# Repository Guidelines

## Project Structure & Module Organization
The macOS app lives under `PirateRadio/PirateRadio`. Source is organized by layer: `App/` (entry point), `Views/` (SwiftUI UI), `ViewModels/` (state + orchestration), `Services/` (audio processing, HackRF integration, streaming), and `Models/` (shared types). App support files live in `Supporting/` (entitlements, bridging header). The Xcode project is `PirateRadio/PirateRadio.xcodeproj`. Product notes are in `specs/prd.md`. Build artifacts land in `PirateRadio/build/` and are git-ignored.

## Build, Test, and Development Commands
Prerequisite: install HackRF tools on macOS (`brew install hackrf`).

Common workflows:
- Open in Xcode: `open PirateRadio/PirateRadio.xcodeproj`
- Build from CLI: `xcodebuild -project PirateRadio/PirateRadio.xcodeproj -scheme PirateRadio -configuration Debug build`
- Run: use Xcode Run (⌘R), then connect a HackRF device and start transmission from the UI.

## Coding Style & Naming Conventions
Use Xcode’s default Swift formatting (4-space indentation). Follow Swift API Design Guidelines. Types use `UpperCamelCase`, functions/properties use `lowerCamelCase`, and filenames should match primary types (e.g., `TransmitterViewModel.swift`). Keep UI composition in `Views/`, state in `ViewModels/`, and hardware/audio logic in `Services/`. Prefer brief, explanatory comments only where logic is non-obvious.

## Testing Guidelines
There is no automated test target in this repository today. Validate changes manually by building, launching the app, loading an audio file, selecting a frequency, and starting/stopping transmission. If you add tests, create an `XCTest` target and place files under a `PirateRadioTests/` directory with names like `AudioProcessorTests.swift`.

## Commit & Pull Request Guidelines
Recent commits use short, imperative summaries (e.g., “Add audio streaming”). Keep commit titles concise and action-oriented. For PRs, include a brief summary, manual testing steps, and (for UI changes) a screenshot. If hardware was involved, note the HackRF model and frequency used.

## Hardware & Compliance Notes
This app transmits over FM; ensure you have appropriate licensing for your region. Always verify HackRF drivers are installed before running the app.
