//
//  StreamingPipeline.swift
//  PirateRadio
//
//  Coordinates audio source → FM modulation → IQ buffer flow
//

import Foundation

/// State of the streaming pipeline
enum StreamingPipelineState: Equatable {
    case idle
    case preparing
    case running
    case paused
    case stopping
    case stopped
    case error(String)

    var description: String {
        switch self {
        case .idle: return "Idle"
        case .preparing: return "Preparing..."
        case .running: return "Streaming"
        case .paused: return "Paused"
        case .stopping: return "Stopping..."
        case .stopped: return "Stopped"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

/// Progress callback for pipeline streaming
typealias StreamingProgressCallback = (Double) -> Void

/// Delegate for pipeline events
protocol StreamingPipelineDelegate: AnyObject {
    func pipeline(_ pipeline: StreamingPipeline, didChangeState state: StreamingPipelineState)
    func pipeline(_ pipeline: StreamingPipeline, didUpdateProgress progress: Double)
    func pipelineDidFinish(_ pipeline: StreamingPipeline)
}

/// Optional delegate methods
extension StreamingPipelineDelegate {
    func pipeline(_ pipeline: StreamingPipeline, didChangeState state: StreamingPipelineState) {}
    func pipeline(_ pipeline: StreamingPipeline, didUpdateProgress progress: Double) {}
    func pipelineDidFinish(_ pipeline: StreamingPipeline) {}
}

/// Orchestrates the flow from audio source through FM modulation to IQ buffer
final class StreamingPipeline {
    // MARK: - Constants

    /// Audio chunk size in samples (50ms at 48kHz = 2400 samples)
    private static let audioChunkSize = 2400

    /// IQ buffer size in bytes (~130ms at 2MSPS = 512KB)
    private static let iqBufferSize = 512 * 1024

    /// Low water mark - start producing when buffer falls below this
    private static let lowWaterMark = 128 * 1024

    // MARK: - Properties

    private let audioSource: AudioSource
    private let modulator: FMModulator
    private let iqBuffer: IQRingBuffer

    private var producerTask: Task<Void, Never>?
    private var isProducing = false

    private(set) var state: StreamingPipelineState = .idle

    weak var delegate: StreamingPipelineDelegate?

    /// Progress callback for finite sources
    var onProgress: StreamingProgressCallback?

    // MARK: - Public Properties

    /// The IQ ring buffer for HackRF to consume from
    var buffer: IQRingBuffer { iqBuffer }

    /// Whether the source is finite (file) or infinite (live)
    var isFiniteSource: Bool { audioSource.isFinite }

    /// Total duration for finite sources
    var duration: TimeInterval? { audioSource.duration }

    /// Current position for finite sources
    var currentPosition: TimeInterval? { audioSource.currentPosition }

    /// Display name of the audio source
    var sourceName: String { audioSource.displayName }

    // MARK: - Initialization

    /// Creates a streaming pipeline with the given audio source
    /// - Parameter audioSource: The audio source to stream from
    init(audioSource: AudioSource) {
        self.audioSource = audioSource
        self.modulator = FMModulator()
        self.iqBuffer = IQRingBuffer(capacityBytes: Self.iqBufferSize)
    }

    // MARK: - Public Methods

    /// Prepares the pipeline for streaming
    func prepare() async throws {
        switch state {
        case .idle:
            break
        case .stopped:
            // Allow re-preparing after stop
            setState(.idle)
        default:
            return
        }

        setState(.preparing)

        do {
            try await audioSource.prepare()
            modulator.reset()
            iqBuffer.reset()
            setState(.running)
        } catch {
            setState(.error(error.localizedDescription))
            throw error
        }
    }

    /// Starts the producer task that feeds the IQ buffer
    func start() {
        guard case .running = state else { return }
        guard producerTask == nil else { return }

        isProducing = true

        producerTask = Task.detached { [weak self] in
            await self?.producerLoop()
        }
    }

    /// Stops the pipeline and releases resources
    func stop() {
        guard state == .running || state == .paused else { return }

        setState(.stopping)
        isProducing = false

        // Cancel producer task
        producerTask?.cancel()
        producerTask = nil

        // Close buffer to wake up any waiting consumers
        iqBuffer.close()

        // Stop audio source
        audioSource.stop()

        setState(.stopped)
    }

    /// Pauses the pipeline (for finite sources)
    func pause() {
        guard case .running = state else { return }
        isProducing = false
        setState(.paused)
    }

    /// Resumes the pipeline after pause
    func resume() {
        guard case .paused = state else { return }
        isProducing = true
        setState(.running)
    }

    /// Resets the pipeline for replay (finite sources only)
    func reset() throws {
        guard audioSource.isFinite else { return }

        stop()

        try audioSource.reset()
        modulator.reset()
        iqBuffer.reset()

        setState(.idle)
    }

    // MARK: - Buffer Reading (for HackRF callback)

    /// Fills a buffer with IQ data for transmission
    /// This is called from the HackRF callback thread
    /// - Parameters:
    ///   - buffer: Destination buffer pointer
    ///   - length: Number of bytes to fill
    /// - Returns: Number of bytes actually filled (0 if finished/closed)
    func fillBuffer(_ buffer: UnsafeMutablePointer<Int8>, length: Int) -> Int {
        let bytesRead = iqBuffer.readInto(buffer, maxCount: length)

        // Report progress for finite sources
        if let duration = duration, duration > 0, let position = currentPosition {
            let progress = position / duration
            DispatchQueue.main.async { [weak self] in
                self?.onProgress?(progress)
                self?.delegate?.pipeline(self!, didUpdateProgress: progress)
            }
        }

        return bytesRead
    }

    /// Non-blocking buffer fill for polling mode
    /// - Parameters:
    ///   - buffer: Destination buffer pointer
    ///   - length: Number of bytes to fill
    /// - Returns: Number of bytes actually filled
    func fillBufferNonBlocking(_ buffer: UnsafeMutablePointer<Int8>, length: Int) -> Int {
        // Read available data without blocking
        let data = iqBuffer.readNonBlocking(maxCount: length)

        guard !data.isEmpty else { return 0 }

        data.withUnsafeBytes { ptr in
            buffer.initialize(from: ptr.bindMemory(to: Int8.self).baseAddress!, count: data.count)
        }

        return data.count
    }

    /// Check if pipeline has finished producing
    var isFinished: Bool {
        if case .stopped = state { return true }
        if audioSource.isFinished && iqBuffer.isEmpty { return true }
        return false
    }

    /// Available IQ data in buffer
    var availableData: Int {
        iqBuffer.availableData
    }

    // MARK: - Private Methods

    private func producerLoop() async {
        while isProducing && !Task.isCancelled {
            // Check if buffer needs more data
            if iqBuffer.availableSpace < Self.lowWaterMark {
                // Buffer is getting full, wait a bit
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                continue
            }

            // Read audio chunk
            do {
                guard let audioSamples = try await audioSource.readSamples(maxSamples: Self.audioChunkSize) else {
                    // End of audio source
                    await handleSourceFinished()
                    break
                }

                // Modulate to IQ
                let iqData = modulator.modulateChunk(audioSamples)

                // Write to buffer
                iqBuffer.write(iqData)

            } catch {
                await handleError(error)
                break
            }
        }
    }

    @MainActor
    private func handleSourceFinished() {
        // For finite sources, signal completion once buffer is drained
        if audioSource.isFinite {
            delegate?.pipelineDidFinish(self)
            onProgress?(1.0)
        }
        // For live sources, this shouldn't happen normally
    }

    @MainActor
    private func handleError(_ error: Error) {
        setState(.error(error.localizedDescription))
    }

    private func setState(_ newState: StreamingPipelineState) {
        state = newState
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.pipeline(self, didChangeState: newState)
        }
    }
}
