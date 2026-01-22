//
//  AudioProcessor.swift
//  HackFM
//
//  Handles audio file loading and conversion using AVFoundation
//

import AVFoundation
import Foundation

/// Result of audio processing containing samples and metadata
struct ProcessedAudio {
    let samples: [Float]        // Mono audio samples normalized to [-1.0, 1.0]
    let sampleRate: Double      // Sample rate (always 48000)
    let duration: TimeInterval  // Duration in seconds

    var sampleCount: Int {
        return samples.count
    }
}

/// Error types for audio processing
enum AudioProcessorError: Error, LocalizedError {
    case fileNotFound
    case unsupportedFormat
    case conversionFailed(String)
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .unsupportedFormat:
            return "Unsupported audio format. Please use WAV, MP3, or AIFF."
        case .conversionFailed(let reason):
            return "Audio conversion failed: \(reason)"
        case .emptyFile:
            return "Audio file is empty or could not be read"
        }
    }
}

/// Processes audio files for FM transmission
final class AudioProcessor {
    // MARK: - Constants

    /// Target sample rate for FM transmission
    static let targetSampleRate: Double = 48000

    /// Target format: mono, 32-bit float, 48kHz
    private static var targetFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!
    }

    // MARK: - Public Methods

    /// Loads and converts an audio file to mono 48kHz float samples
    /// - Parameter url: URL of the audio file (WAV, MP3, AIFF)
    /// - Returns: ProcessedAudio containing normalized samples
    func loadAudio(from url: URL) throws -> ProcessedAudio {
        // Open the audio file
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain {
                throw AudioProcessorError.fileNotFound
            }
            throw AudioProcessorError.unsupportedFormat
        }

        let sourceFormat = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard frameCount > 0 else {
            throw AudioProcessorError.emptyFile
        }

        // Check if conversion is needed
        let targetFormat = Self.targetFormat

        if sourceFormat.sampleRate == targetFormat.sampleRate &&
           sourceFormat.channelCount == 1 &&
           sourceFormat.commonFormat == .pcmFormatFloat32 {
            // No conversion needed - read directly
            return try readDirectly(from: audioFile, frameCount: frameCount)
        } else {
            // Conversion needed
            return try convertAudio(from: audioFile, sourceFormat: sourceFormat, frameCount: frameCount)
        }
    }

    /// Gets audio file information without loading samples
    /// - Parameter url: URL of the audio file
    /// - Returns: Tuple of (duration, format description)
    func getFileInfo(from url: URL) throws -> (duration: TimeInterval, format: String) {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let duration = Double(audioFile.length) / format.sampleRate

        let formatDescription = "\(Int(format.sampleRate))Hz, \(format.channelCount) ch"
        return (duration, formatDescription)
    }

    // MARK: - Private Methods

    private func readDirectly(from audioFile: AVAudioFile, frameCount: AVAudioFrameCount) throws -> ProcessedAudio {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: frameCount) else {
            throw AudioProcessorError.conversionFailed("Failed to create audio buffer")
        }

        do {
            try audioFile.read(into: buffer)
        } catch {
            throw AudioProcessorError.conversionFailed("Failed to read audio data: \(error.localizedDescription)")
        }

        let samples = extractSamples(from: buffer)
        let duration = Double(samples.count) / Self.targetSampleRate

        return ProcessedAudio(
            samples: samples,
            sampleRate: Self.targetSampleRate,
            duration: duration
        )
    }

    private func convertAudio(
        from audioFile: AVAudioFile,
        sourceFormat: AVAudioFormat,
        frameCount: AVAudioFrameCount
    ) throws -> ProcessedAudio {
        let targetFormat = Self.targetFormat

        // Create converter
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioProcessorError.conversionFailed("Could not create audio converter")
        }

        // Read source audio into buffer
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw AudioProcessorError.conversionFailed("Failed to create source buffer")
        }

        do {
            try audioFile.read(into: sourceBuffer)
        } catch {
            throw AudioProcessorError.conversionFailed("Failed to read audio: \(error.localizedDescription)")
        }

        // Calculate output frame count based on sample rate ratio
        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(frameCount) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            throw AudioProcessorError.conversionFailed("Failed to create output buffer")
        }

        // Perform conversion
        var error: NSError?
        var allSamples: [Float] = []

        // Use input block for conversion
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

        // Convert in chunks to handle large files
        let chunkSize: AVAudioFrameCount = 8192
        var totalFramesConverted: AVAudioFrameCount = 0

        while totalFramesConverted < outputFrameCount {
            let remainingFrames = outputFrameCount - totalFramesConverted
            let framesToConvert = min(chunkSize, remainingFrames)

            guard let chunkBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: framesToConvert) else {
                break
            }

            let status = converter.convert(to: chunkBuffer, error: &error, withInputFrom: inputBlock)

            if let error = error {
                throw AudioProcessorError.conversionFailed(error.localizedDescription)
            }

            if status == .error {
                throw AudioProcessorError.conversionFailed("Conversion error")
            }

            if chunkBuffer.frameLength > 0 {
                let chunkSamples = extractSamples(from: chunkBuffer)
                allSamples.append(contentsOf: chunkSamples)
                totalFramesConverted += chunkBuffer.frameLength
            }

            if status == .endOfStream || status == .inputRanDry {
                break
            }
        }

        guard !allSamples.isEmpty else {
            throw AudioProcessorError.emptyFile
        }

        let duration = Double(allSamples.count) / Self.targetSampleRate

        return ProcessedAudio(
            samples: allSamples,
            sampleRate: Self.targetSampleRate,
            duration: duration
        )
    }

    private func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }

        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        // Normalize samples to [-1.0, 1.0] range if needed
        let maxMagnitude = samples.map { abs($0) }.max() ?? 1.0
        if maxMagnitude > 1.0 {
            return samples.map { $0 / maxMagnitude }
        }

        return samples
    }
}
