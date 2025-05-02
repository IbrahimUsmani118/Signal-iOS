#!/bin/bash

# Download and cache libsignal-ffi
LIBSIGNAL_FFI_PREBUILD_CHECKSUM="95ea83f1a17b0d92fa1dcb36a8b40744ee0a803d89db536b5433fafcc3c96868"
LIBSIGNAL_FFI_PREBUILD_URL="https://github.com/signalapp/libsignal/releases/download/v0.35.0/libsignal-ffi.tar.gz"
LIBSIGNAL_FFI_CACHE_DIR="${HOME}/Library/Caches/org.signal.libsignal"
LIBSIGNAL_FFI_CACHE_PATH="${LIBSIGNAL_FFI_CACHE_DIR}/libsignal-ffi-${LIBSIGNAL_FFI_PREBUILD_CHECKSUM}.tar.gz"

mkdir -p "${LIBSIGNAL_FFI_CACHE_DIR}"

if [ ! -f "${LIBSIGNAL_FFI_CACHE_PATH}" ]; then
    echo "Downloading libsignal-ffi..."
    curl -L "${LIBSIGNAL_FFI_PREBUILD_URL}" -o "${LIBSIGNAL_FFI_CACHE_PATH}"
fi

echo "Extracting libsignal-ffi..."
tar -xzf "${LIBSIGNAL_FFI_CACHE_PATH}" -C "${PODS_ROOT}/LibSignalClient/swift/Sources/LibSignalClient" 