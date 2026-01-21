# Pirate Radio Station

Broadcast audio files over FM radio using a HackRF One on macOS.

![Pirate Radio screenshot](.github/screenshot.png)

Pirate Radio is a simple macOS app that lets you pick an audio file (WAV, MP3, AIFF), choose a broadcast frequency between 88.00 and 108.00 MHz, and start or stop transmission. A progress bar shows how much of the file has played.

## Requirements (macOS)

You’ll need a HackRF One device and the HackRF tools installed.

Install [Homebrew](https://brew.sh/) if you haven’t already.

Then install the HackRF tools:

```
brew install hackrf
```

## Building

Open `PirateRadio/PirateRadio.xcodeproj` in Xcode and press Run.

## Legal note
FM transmission requires appropriate licensing in many regions. Use responsibly.
