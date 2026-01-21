//
//  FileAudioSource.swift
//  PirateRadio
//
//  Chunk-based file reading for streaming audio from files
//

import AVFoundation
import Foundation

/// Audio source that reads from audio files in chunks
final class FileAudioSource: AudioSource {
    // MARK: - Constants

    /// Default chunk size in samples (50ms at 48kHz)
    private static let defaultChunkSize: Int = 2400

    /// Target format: mono, 32-bit float, 48kHz
    private static var targetFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: defaultSampleRate,
            channels: 1,
            interleaved: false
        )!
    }

    // MARK: - Properties

    private let fileURL: URL
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var sourceBuffer: AVAudioPCMBuffer?

    private var currentFramePosition: AVAudioFramePosition = 0
    private var totalFrames: AVAudioFrameCount = 0
    private var needsConversion: Bool = false

    private(set) var state: AudioSourceState = .idle

    weak var delegate: AudioSourceDelegate?

    // MARK: - AudioSource Protocol

    var sampleRate: Double { Self.defaultSampleRate }

    var isFinite: Bool { true }

    var duration: TimeInterval? {
        guard totalFrames > 0 else { return nil }
        return Double(totalFrames) / sampleRate
    }

    var currentPosition: TimeInterval? {
        guard totalFrames > 0 else { return nil }
        return Double(currentFramePosition) / sampleRate
    }

    var displayName: String {
        fileURL.lastPathComponent
    }

    // MARK: - Initialization

    /// Creates a file audio source for the specified URL
    /// - Parameter url: URL of the audio file (WAV, MP3, AIFF)
    init(url: URL) {
        self.fileURL = url
    }

    // MARK: - Public Methods

    func prepare() async throws {
        guard case .idle = state else {
            if case .ready = state { return }
            throw AudioSourceError.alreadyStreaming
        }

        setState(.preparing)

        do {
            // Open the audio file
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw AudioSourceError.fileNotFound
            }

            let file = try AVAudioFile(forReading: fileURL)
            audioFile = file

            let sourceFormat = file.processingFormat
            totalFrames = AVAudioFrameCount(file.length)

            guard totalFrames > 0 else {
                throw AudioSourceError.invalidFormat
            }

            // Check if conversion is needed
            let targetFormat = Self.targetFormat
            needsConversion = !(
                sourceFormat.sampleRate == targetFormat.sampleRate &&
                sourceFormat.channelCount == 1 &&
                sourceFormat.commonFormat == .pcmFormatFloat32
            )

            if needsConversion {
                // Create converter
                guard let conv = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                    throw AudioSourceError.invalidFormat
                }
                converter = conv

                // Calculate total output frames after conversion
                let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
                totalFrames = AVAudioFrameCount(Double(totalFrames) * ratio)
            }

            setState(.ready)
        } catch let error as AudioSourceError {
            setState(.error(error.localizedDescription))
            throw error
        } catch {
            let sourceError = AudioSourceError.readError(error.localizedDescription)
            setState(.error(sourceError.localizedDescription))
            throw sourceError
        }
    }

    func readSamples(maxSamples: Int) async throws -> [Float]? {
        guard case .ready = state, let file = audioFile else {
            if case .streaming = state, let file = audioFile {
                // Continue reading in streaming state
                return try await readChunk(from: file, maxSamples: maxSamples)
            }
            if case .finished = state {
                return nil
            }
            throw AudioSourceError.notReady
        }

        setState(.streaming)
        return try await readChunk(from: file, maxSamples: maxSamples)
    }

    func stop() {
        setState(.finished)
        audioFile = nil
        converter = nil
        sourceBuffer = nil
    }

    func reset() throws {
        guard let file = audioFile else {
            // Re-prepare if file was closed
            state = .idle
            currentFramePosition = 0
            return
        }

        file.framePosition = 0
        currentFramePosition = 0

        if case .finished = state {
            setState(.ready)
        }
    }

    // MARK: - File Info

    /// Gets file information without preparing for streaming
    /// - Returns: Tuple of (duration, format description)
    func getFileInfo() throws -> (duration: TimeInterval, format: String) {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let duration = Double(file.length) / format.sampleRate

        let formatDescription = "\(Int(format.sampleRate))Hz, \(format.channelCount) ch"
        return (duration, formatDescription)
    }

    // MARK: - Private Methods

    private func readChunk(from file: AVAudioFile, maxSamples: Int) async throws -> [Float]? {
        // Check if we've reached the end
        let remainingSourceFrames = AVAudioFrameCount(file.length) - AVAudioFrameCount(file.framePosition)
        if remainingSourceFrames == 0 {
            setState(.finished)
            delegate?.audioSourceDidFinish(self)
            return nil
        }

        if needsConversion {
            return try readWithConversion(from: file, maxSamples: maxSamples)
        } else {
            return try readDirect(from: file, maxSamples: maxSamples)
        }
    }

    private func readDirect(from file: AVAudioFile, maxSamples: Int) throws -> [Float]? {
        let framesToRead = min(
            AVAudioFrameCount(maxSamples),
            AVAudioFrameCount(file.length - file.framePosition)
        )

        guard framesToRead > 0 else {
            setState(.finished)
            delegate?.audioSourceDidFinish(self)
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: framesToRead) else {
            throw AudioSourceError.readError("Failed to create buffer")
        }

        try file.read(into: buffer, frameCount: framesToRead)

        currentFramePosition += AVAudioFramePosition(buffer.frameLength)

        return extractSamples(from: buffer)
    }

    private func readWithConversion(from file: AVAudioFile, maxSamples: Int) throws -> [Float]? {
        guard let converter = converter else {
            throw AudioSourceError.readError("No converter available")
        }

        let sourceFormat = file.processingFormat
        let targetFormat = Self.targetFormat

        // Calculate source frames needed
        let ratio = sourceFormat.sampleRate / targetFormat.sampleRate
        let sourceFramesNeeded = AVAudioFrameCount(ceil(Double(maxSamples) * ratio))
        let sourceFramesToRead = min(
            sourceFramesNeeded,
            AVAudioFrameCount(file.length - file.framePosition)
        )

        guard sourceFramesToRead > 0 else {
            setState(.finished)
            delegate?.audioSourceDidFinish(self)
            return nil
        }

        // Read source audio
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: sourceFramesToRead) else {
            throw AudioSourceError.readError("Failed to create source buffer")
        }

        try file.read(into: sourceBuffer, frameCount: sourceFramesToRead)

        // Prepare output buffer
        let outputFrameCount = AVAudioFrameCount(Double(sourceBuffer.frameLength) / ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            throw AudioSourceError.readError("Failed to create output buffer")
        }

        // Convert
        var error: NSError?
        var inputBufferUsed = false

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputBufferUsed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputBufferUsed = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            throw AudioSourceError.readError(error.localizedDescription)
        }

        if status == .error {
            throw AudioSourceError.readError("Conversion failed")
        }

        currentFramePosition += AVAudioFramePosition(outputBuffer.frameLength)

        guard outputBuffer.frameLength > 0 else {
            setState(.finished)
            delegate?.audioSourceDidFinish(self)
            return nil
        }

        return extractSamples(from: outputBuffer)
    }

    private func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else {
            return nil
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        var samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        // Normalize if needed
        let maxMagnitude = samples.map { abs($0) }.max() ?? 1.0
        if maxMagnitude > 1.0 {
            samples = samples.map { $0 / maxMagnitude }
        }

        return samples
    }

    private func setState(_ newState: AudioSourceState) {
        state = newState
        delegate?.audioSource(self, didChangeState: newState)
    }
}
