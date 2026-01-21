//
//  TransmitterViewModel.swift
//  PirateRadio
//
//  Main view model coordinating audio processing and FM transmission
//

import Foundation
import SwiftUI
import Combine

/// Represents the current state of the transmitter
enum TransmitterState: Equatable {
    case idle
    case connecting
    case connected
    case loading
    case modulating
    case transmitting
    case stopping
    case error(String)

    var description: String {
        switch self {
        case .idle:
            return "No HackRF connected"
        case .connecting:
            return "Connecting to HackRF..."
        case .connected:
            return "HackRF connected - Ready"
        case .loading:
            return "Loading audio file..."
        case .modulating:
            return "Processing audio..."
        case .transmitting:
            return "Transmitting..."
        case .stopping:
            return "Stopping transmission..."
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var isReady: Bool {
        if case .connected = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .loading, .modulating, .transmitting, .stopping, .connecting:
            return true
        default:
            return false
        }
    }
}

/// Main view model for the Pirate Radio transmitter
@MainActor
final class TransmitterViewModel: ObservableObject {
    // MARK: - Published Properties

    /// Current state of the transmitter
    @Published var state: TransmitterState = .idle

    /// Selected audio file URL
    @Published var selectedFileURL: URL?

    /// Audio file name for display
    @Published var fileName: String = "No file selected"

    /// Audio duration in seconds
    @Published var audioDuration: TimeInterval = 0

    /// Audio format description
    @Published var audioFormat: String = ""

    /// FM frequency in MHz (88.0 - 108.0)
    @Published var frequencyMHz: Double = 100.1

    /// Transmission progress (0.0 - 1.0)
    @Published var transmissionProgress: Double = 0

    /// Processing progress (0.0 - 1.0)
    @Published var processingProgress: Double = 0

    /// Estimated memory usage for current audio
    @Published var estimatedMemory: String = ""

    // MARK: - Private Properties

    private var hackRF: HackRFWrapper?
    private let audioProcessor = AudioProcessor()
    private let fmModulator = FMModulator()

    private var processedAudio: ProcessedAudio?
    private var iqData: [Int8]?

    // MARK: - Computed Properties

    /// Whether the Start button should be enabled
    var canStart: Bool {
        state.isReady && selectedFileURL != nil && !state.isBusy
    }

    /// Whether the Stop button should be enabled
    var canStop: Bool {
        if case .transmitting = state { return true }
        return false
    }

    /// Frequency in Hz for HackRF
    var frequencyHz: UInt64 {
        UInt64(frequencyMHz * 1_000_000)
    }

    /// Current transmission time in seconds
    var currentTime: TimeInterval {
        transmissionProgress * audioDuration
    }

    // MARK: - Device Management

    /// Connects to the HackRF device
    func connectDevice() {
        guard hackRF == nil else { return }

        state = .connecting

        Task {
            do {
                let wrapper = try HackRFWrapper()
                try wrapper.open()
                hackRF = wrapper
                state = .connected
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    /// Disconnects from the HackRF device
    func disconnectDevice() {
        hackRF?.close()
        hackRF = nil
        state = .idle
    }

    /// Attempts to reconnect to the device
    func reconnectDevice() {
        disconnectDevice()
        connectDevice()
    }

    // MARK: - File Selection

    /// Handles selection of an audio file
    func selectFile(_ url: URL) {
        selectedFileURL = url
        fileName = url.lastPathComponent

        // Get file info
        Task {
            do {
                let (duration, format) = try audioProcessor.getFileInfo(from: url)
                audioDuration = duration
                audioFormat = format

                // Calculate estimated memory
                let memoryBytes = FMModulator.estimateMemoryUsage(duration: duration)
                estimatedMemory = FMModulator.formatMemorySize(memoryBytes)

                // Clear any previously processed data
                processedAudio = nil
                iqData = nil
                transmissionProgress = 0
                processingProgress = 0
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    /// Clears the selected file
    func clearFile() {
        selectedFileURL = nil
        fileName = "No file selected"
        audioDuration = 0
        audioFormat = ""
        estimatedMemory = ""
        processedAudio = nil
        iqData = nil
        transmissionProgress = 0
        processingProgress = 0
    }

    // MARK: - Transmission Control

    /// Starts the transmission process (load, modulate, transmit)
    func startTransmission() {
        guard let fileURL = selectedFileURL,
              let hackRF = hackRF else {
            return
        }

        Task {
            do {
                // Step 1: Load audio if not already loaded
                if processedAudio == nil {
                    state = .loading
                    processingProgress = 0

                    processedAudio = try audioProcessor.loadAudio(from: fileURL)
                    processingProgress = 0.3
                }

                // Step 2: Modulate to IQ if not already done
                if iqData == nil {
                    state = .modulating

                    guard let audio = processedAudio else { return }

                    // Modulate with progress callback
                    fmModulator.reset()
                    iqData = await Task.detached { [fmModulator, weak self] in
                        fmModulator.modulate(audioSamples: audio.samples) { progress in
                            Task { @MainActor in
                                self?.processingProgress = 0.3 + (progress * 0.7)
                            }
                        }
                    }.value

                    processingProgress = 1.0
                }

                // Step 3: Configure and start transmission
                guard let iqData = iqData else { return }

                try hackRF.configure(frequencyHz: frequencyHz)
                state = .transmitting
                transmissionProgress = 0

                try hackRF.startTransmission(iqData: iqData) { [weak self] progress in
                    Task { @MainActor in
                        self?.transmissionProgress = progress
                        if progress >= 1.0 {
                            self?.onTransmissionComplete()
                        }
                    }
                }
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    /// Stops the current transmission
    func stopTransmission() {
        guard let hackRF = hackRF else { return }

        state = .stopping

        Task {
            do {
                try hackRF.stopTransmission()
                state = .connected
                transmissionProgress = 0
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Private Methods

    private func onTransmissionComplete() {
        if case .transmitting = state {
            state = .connected
        }
    }
}

// MARK: - Frequency Helpers

extension TransmitterViewModel {
    /// Minimum FM frequency in MHz
    static let minFrequencyMHz: Double = 88.0

    /// Maximum FM frequency in MHz
    static let maxFrequencyMHz: Double = 108.0

    /// Frequency step in MHz
    static let frequencyStepMHz: Double = 0.1

    /// Increases frequency by one step
    func incrementFrequency() {
        frequencyMHz = min(frequencyMHz + Self.frequencyStepMHz, Self.maxFrequencyMHz)
    }

    /// Decreases frequency by one step
    func decrementFrequency() {
        frequencyMHz = max(frequencyMHz - Self.frequencyStepMHz, Self.minFrequencyMHz)
    }

    /// Formatted frequency string
    var frequencyString: String {
        String(format: "%.1f MHz", frequencyMHz)
    }
}

// MARK: - Time Formatting

extension TransmitterViewModel {
    /// Formats a time interval as MM:SS
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Current time formatted
    var currentTimeString: String {
        formatTime(currentTime)
    }

    /// Total duration formatted
    var durationString: String {
        formatTime(audioDuration)
    }
}
