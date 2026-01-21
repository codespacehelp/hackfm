//
//  FMModulator.swift
//  PirateRadio
//
//  Converts audio samples to FM-modulated IQ data for HackRF transmission
//

import Foundation
import Accelerate

/// Progress callback for modulation progress updates
typealias ModulationProgressCallback = (Double) -> Void

/// FM modulator that converts audio samples to IQ data
final class FMModulator {
    // MARK: - Constants

    /// FM broadcast frequency deviation (±75 kHz)
    private static let frequencyDeviation: Double = 75_000

    /// HackRF sample rate (2 MSPS)
    private static let sampleRate: Double = 2_000_000

    /// Audio sample rate (48 kHz)
    private static let audioSampleRate: Double = 48_000

    /// Upsample ratio from audio to IQ sample rate
    private static let upsampleRatio: Double = sampleRate / audioSampleRate  // ~41.67

    // MARK: - Properties

    private var phase: Double = 0

    // MARK: - Public Methods

    /// Converts audio samples to FM-modulated IQ data
    /// - Parameters:
    ///   - audioSamples: Normalized audio samples in range [-1.0, 1.0]
    ///   - onProgress: Optional callback for progress updates
    /// - Returns: Interleaved IQ samples as Int8 values
    func modulate(audioSamples: [Float], onProgress: ModulationProgressCallback? = nil) -> [Int8] {
        // Calculate output size
        let outputSamplesPerAudioSample = Int(ceil(Self.upsampleRatio))
        let totalIQSamples = audioSamples.count * outputSamplesPerAudioSample
        let totalBytes = totalIQSamples * 2  // I and Q for each sample

        // Pre-allocate output array
        var iqData = [Int8](repeating: 0, count: totalBytes)

        // Phase increment scale factor
        // For FM: phase_increment = 2π × deviation × audio_sample / sample_rate
        let phaseScale = 2.0 * Double.pi * Self.frequencyDeviation / Self.sampleRate

        // Process in chunks for progress reporting
        let chunkSize = 10000
        var iqIndex = 0
        var lastReportedProgress = 0.0

        for (audioIndex, audioSample) in audioSamples.enumerated() {
            // Calculate phase increment for this audio sample
            let phaseIncrement = phaseScale * Double(audioSample)

            // Generate upsampled IQ pairs for this audio sample
            for _ in 0..<outputSamplesPerAudioSample {
                // Update phase
                phase += phaseIncrement

                // Wrap phase to [-π, π] for numerical stability
                if phase > Double.pi {
                    phase -= 2.0 * Double.pi
                } else if phase < -Double.pi {
                    phase += 2.0 * Double.pi
                }

                // Generate I and Q components
                let i = cos(phase)
                let q = sin(phase)

                // Convert to Int8 range [-127, 127]
                // Using 127 instead of 128 to avoid overflow
                iqData[iqIndex] = Int8(clamping: Int(i * 127.0))
                iqData[iqIndex + 1] = Int8(clamping: Int(q * 127.0))
                iqIndex += 2

                // Bounds check
                if iqIndex >= totalBytes {
                    break
                }
            }

            // Report progress periodically
            if let onProgress = onProgress, audioIndex % chunkSize == 0 {
                let progress = Double(audioIndex) / Double(audioSamples.count)
                if progress - lastReportedProgress >= 0.01 {
                    onProgress(progress)
                    lastReportedProgress = progress
                }
            }
        }

        // Trim to actual size used
        if iqIndex < totalBytes {
            iqData.removeLast(totalBytes - iqIndex)
        }

        // Report completion
        onProgress?(1.0)

        return iqData
    }

    /// Resets the modulator phase (call between transmissions)
    func reset() {
        phase = 0
    }

    /// Estimates the memory required for IQ data
    /// - Parameter audioSampleCount: Number of audio samples
    /// - Returns: Estimated memory in bytes
    static func estimateMemoryUsage(audioSampleCount: Int) -> Int {
        let outputSamplesPerAudioSample = Int(ceil(upsampleRatio))
        return audioSampleCount * outputSamplesPerAudioSample * 2
    }

    /// Estimates the memory required for audio duration
    /// - Parameter duration: Audio duration in seconds
    /// - Returns: Estimated memory in bytes
    static func estimateMemoryUsage(duration: TimeInterval) -> Int {
        let audioSampleCount = Int(duration * audioSampleRate)
        return estimateMemoryUsage(audioSampleCount: audioSampleCount)
    }

    /// Formats memory size for display
    /// - Parameter bytes: Size in bytes
    /// - Returns: Human-readable string (e.g., "512 MB")
    static func formatMemorySize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
