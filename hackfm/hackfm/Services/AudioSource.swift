//
//  AudioSource.swift
//  HackFM
//
//  Protocol definition for audio sources (file or live input)
//

import Foundation

/// State of an audio source
enum AudioSourceState: Equatable {
    case idle
    case preparing
    case ready
    case streaming
    case finished
    case error(String)

    var description: String {
        switch self {
        case .idle:
            return "Idle"
        case .preparing:
            return "Preparing..."
        case .ready:
            return "Ready"
        case .streaming:
            return "Streaming"
        case .finished:
            return "Finished"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

/// Error types for audio sources
enum AudioSourceError: Error, LocalizedError {
    case notReady
    case alreadyStreaming
    case fileNotFound
    case invalidFormat
    case readError(String)
    case captureError(String)
    case endOfFile

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Audio source is not ready"
        case .alreadyStreaming:
            return "Audio source is already streaming"
        case .fileNotFound:
            return "Audio file not found"
        case .invalidFormat:
            return "Invalid audio format"
        case .readError(let reason):
            return "Failed to read audio: \(reason)"
        case .captureError(let reason):
            return "Failed to capture audio: \(reason)"
        case .endOfFile:
            return "End of audio file reached"
        }
    }
}

/// Protocol for audio sources that can provide samples for FM modulation
protocol AudioSource: AnyObject {
    /// Current state of the audio source
    var state: AudioSourceState { get }

    /// Sample rate of the audio source (always 48000 for FM transmission)
    var sampleRate: Double { get }

    /// Whether this source has a finite duration (true for files, false for live)
    var isFinite: Bool { get }

    /// Total duration in seconds (nil for infinite sources)
    var duration: TimeInterval? { get }

    /// Current playback position in seconds (nil for live sources)
    var currentPosition: TimeInterval? { get }

    /// Display name for the source
    var displayName: String { get }

    /// Prepares the source for streaming
    func prepare() async throws

    /// Reads up to maxSamples audio samples
    /// - Parameter maxSamples: Maximum number of samples to read
    /// - Returns: Array of float samples, or nil if end of stream/closed
    func readSamples(maxSamples: Int) async throws -> [Float]?

    /// Stops the audio source and releases resources
    func stop()

    /// Resets the source to the beginning (for file sources)
    func reset() throws
}

/// Extension with default implementations
extension AudioSource {
    /// Default sample rate for FM transmission
    static var defaultSampleRate: Double { 48000 }

    /// Convenience method to check if source is ready to stream
    var isReady: Bool {
        if case .ready = state { return true }
        if case .streaming = state { return true }
        return false
    }

    /// Convenience method to check if source has finished
    var isFinished: Bool {
        if case .finished = state { return true }
        return false
    }

    /// Convenience method to check if source has an error
    var hasError: Bool {
        if case .error = state { return true }
        return false
    }
}

/// Delegate protocol for audio source events
protocol AudioSourceDelegate: AnyObject {
    /// Called when the audio source state changes
    func audioSource(_ source: AudioSource, didChangeState state: AudioSourceState)

    /// Called when new audio level is available (for live input monitoring)
    func audioSource(_ source: AudioSource, didUpdateLevel level: Float)

    /// Called when the audio source finishes (for finite sources)
    func audioSourceDidFinish(_ source: AudioSource)
}

/// Optional delegate methods
extension AudioSourceDelegate {
    func audioSource(_ source: AudioSource, didChangeState state: AudioSourceState) {}
    func audioSource(_ source: AudioSource, didUpdateLevel level: Float) {}
    func audioSourceDidFinish(_ source: AudioSource) {}
}
