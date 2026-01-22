//
//  FMModulator.swift
//  HackFM
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
    static let sampleRate: Double = 2_000_000

    /// Audio sample rate (48 kHz)
    static let audioSampleRate: Double = 48_000

    /// Upsample ratio from audio to IQ sample rate
    private static let upsampleRatio: Double = sampleRate / audioSampleRate  // ~41.67

    /// IQ samples generated per audio sample
    static var iqSamplesPerAudioSample: Int {
        Int(ceil(upsampleRatio))
    }

    // MARK: - Properties

    private var phase: Double = 0

    // MARK: - Public Methods

    /// Modulates a single chunk of audio samples to IQ data
    /// Phase continuity is maintained across consecutive calls
    /// - Parameter audioChunk: Normalized audio samples in range [-1.0, 1.0]
    /// - Returns: Interleaved IQ samples as Int8 values
    func modulateChunk(_ audioChunk: [Float]) -> [Int8] {
        guard !audioChunk.isEmpty else { return [] }

        let outputSamplesPerAudioSample = Int(ceil(Self.upsampleRatio))
        let chunkIQCount = audioChunk.count * outputSamplesPerAudioSample
        let totalBytes = chunkIQCount * 2

        var iqData = [Int8](repeating: 0, count: totalBytes)

        // Phase increment scale factor
        let phaseScale = Float(2.0 * Double.pi * Self.frequencyDeviation / Self.sampleRate)

        // Step 1: Compute phase increments for each audio sample
        let phaseIncrements = vDSP.multiply(phaseScale, audioChunk)

        // Step 2: Upsample by repeating each phase increment
        var upsampledIncrements = [Float](repeating: 0, count: chunkIQCount)
        for (i, increment) in phaseIncrements.enumerated() {
            let startIdx = i * outputSamplesPerAudioSample
            let endIdx = min(startIdx + outputSamplesPerAudioSample, chunkIQCount)
            for j in startIdx..<endIdx {
                upsampledIncrements[j] = increment
            }
        }

        // Step 3: Compute cumulative phase using running sum
        var phases = [Float](repeating: 0, count: chunkIQCount)
        var currentPhase = Float(phase)
        var one: Float = 1.0
        vDSP_vrsum(upsampledIncrements, 1, &one, &phases, 1, vDSP_Length(chunkIQCount))
        // Add initial phase offset
        vDSP.add(currentPhase, phases, result: &phases)

        // Update running phase for next chunk (unwrapped for continuity)
        if let lastPhase = phases.last {
            phase = Double(lastPhase)
        }

        // Step 4: Wrap phases to [-π, π] using remainder
        let twoPi = Float(2.0 * Double.pi)
        vDSP.divide(phases, twoPi, result: &phases)
        var wrappedPhases = [Float](repeating: 0, count: chunkIQCount)
        for i in 0..<chunkIQCount {
            wrappedPhases[i] = (phases[i] - floor(phases[i] + 0.5)) * twoPi
        }

        // Step 5: Compute sin and cos using vForce
        var sinValues = [Float](repeating: 0, count: chunkIQCount)
        var cosValues = [Float](repeating: 0, count: chunkIQCount)
        var count = Int32(chunkIQCount)
        vvsincosf(&sinValues, &cosValues, &wrappedPhases, &count)

        // Step 6: Scale to [-127, 127]
        let scale: Float = 127.0
        vDSP.multiply(scale, cosValues, result: &cosValues)
        vDSP.multiply(scale, sinValues, result: &sinValues)

        // Step 7: Convert to Int8 and interleave I/Q
        var iqIndex = 0
        for i in 0..<chunkIQCount {
            iqData[iqIndex] = Int8(clamping: Int(cosValues[i].rounded()))
            iqData[iqIndex + 1] = Int8(clamping: Int(sinValues[i].rounded()))
            iqIndex += 2
        }

        return iqData
    }

    /// Converts audio samples to FM-modulated IQ data using vectorized Accelerate operations
    /// - Parameters:
    ///   - audioSamples: Normalized audio samples in range [-1.0, 1.0]
    ///   - onProgress: Optional callback for progress updates
    /// - Returns: Interleaved IQ samples as Int8 values
    func modulate(audioSamples: [Float], onProgress: ModulationProgressCallback? = nil) -> [Int8] {
        let outputSamplesPerAudioSample = Int(ceil(Self.upsampleRatio))
        let totalIQSamples = audioSamples.count * outputSamplesPerAudioSample
        let totalBytes = totalIQSamples * 2

        var iqData = [Int8](repeating: 0, count: totalBytes)

        // Phase increment scale factor (as Float for vectorized operations)
        let phaseScale = Float(2.0 * Double.pi * Self.frequencyDeviation / Self.sampleRate)

        // Process in chunks for memory efficiency and progress reporting
        let audioChunkSize = 50_000
        let iqChunkSize = audioChunkSize * outputSamplesPerAudioSample
        var iqIndex = 0
        var lastReportedProgress = 0.0

        for chunkStart in stride(from: 0, to: audioSamples.count, by: audioChunkSize) {
            let chunkEnd = min(chunkStart + audioChunkSize, audioSamples.count)
            let audioChunk = Array(audioSamples[chunkStart..<chunkEnd])
            let chunkIQCount = audioChunk.count * outputSamplesPerAudioSample

            // Step 1: Compute phase increments for each audio sample
            var phaseIncrements = vDSP.multiply(phaseScale, audioChunk)

            // Step 2: Upsample by repeating each phase increment
            var upsampledIncrements = [Float](repeating: 0, count: chunkIQCount)
            for (i, increment) in phaseIncrements.enumerated() {
                let startIdx = i * outputSamplesPerAudioSample
                let endIdx = min(startIdx + outputSamplesPerAudioSample, chunkIQCount)
                for j in startIdx..<endIdx {
                    upsampledIncrements[j] = increment
                }
            }

            // Step 3: Compute cumulative phase using running sum
            var phases = [Float](repeating: 0, count: chunkIQCount)
            var currentPhase = Float(phase)
            var one: Float = 1.0
            vDSP_vrsum(upsampledIncrements, 1, &one, &phases, 1, vDSP_Length(chunkIQCount))
            // Add initial phase offset
            vDSP.add(currentPhase, phases, result: &phases)

            // Update running phase for next chunk (unwrapped for continuity)
            if let lastPhase = phases.last {
                phase = Double(lastPhase)
            }

            // Step 4: Wrap phases to [-π, π] using remainder
            let twoPi = Float(2.0 * Double.pi)
            vDSP.divide(phases, twoPi, result: &phases)
            var wrappedPhases = [Float](repeating: 0, count: chunkIQCount)
            for i in 0..<chunkIQCount {
                wrappedPhases[i] = (phases[i] - floor(phases[i] + 0.5)) * twoPi
            }

            // Step 5: Compute sin and cos using vForce
            var sinValues = [Float](repeating: 0, count: chunkIQCount)
            var cosValues = [Float](repeating: 0, count: chunkIQCount)
            var count = Int32(chunkIQCount)
            vvsincosf(&sinValues, &cosValues, &wrappedPhases, &count)

            // Step 6: Scale to [-127, 127]
            let scale: Float = 127.0
            vDSP.multiply(scale, cosValues, result: &cosValues)
            vDSP.multiply(scale, sinValues, result: &sinValues)

            // Step 7: Convert to Int8 and interleave I/Q
            let remainingBytes = totalBytes - iqIndex
            let bytesToWrite = min(chunkIQCount * 2, remainingBytes)
            let samplesToWrite = bytesToWrite / 2

            for i in 0..<samplesToWrite {
                iqData[iqIndex] = Int8(clamping: Int(cosValues[i].rounded()))
                iqData[iqIndex + 1] = Int8(clamping: Int(sinValues[i].rounded()))
                iqIndex += 2
            }

            // Report progress
            if let onProgress = onProgress {
                let progress = Double(chunkEnd) / Double(audioSamples.count)
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
