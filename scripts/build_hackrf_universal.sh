#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="$ROOT_DIR/third_party/hackrf"
SRC_DIR="$THIRD_PARTY_DIR/src"
HOST_DIR="$SRC_DIR/host"
BUILD_DIR="$THIRD_PARTY_DIR/build"
STAGE_DIR="$THIRD_PARTY_DIR/stage"
OUT_INCLUDE_DIR="$THIRD_PARTY_DIR/include"
OUT_LIB_DIR="$THIRD_PARTY_DIR/lib"
DEPS_DIR="$THIRD_PARTY_DIR/deps"
DEPS_SRC_DIR="$DEPS_DIR/src"
DEPS_BUILD_DIR="$DEPS_DIR/build"
DEPS_STAGE_DIR="$DEPS_DIR/stage"
DEPS_UNIVERSAL_DIR="$DEPS_DIR/universal"

LIBUSB_VERSION="1.0.29"
LIBUSB_TARBALL="libusb-$LIBUSB_VERSION.tar.bz2"
LIBUSB_URL="https://github.com/libusb/libusb/releases/download/v$LIBUSB_VERSION/$LIBUSB_TARBALL"

FFTW_VERSION="3.3.10"
FFTW_TARBALL="fftw-$FFTW_VERSION.tar.gz"
FFTW_URL="https://www.fftw.org/$FFTW_TARBALL"

if [[ ! -d "$HOST_DIR" ]]; then
  echo "HackRF source not found at $HOST_DIR" >&2
  echo "Add the HackRF repo as a submodule at third_party/hackrf/src." >&2
  exit 1
fi

need_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
}

for tool in cmake otool install_name_tool curl tar make lipo pkg-config; do
  need_tool "$tool"
done

JOBS="$(sysctl -n hw.ncpu)"

mkdir -p "$DEPS_SRC_DIR" "$DEPS_BUILD_DIR" "$DEPS_STAGE_DIR" "$DEPS_UNIVERSAL_DIR"

fetch_dep() {
  local url="$1"
  local tarball="$2"
  local dest="$DEPS_SRC_DIR/$tarball"
  if [[ ! -f "$dest" ]]; then
    echo "Downloading $tarball..."
    curl -L "$url" -o "$dest"
  fi
}

extract_dep() {
  local tarball="$1"
  local dir="$2"
  if [[ ! -d "$dir" ]]; then
    echo "Extracting $tarball..."
    tar -xf "$DEPS_SRC_DIR/$tarball" -C "$DEPS_SRC_DIR"
  fi
}

get_build_triplet() {
  local src_dir="$1"
  if [[ -x "$src_dir/config.guess" ]]; then
    "$src_dir/config.guess"
    return
  fi
  if [[ -x "$src_dir/build-aux/config.guess" ]]; then
    "$src_dir/build-aux/config.guess"
    return
  fi
  echo ""
}

run_autotools_build() {
  local src_dir="$1"
  local build_dir="$2"
  local prefix="$3"
  local arch="$4"
  shift 4

  rm -rf "$build_dir"
  mkdir -p "$build_dir"

  local cflags="-O2 -arch $arch -mmacosx-version-min=13.0"
  local ldflags="-arch $arch -mmacosx-version-min=13.0"

  (cd "$build_dir" && \
    CC=clang \
    CFLAGS="$cflags" \
    LDFLAGS="$ldflags" \
    "$src_dir/configure" --prefix="$prefix" "$@" && \
    make -j"$JOBS" && \
    make install)
}

