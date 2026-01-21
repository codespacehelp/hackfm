//
//  HackRFWrapper.swift
//  PirateRadio
//
//  Swift wrapper around the libhackrf C API for HackRF One device control
//

import Foundation

/// Progress callback type for transmission updates
typealias TransmissionProgressCallback = (Double) -> Void

/// Wrapper class for HackRF One device operations
final class HackRFWrapper {
    // MARK: - Constants

    private static let sampleRate: UInt32 = 2_000_000  // 2 MSPS
    private static let txGain: UInt32 = 20  // 20 dB TX gain (conservative)
    private static let txVgaGain: UInt32 = 47  // TX VGA gain (0-47)

    // MARK: - Properties

    private var device: OpaquePointer?
    private var isTransmitting = false

    // Pre-computed mode properties
    private var iqData: [Int8] = []
    private var iqDataIndex = 0
    private var progressCallback: TransmissionProgressCallback?

    // Streaming mode properties
    private var streamingPipeline: StreamingPipeline?
    private var isStreamingMode = false

    // Singleton for callback access (C callbacks can't capture Swift context)
    // Must be fileprivate so the C callback function can access it
    fileprivate static var activeInstance: HackRFWrapper?

    // MARK: - Initialization

    init() throws {
        let result = hackrf_init()
        guard result == HACKRF_SUCCESS.rawValue else {
            throw HackRFError.initializationFailed(code: result)
        }
    }

    deinit {
        if isTransmitting {
            try? stopTransmission()
        }
        if device != nil {
            hackrf_close(device)
        }
        hackrf_exit()
    }

    // MARK: - Device Management

    /// Opens the HackRF device
    func open() throws {
        guard device == nil else {
            throw HackRFError.alreadyOpen
        }

        let result = hackrf_open(&device)
        guard result == HACKRF_SUCCESS.rawValue else {
            if result == HACKRF_ERROR_NOT_FOUND.rawValue {
                throw HackRFError.deviceNotFound
            }
            throw HackRFError.openFailed(code: result)
        }
    }

    /// Closes the HackRF device
    func close() {
        if isTransmitting {
            try? stopTransmission()
        }
        if device != nil {
            hackrf_close(device)
            device = nil
        }
    }

    /// Checks if device is currently open
    var isOpen: Bool {
        return device != nil
    }

    /// Checks if device is currently transmitting
    var transmitting: Bool {
        return isTransmitting
    }

    // MARK: - Configuration

    /// Configures the HackRF for FM transmission at the specified frequency
    /// - Parameter frequencyHz: Center frequency in Hz (e.g., 100_100_000 for 100.1 MHz)
    func configure(frequencyHz: UInt64) throws {
        guard let device = device else {
            throw HackRFError.notOpen
        }

        // Set sample rate
        var result = hackrf_set_sample_rate(device, Double(Self.sampleRate))
        guard result == HACKRF_SUCCESS.rawValue else {
            throw HackRFError.configurationFailed(parameter: "sample rate", code: result)
        }

        // Set center frequency
        result = hackrf_set_freq(device, frequencyHz)
        guard result == HACKRF_SUCCESS.rawValue else {
            throw HackRFError.configurationFailed(parameter: "frequency", code: result)
        }

        // Set TX VGA gain
        result = hackrf_set_txvga_gain(device, Self.txVgaGain)
        guard result == HACKRF_SUCCESS.rawValue else {
            throw HackRFError.configurationFailed(parameter: "TX VGA gain", code: result)
        }

        // Enable antenna power (for external amplifier if connected)
        result = hackrf_set_antenna_enable(device, 0)
        guard result == HACKRF_SUCCESS.rawValue else {
            throw HackRFError.configurationFailed(parameter: "antenna", code: result)
        }
    }

    // MARK: - Transmission

    /// Starts FM transmission with pre-computed IQ data
    /// - Parameters:
    ///   - iqData: Interleaved I/Q samples as Int8 values
    ///   - onProgress: Callback for progress updates (0.0 to 1.0)
    func startTransmission(iqData: [Int8], onProgress: @escaping TransmissionProgressCallback) throws {
        guard let device = device else {
            throw HackRFError.notOpen
        }

        guard !isTransmitting else {
            throw HackRFError.transmissionInProgress
        }

        guard !iqData.isEmpty else {
            throw HackRFError.noDataToTransmit
        }

        // Store data for callback access
        self.iqData = iqData
        self.iqDataIndex = 0
        self.progressCallback = onProgress
        Self.activeInstance = self

        // Start transmission
        let result = hackrf_start_tx(device, txCallback, nil)
        guard result == HACKRF_SUCCESS.rawValue else {
            Self.activeInstance = nil
            throw HackRFError.transmissionFailed(code: result)
        }

        isTransmitting = true
    }

