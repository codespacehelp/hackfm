# HackRF Third-Party Bundle

This folder contains the prebuilt macOS universal binaries that PirateRadio links and embeds.

Expected layout:
- include/libhackrf/hackrf.h
- lib/libhackrf.dylib
- lib/libusb-1.0.0.dylib
- lib/libfftw3f.3.dylib
- lib/libfftw3f_threads.3.dylib

Notes:
- The dylibs should use @rpath install names so the app can load them from the bundle's Frameworks directory.
- If you need to rebuild, use scripts/build_hackrf_universal.sh. It builds libusb + fftw from source and produces universal binaries without Rosetta.
- Optional: add the HackRF upstream repo as a git submodule at third_party/hackrf/src to track sources.
- Licensing: libhackrf is GPL-2.0-or-later; include upstream license texts when distributing.
