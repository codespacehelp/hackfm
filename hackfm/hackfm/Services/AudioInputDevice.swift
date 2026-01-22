//
//  AudioInputDevice.swift
//  HackFM
//
//  CoreAudio device enumeration for audio input devices
//

import AudioToolbox
import CoreAudio
import Foundation

/// Represents an audio input device
struct AudioInputDevice: Identifiable, Hashable {
    /// Unique device ID (CoreAudio AudioDeviceID)
    let id: AudioDeviceID

    /// Device name
    let name: String

    /// Device manufacturer
    let manufacturer: String

    /// Number of input channels
    let inputChannels: Int

    /// Sample rates supported by the device
    let supportedSampleRates: [Double]

    /// Current sample rate
    let currentSampleRate: Double

    /// Whether this is the system default input device
    let isDefault: Bool

    /// Display name combining name and manufacturer
    var displayName: String {
        if manufacturer.isEmpty || name.lowercased().contains(manufacturer.lowercased()) {
            return name
        }
        return "\(name) (\(manufacturer))"
    }
}

/// Error types for audio device enumeration
enum AudioDeviceError: Error, LocalizedError {
    case noInputDevices
    case deviceNotFound(AudioDeviceID)
    case propertyError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noInputDevices:
            return "No audio input devices found"
        case .deviceNotFound(let id):
            return "Audio device with ID \(id) not found"
        case .propertyError(let status):
            return "CoreAudio property error: \(status)"
        }
    }
}

/// Manager for audio input device enumeration
final class AudioInputDeviceManager {
    // MARK: - Singleton

    static let shared = AudioInputDeviceManager()

    private init() {}

    // MARK: - Public Methods

    /// Gets all available audio input devices
    /// - Returns: Array of AudioInputDevice
    func getInputDevices() throws -> [AudioInputDevice] {
        let deviceIDs = try getAllAudioDeviceIDs()
        let defaultInputID = try getDefaultInputDeviceID()

        var inputDevices: [AudioInputDevice] = []

        for deviceID in deviceIDs {
            // Check if device has input channels
            let inputChannels = getInputChannelCount(for: deviceID)
            guard inputChannels > 0 else { continue }

            // Get device properties
            let name = getDeviceName(for: deviceID) ?? "Unknown Device"
            let manufacturer = getDeviceManufacturer(for: deviceID) ?? ""
            let sampleRates = getSupportedSampleRates(for: deviceID)
            let currentRate = getCurrentSampleRate(for: deviceID) ?? 48000

            let device = AudioInputDevice(
                id: deviceID,
                name: name,
                manufacturer: manufacturer,
                inputChannels: inputChannels,
                supportedSampleRates: sampleRates,
                currentSampleRate: currentRate,
                isDefault: deviceID == defaultInputID
            )

            inputDevices.append(device)
        }

        // Sort with default device first, then alphabetically
        inputDevices.sort { device1, device2 in
            if device1.isDefault != device2.isDefault {
                return device1.isDefault
            }
            return device1.name < device2.name
        }

        return inputDevices
    }

    /// Gets the default audio input device
    /// - Returns: The default input device, or nil if none
    func getDefaultInputDevice() -> AudioInputDevice? {
        guard let defaultID = try? getDefaultInputDeviceID() else { return nil }

        let inputChannels = getInputChannelCount(for: defaultID)
        guard inputChannels > 0 else { return nil }

        let name = getDeviceName(for: defaultID) ?? "Default Input"
        let manufacturer = getDeviceManufacturer(for: defaultID) ?? ""
        let sampleRates = getSupportedSampleRates(for: defaultID)
        let currentRate = getCurrentSampleRate(for: defaultID) ?? 48000

        return AudioInputDevice(
            id: defaultID,
            name: name,
            manufacturer: manufacturer,
            inputChannels: inputChannels,
            supportedSampleRates: sampleRates,
            currentSampleRate: currentRate,
            isDefault: true
        )
    }

    /// Gets an input device by ID
    /// - Parameter id: The AudioDeviceID
    /// - Returns: The device if found
    func getDevice(byID id: AudioDeviceID) throws -> AudioInputDevice {
        let inputChannels = getInputChannelCount(for: id)
        guard inputChannels > 0 else {
            throw AudioDeviceError.deviceNotFound(id)
        }

        let defaultID = try? getDefaultInputDeviceID()
        let name = getDeviceName(for: id) ?? "Unknown Device"
        let manufacturer = getDeviceManufacturer(for: id) ?? ""
        let sampleRates = getSupportedSampleRates(for: id)
        let currentRate = getCurrentSampleRate(for: id) ?? 48000

        return AudioInputDevice(
            id: id,
            name: name,
            manufacturer: manufacturer,
            inputChannels: inputChannels,
            supportedSampleRates: sampleRates,
            currentSampleRate: currentRate,
            isDefault: id == defaultID
        )
    }

    // MARK: - Private Methods

    private func getAllAudioDeviceIDs() throws -> [AudioDeviceID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            throw AudioDeviceError.propertyError(status)
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else {
            throw AudioDeviceError.propertyError(status)
        }

        return deviceIDs
    }

    private func getDefaultInputDeviceID() throws -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else {
            throw AudioDeviceError.propertyError(status)
        }

        return deviceID
    }

    private func getInputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)

        guard status == noErr, dataSize > 0 else { return 0 }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)

        guard status == noErr else { return 0 }

        var totalChannels = 0
        let bufferList = bufferListPointer.pointee
        let bufferCount = Int(bufferList.mNumberBuffers)

        // Access buffers through UnsafeBufferPointer
        withUnsafePointer(to: bufferList.mBuffers) { buffersPtr in
            let buffers = UnsafeBufferPointer(start: buffersPtr, count: bufferCount)
            for buffer in buffers {
                totalChannels += Int(buffer.mNumberChannels)
            }
        }

        return totalChannels
    }

    private func getDeviceName(for deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)

        guard status == noErr, let cfName = name else { return nil }
        return cfName as String
    }

    private func getDeviceManufacturer(for deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceManufacturerCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var manufacturer: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &manufacturer)

        guard status == noErr, let cfManufacturer = manufacturer else { return nil }
        return cfManufacturer as String
    }

    private func getSupportedSampleRates(for deviceID: AudioDeviceID) -> [Double] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)

        guard status == noErr, dataSize > 0 else { return [] }

        let rangeCount = Int(dataSize) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: rangeCount)

        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &ranges)

        guard status == noErr else { return [] }

        // Collect unique sample rates
        var sampleRates = Set<Double>()
        for range in ranges {
            // If min equals max, it's a discrete rate
            if range.mMinimum == range.mMaximum {
                sampleRates.insert(range.mMinimum)
            } else {
                // Add common rates within the range
                let commonRates: [Double] = [44100, 48000, 88200, 96000, 176400, 192000]
                for rate in commonRates {
                    if rate >= range.mMinimum && rate <= range.mMaximum {
                        sampleRates.insert(rate)
                    }
                }
            }
        }

        return Array(sampleRates).sorted()
    }

    private func getCurrentSampleRate(for deviceID: AudioDeviceID) -> Double? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var sampleRate: Float64 = 0
        var dataSize = UInt32(MemoryLayout<Float64>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &sampleRate)

        guard status == noErr else { return nil }
        return sampleRate
    }
}