build_libusb() {
  local src_dir="$DEPS_SRC_DIR/libusb-$LIBUSB_VERSION"
  fetch_dep "$LIBUSB_URL" "$LIBUSB_TARBALL"
  extract_dep "$LIBUSB_TARBALL" "$src_dir"

  local build_triplet
  build_triplet="$(get_build_triplet "$src_dir")"
  if [[ -z "$build_triplet" ]]; then
    echo "Unable to determine build triplet for libusb." >&2
    exit 1
  fi

  for arch in arm64 x86_64; do
    local build_dir="$DEPS_BUILD_DIR/libusb-$arch"
    local prefix="$DEPS_STAGE_DIR/$arch"
    local host_args
    host_args=()
    if [[ "$arch" == "x86_64" ]]; then
      host_args=(--host=x86_64-apple-darwin --build="$build_triplet")
    fi
    if [[ ${#host_args[@]} -gt 0 ]]; then
      run_autotools_build "$src_dir" "$build_dir" "$prefix" "$arch" "${host_args[@]}" \
        --disable-dependency-tracking
    else
      run_autotools_build "$src_dir" "$build_dir" "$prefix" "$arch" \
        --disable-dependency-tracking
    fi
  done
}

build_fftw() {
  local src_dir="$DEPS_SRC_DIR/fftw-$FFTW_VERSION"
  fetch_dep "$FFTW_URL" "$FFTW_TARBALL"
  extract_dep "$FFTW_TARBALL" "$src_dir"

  local build_triplet
  build_triplet="$(get_build_triplet "$src_dir")"
  if [[ -z "$build_triplet" ]]; then
    echo "Unable to determine build triplet for fftw." >&2
    exit 1
  fi

  for arch in arm64 x86_64; do
    local build_dir="$DEPS_BUILD_DIR/fftw-$arch"
    local prefix="$DEPS_STAGE_DIR/$arch"
    local host_args
    host_args=()
    if [[ "$arch" == "x86_64" ]]; then
      host_args=(--host=x86_64-apple-darwin --build="$build_triplet")
    fi
    if [[ ${#host_args[@]} -gt 0 ]]; then
    run_autotools_build "$src_dir" "$build_dir" "$prefix" "$arch" "${host_args[@]}" \
      --enable-float --enable-threads --enable-shared --disable-fortran --disable-dependency-tracking
    else
    run_autotools_build "$src_dir" "$build_dir" "$prefix" "$arch" \
      --enable-float --enable-threads --enable-shared --disable-fortran --disable-dependency-tracking
    fi
  done
}

make_universal_deps() {
  rm -rf "$DEPS_UNIVERSAL_DIR"
  mkdir -p "$DEPS_UNIVERSAL_DIR/lib" "$DEPS_UNIVERSAL_DIR/include" "$DEPS_UNIVERSAL_DIR/lib/pkgconfig"

  cp -R "$DEPS_STAGE_DIR/arm64/include/" "$DEPS_UNIVERSAL_DIR/include/"

  lipo -create \
    "$DEPS_STAGE_DIR/arm64/lib/libusb-1.0.0.dylib" \
    "$DEPS_STAGE_DIR/x86_64/lib/libusb-1.0.0.dylib" \
    -output "$DEPS_UNIVERSAL_DIR/lib/libusb-1.0.0.dylib"
  ln -sf libusb-1.0.0.dylib "$DEPS_UNIVERSAL_DIR/lib/libusb-1.0.dylib"

  lipo -create \
    "$DEPS_STAGE_DIR/arm64/lib/libfftw3f.3.dylib" \
    "$DEPS_STAGE_DIR/x86_64/lib/libfftw3f.3.dylib" \
    -output "$DEPS_UNIVERSAL_DIR/lib/libfftw3f.3.dylib"
  ln -sf libfftw3f.3.dylib "$DEPS_UNIVERSAL_DIR/lib/libfftw3f.dylib"

  lipo -create \
    "$DEPS_STAGE_DIR/arm64/lib/libfftw3f_threads.3.dylib" \
    "$DEPS_STAGE_DIR/x86_64/lib/libfftw3f_threads.3.dylib" \
    -output "$DEPS_UNIVERSAL_DIR/lib/libfftw3f_threads.3.dylib"
  ln -sf libfftw3f_threads.3.dylib "$DEPS_UNIVERSAL_DIR/lib/libfftw3f_threads.dylib"

  for pc in "$DEPS_STAGE_DIR/arm64/lib/pkgconfig/"*.pc; do
    local name
    name="$(basename "$pc")"
    cp "$pc" "$DEPS_UNIVERSAL_DIR/lib/pkgconfig/$name"
    sed -i '' "s|^prefix=.*|prefix=$DEPS_UNIVERSAL_DIR|" "$DEPS_UNIVERSAL_DIR/lib/pkgconfig/$name"
  done
}

build_hackrf() {
  rm -rf "$BUILD_DIR" "$STAGE_DIR"
  export PKG_CONFIG_PATH="$DEPS_UNIVERSAL_DIR/lib/pkgconfig"
  export CMAKE_PREFIX_PATH="$DEPS_UNIVERSAL_DIR"

  cmake -S "$HOST_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_INSTALL_PREFIX="$STAGE_DIR"

  cmake --build "$BUILD_DIR" --config Release --target install
}

copy_outputs() {
  mkdir -p "$OUT_INCLUDE_DIR" "$OUT_LIB_DIR"
  rm -rf "$OUT_INCLUDE_DIR"/*
  rm -rf "$OUT_LIB_DIR"/*

  cp -R "$STAGE_DIR/include/" "$OUT_INCLUDE_DIR/"
  cp -f "$STAGE_DIR/lib/libhackrf.dylib" "$OUT_LIB_DIR/"

  local libhackrf="$OUT_LIB_DIR/libhackrf.dylib"
  install_name_tool -id "@rpath/$(basename "$libhackrf")" "$libhackrf"

  for dep in libusb-1.0.0.dylib libfftw3f.3.dylib libfftw3f_threads.3.dylib; do
    cp -f "$DEPS_UNIVERSAL_DIR/lib/$dep" "$OUT_LIB_DIR/$dep"
    install_name_tool -id "@rpath/$dep" "$OUT_LIB_DIR/$dep"
  done

  install_name_tool -change "$DEPS_UNIVERSAL_DIR/lib/libusb-1.0.0.dylib" "@rpath/libusb-1.0.0.dylib" "$libhackrf" || true
  install_name_tool -change "$DEPS_STAGE_DIR/arm64/lib/libusb-1.0.0.dylib" "@rpath/libusb-1.0.0.dylib" "$libhackrf" || true
  install_name_tool -change "$DEPS_STAGE_DIR/x86_64/lib/libusb-1.0.0.dylib" "@rpath/libusb-1.0.0.dylib" "$libhackrf" || true

  install_name_tool -change "$DEPS_UNIVERSAL_DIR/lib/libfftw3f.3.dylib" "@rpath/libfftw3f.3.dylib" "$libhackrf" || true
  install_name_tool -change "$DEPS_STAGE_DIR/arm64/lib/libfftw3f.3.dylib" "@rpath/libfftw3f.3.dylib" "$libhackrf" || true
  install_name_tool -change "$DEPS_STAGE_DIR/x86_64/lib/libfftw3f.3.dylib" "@rpath/libfftw3f.3.dylib" "$libhackrf" || true

  install_name_tool -change "$DEPS_UNIVERSAL_DIR/lib/libfftw3f_threads.3.dylib" "@rpath/libfftw3f_threads.3.dylib" "$libhackrf" || true
  install_name_tool -change "$DEPS_STAGE_DIR/arm64/lib/libfftw3f_threads.3.dylib" "@rpath/libfftw3f_threads.3.dylib" "$libhackrf" || true
  install_name_tool -change "$DEPS_STAGE_DIR/x86_64/lib/libfftw3f_threads.3.dylib" "@rpath/libfftw3f_threads.3.dylib" "$libhackrf" || true

  if command -v lipo >/dev/null 2>&1; then
    lipo -info "$libhackrf" || true
  fi
}

build_libusb
build_fftw
make_universal_deps
build_hackrf
copy_outputs
