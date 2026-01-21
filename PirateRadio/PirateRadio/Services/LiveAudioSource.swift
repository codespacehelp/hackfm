//
//  LiveAudioSource.swift
//  PirateRadio
//
//  AVAudioEngine-based live audio capture from input devices
//

import AVFoundation
import CoreAudio
import Foundation

/// Audio source that captures live audio from an input device
final class LiveAudioSource: AudioSource {
    // MARK: - Constants

    /// Internal buffer size in samples (holds ~100ms of audio)
    private static let bufferCapacity = 4800

    // MARK: - Properties

    private let device: AudioInputDevice
    private var audioEngine: AVAudioEngine?
    private var sampleBuffer: RingBuffer<Float>

    private(set) var state: AudioSourceState = .idle
    private var currentLevel: Float = 0

    weak var delegate: AudioSourceDelegate?

    // MARK: - AudioSource Protocol

    var sampleRate: Double { Self.defaultSampleRate }

    var isFinite: Bool { false }

    var duration: TimeInterval? { nil }

    var currentPosition: TimeInterval? { nil }

    var displayName: String { device.displayName }

    /// Current audio level (0.0 to 1.0) for metering
    var audioLevel: Float { currentLevel }

    // MARK: - Initialization

    /// Creates a live audio source for the specified input device
    /// - Parameter device: The audio input device to capture from
    init(device: AudioInputDevice) {
        self.device = device
        self.sampleBuffer = RingBuffer(capacity: Self.bufferCapacity, defaultValue: Float(0))
    }

    // MARK: - Public Methods

    func prepare() async throws {
        guard case .idle = state else {
            if case .ready = state { return }
            throw AudioSourceError.alreadyStreaming
        }

        setState(.preparing)

        do {
            try await setupAudioEngine()
            setState(.ready)
        } catch {
            setState(.error(error.localizedDescription))
            throw error
        }
    }

    func readSamples(maxSamples: Int) async throws -> [Float]? {
        guard case .ready = state else {
            if case .streaming = state {
                // Continue reading in streaming state
                return readFromBuffer(maxSamples: maxSamples)
            }
            if case .finished = state {
                return nil
            }
            throw AudioSourceError.notReady
        }

        setState(.streaming)

        // Start the audio engine if not running
        if let engine = audioEngine, !engine.isRunning {
            try engine.start()
        }

        return readFromBuffer(maxSamples: maxSamples)
    }

    func stop() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        sampleBuffer.close()
        setState(.finished)
    }

    func reset() throws {
        stop()
        sampleBuffer = RingBuffer(capacity: Self.bufferCapacity, defaultValue: Float(0))
        state = .idle
    }

    // MARK: - Private Methods

    private func setupAudioEngine() async throws {
        let engine = AVAudioEngine()

        // Set the input device
        try setInputDevice(device.id, for: engine)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        // Create target format (mono, 48kHz, float32)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.defaultSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioSourceError.captureError("Failed to create target audio format")
        }

        // Install tap with conversion if needed
        let needsConversion = inputFormat.sampleRate != targetFormat.sampleRate ||
                              inputFormat.channelCount != 1

        if needsConversion {
            // Create converter
            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw AudioSourceError.captureError("Failed to create audio converter")
            }

            // Calculate buffer size for tap (50ms of input)
            let tapBufferSize = AVAudioFrameCount(inputFormat.sampleRate * 0.05)

            inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: inputFormat) {
                [weak self] buffer, _ in
                self?.processInputBuffer(buffer, converter: converter, targetFormat: targetFormat)
            }
        } else {
            // No conversion needed
            let tapBufferSize = AVAudioFrameCount(Self.defaultSampleRate * 0.05) // 50ms

            inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: inputFormat) {
                [weak self] buffer, _ in
                self?.processInputBufferDirect(buffer)
            }
        }

        // Prepare the engine
        engine.prepare()

        self.audioEngine = engine
    }

    private func setInputDevice(_ deviceID: AudioDeviceID, for engine: AVAudioEngine) throws {
        let audioUnit = engine.inputNode.audioUnit!

        var deviceIDVar = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIDVar,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw AudioSourceError.captureError("Failed to set input device (error: \(status))")
        }
    }

    private func processInputBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        // Calculate output frame count
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return
        }

        var error: NSError?
        var inputBufferUsed = false

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputBufferUsed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputBufferUsed = true
            outStatus.pointee = .haveData
            return buffer
        }

        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        guard status != .error, outputBuffer.frameLength > 0 else { return }

        // Extract samples and add to buffer
        if let samples = extractSamples(from: outputBuffer) {
            addSamplesToBuffer(samples)
        }
    }

    private func processInputBufferDirect(_ buffer: AVAudioPCMBuffer) {
        if let samples = extractSamples(from: buffer) {
            addSamplesToBuffer(samples)
        }
    }

    private func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        // If stereo, mix to mono
        if buffer.format.channelCount > 1 {
            var monoSamples = [Float](repeating: 0, count: frameLength)
            let channelCount = Int(buffer.format.channelCount)

            for i in 0..<frameLength {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += channelData[ch][i]
                }
                monoSamples[i] = sum / Float(channelCount)
            }
            return monoSamples
        }

        return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
    }

    private func addSamplesToBuffer(_ samples: [Float]) {
        // Calculate audio level for metering
        let level = samples.map { abs($0) }.max() ?? 0
        currentLevel = level

        // Notify delegate of level update
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.audioSource(self, didUpdateLevel: level)
        }

        // Write to ring buffer (non-blocking to avoid glitches)
        sampleBuffer.writeNonBlocking(samples)
    }

    private func readFromBuffer(maxSamples: Int) -> [Float]? {
        // Read available samples (blocking if needed)
        let samples = sampleBuffer.read(maxCount: maxSamples)

        if samples.isEmpty && sampleBuffer.closed {
            return nil
        }

        return samples.isEmpty ? nil : samples
    }

    private func setState(_ newState: AudioSourceState) {
        state = newState
        delegate?.audioSource(self, didChangeState: newState)
    }
}
