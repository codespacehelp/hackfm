# HackFM: macOS FM Transmitter App

## Overview

A native macOS SwiftUI app that transmits audio files (WAV, MP3, AIFF) over FM radio using HackRF One.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   SwiftUI UI    │ --> │ AudioProcessor  │ --> │ HackRFWrapper   │
│                 │     │ (AVFoundation)  │     │ (libhackrf C)   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
   File picker            Load & convert          USB transmission
   Frequency dial         to 48kHz mono           via callback API
   Start/Stop             FM modulation
   Progress bar           to IQ samples
```

**Key Decisions:**

- **Direct libhackrf bindings** (not subprocess) - better control, real-time progress
- **Pre-compute IQ samples** - simpler than streaming, acceptable memory for typical audio
- **2 MSPS sample rate** - good FM quality, reasonable memory usage (~500MB for 5 min audio)
- **Command-line build** - use Swift Package Manager + xcodebuild (no Xcode GUI needed)

## Project Structure

```
hackfm/
├── hackfm.xcodeproj
├── hackfm/
│   ├── App/
│   │   └── HackFMApp.swift          # App entry point
│   ├── Views/
│   │   ├── ContentView.swift        # Main UI
│   │   ├── FileSelectionView.swift
│   │   ├── FrequencyControlView.swift
│   │   ├── TransmissionControlView.swift
│   │   └── ProgressDisplayView.swift
│   ├── ViewModels/
│   │   └── TransmitterViewModel.swift
│   ├── Services/
│   │   ├── AudioProcessor.swift
│   │   ├── FMModulator.swift
│   │   └── HackRFWrapper.swift
│   ├── Models/
│   │   └── HackRFError.swift
│   └── Supporting/
│       ├── HackFM.entitlements
│       └── HackFM-Bridging-Header.h
```

## Build Process

```bash
# 1. Generate Xcode project from Package.swift
swift package generate-xcodeproj

# 2. Build with xcodebuild
xcodebuild -project hackfm/hackfm.xcodeproj \
  -scheme HackFM \
  -configuration Release \
  build

# Output: build/Release/HackFM.app
```

## Implementation Steps

### 1. Package.swift

- Define executable target for macOS app
- Link system library for libhackrf
- Configure C settings for bridging header

### 2. HackRFWrapper (Services/HackRFWrapper.swift)

Swift wrapper around libhackrf C API:

- `init()` - calls `hackrf_init()`
- `open()` - opens device with `hackrf_open()`
- `configure(frequencyHz:)` - sets frequency, sample rate (2 MSPS), TX gain
- `startTransmission(iqData:onProgress:)` - uses `hackrf_start_tx()` with callback
- `stopTransmission()` - calls `hackrf_stop_tx()`

### 3. AudioProcessor (Services/AudioProcessor.swift)

Uses AVFoundation to load and convert audio:

- `loadAudio(from: URL)` - uses `AVAudioFile` (handles WAV/MP3/AIFF)
- Converts to mono 48kHz Float32 PCM using `AVAudioConverter`
- Returns normalized `[Float]` samples in range [-1.0, 1.0]

### 4. FMModulator (Services/FMModulator.swift)

Converts audio samples to FM-modulated IQ:

```
phaseIncrement = 2π × 75kHz × audioSample / 2MHz
phase += phaseIncrement
I = cos(phase) × 127  // Int8
Q = sin(phase) × 127  // Int8
```

- Upsamples from 48kHz to 2MHz
- Output: `[Int8]` interleaved IQ pairs

### 5. SwiftUI Views

- **ContentView** - Main layout with file picker, frequency control, progress, start/stop
- **FrequencyControlView** - Slider (88-108 MHz) + stepper (0.01 MHz precision)
- **TransmissionControlView** - Start/Stop button with status indicator
- **ProgressDisplayView** - Progress bar with elapsed/total time

## FM Parameters

- Frequency range: 88.00 - 108.00 MHz (0.01 MHz steps)
- Frequency deviation: ±75 kHz (FM broadcast standard)
- Sample rate: 2 MSPS
- TX gain: 20 dB (conservative)

## Verification

1. Build: `swift package generate-xcodeproj && xcodebuild`
2. Run the app
3. Connect HackRF, load audio file, set frequency
4. Start transmission, verify with FM radio receiver
5. Stop transmission

## Legal Note

FM transmission requires appropriate licensing in most jurisdictions. Use responsibly.
