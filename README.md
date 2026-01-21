# Pirate Radio Station

Using the HackRF to transmit audio files.

Simple app for macos that can transmit audio files (WAV, MP3, AIFF) over FM radio. The UI should be able to choose the exact frequency (between 88Mhz
and 108Mhz, in steps of 0.01Mhz) as well as a start/stop button to start / stop the transmission. A progress indicator for where we are in the file would be nice. Make a plan first. Assume the
hackrf driver is already installed (`brew install hackrf`)

## Requirements (macOS)

Install [Homebrew](https://brew.sh/) if you haven't already.

Then install the HackRF tools:

```
brew install hackrf
```

## Building