    /// Starts FM transmission in streaming mode from a pipeline
    /// - Parameters:
    ///   - pipeline: The streaming pipeline providing IQ data
    ///   - onProgress: Callback for progress updates (0.0 to 1.0) for finite sources
    func startStreamingTransmission(
        pipeline: StreamingPipeline,
        onProgress: @escaping TransmissionProgressCallback
    ) throws {
        guard let device = device else {
            throw HackRFError.notOpen
        }

        guard !isTransmitting else {
            throw HackRFError.transmissionInProgress
        }

        // Store pipeline for callback access
        self.streamingPipeline = pipeline
        self.isStreamingMode = true
        self.progressCallback = onProgress
        Self.activeInstance = self

        // Start the pipeline producer
        pipeline.start()

        // Start transmission
        let result = hackrf_start_tx(device, txCallback, nil)
        guard result == HACKRF_SUCCESS.rawValue else {
            Self.activeInstance = nil
            streamingPipeline = nil
            isStreamingMode = false
            throw HackRFError.transmissionFailed(code: result)
        }

        isTransmitting = true
    }

    /// Stops the current transmission
    func stopTransmission() throws {
        guard let device = device else {
            throw HackRFError.notOpen
        }

        if isTransmitting {
            hackrf_stop_tx(device)
            isTransmitting = false
            Self.activeInstance = nil

            // Clean up streaming mode
            if isStreamingMode {
                streamingPipeline?.stop()
                streamingPipeline = nil
                isStreamingMode = false
            }
        }
    }

    // MARK: - Callback Handling

    /// Called by the C callback to fill the transfer buffer
    fileprivate func fillBuffer(_ transfer: UnsafeMutablePointer<hackrf_transfer>) -> Int32 {
        let bufferLength = Int(transfer.pointee.valid_length)
        let buffer = transfer.pointee.buffer!

        if isStreamingMode {
            return fillBufferFromPipeline(buffer, length: bufferLength)
        } else {
            return fillBufferFromPrecomputed(buffer, length: bufferLength)
        }
    }

    /// Fills buffer from pre-computed IQ data array
    private func fillBufferFromPrecomputed(_ buffer: UnsafeMutablePointer<UInt8>, length: Int) -> Int32 {
        // Calculate how much data we can copy
        let remainingData = iqData.count - iqDataIndex
        let bytesToCopy = min(length, remainingData)

        if bytesToCopy > 0 {
            // Copy IQ data to buffer
            iqData.withUnsafeBytes { iqPointer in
                let sourcePtr = iqPointer.baseAddress!.advanced(by: iqDataIndex)
                memcpy(buffer, sourcePtr, bytesToCopy)
            }

            // Zero-fill remainder if needed
            if bytesToCopy < length {
                memset(buffer.advanced(by: bytesToCopy), 0, length - bytesToCopy)
            }

            iqDataIndex += bytesToCopy

            // Report progress
            let progress = Double(iqDataIndex) / Double(iqData.count)
            DispatchQueue.main.async { [weak self] in
                self?.progressCallback?(progress)
            }
        } else {
            // No more data - fill with zeros and signal completion
            memset(buffer, 0, length)

            DispatchQueue.main.async { [weak self] in
                self?.progressCallback?(1.0)
            }

            // Return non-zero to stop transmission
            return -1
        }

        return 0
    }

    /// Fills buffer from streaming pipeline
    private func fillBufferFromPipeline(_ buffer: UnsafeMutablePointer<UInt8>, length: Int) -> Int32 {
        guard let pipeline = streamingPipeline else {
            memset(buffer, 0, length)
            return -1
        }

        // Cast to Int8 pointer for the pipeline
        let int8Buffer = buffer.withMemoryRebound(to: Int8.self, capacity: length) { $0 }

        // Get data from pipeline (this may block briefly if buffer is low)
        let bytesRead = pipeline.fillBuffer(int8Buffer, length: length)

        if bytesRead == 0 {
            // Check if pipeline is finished (for finite sources)
            if pipeline.isFinished {
                memset(buffer, 0, length)
                DispatchQueue.main.async { [weak self] in
                    self?.progressCallback?(1.0)
                }
                return -1
            }

            // Buffer underrun - fill with zeros and continue
            memset(buffer, 0, length)
        } else if bytesRead < length {
            // Partial fill - zero the rest
            memset(buffer.advanced(by: bytesRead), 0, length - bytesRead)
        }

        // Progress is reported by the pipeline via its callback

        return 0
    }
}

// MARK: - C Callback

/// C callback function for HackRF TX
private func txCallback(_ transfer: UnsafeMutablePointer<hackrf_transfer>?) -> Int32 {
    guard let transfer = transfer,
          let instance = HackRFWrapper.activeInstance else {
        return -1
    }
    return instance.fillBuffer(transfer)
}
