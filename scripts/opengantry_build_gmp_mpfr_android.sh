#!/usr/bin/env bash
set -euo pipefail

GMP_VERSION="6.2.1"
MPFR_VERSION="4.2.1"
GMP_SHA256="fd4829912cddd12f84181c3451cc752be224643e87fac497b69edddadc49b4f2"
MPFR_SHA256="277807353a6726978996945af13e52829e3abd7a9a5b7fb2793894e18f1fcbb2"
GMP_URL="https://gmplib.org/download/gmp/gmp-${GMP_VERSION}.tar.xz"
MPFR_URL="https://www.mpfr.org/mpfr-${MPFR_VERSION}/mpfr-${MPFR_VERSION}.tar.xz"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${1:-${OPENGANTRY_ORCA_DEPS_WORK:-/tmp/build_android_deps}}"
ANDROID_ABI="${ANDROID_ABI:-${ABI:-arm64-v8a}}"
GMP_ABI="${GMP_ABI:-64}"
unset ABI
API_LEVEL="${API_LEVEL:-21}"
N_CORES="${N_CORES:-$(nproc)}"
: "${ANDROID_NDK_ROOT:?ANDROID_NDK_ROOT must point to the OpenGantry NDK r28 install}"

if [[ "$ANDROID_ABI" != "arm64-v8a" ]]; then
    echo "ERROR: OpenGantry fork GMP/MPFR builder currently qualifies arm64-v8a only (got $ANDROID_ABI)" >&2
    exit 1
fi
if [[ "$GMP_ABI" != "64" ]]; then
    echo "ERROR: OpenGantry fork GMP build requires GMP ABI=64 for arm64-v8a (got $GMP_ABI)" >&2
    exit 1
fi

TOOLCHAIN="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64"
TARGET="aarch64-linux-android"
CC="$TOOLCHAIN/bin/${TARGET}${API_LEVEL}-clang"
CXX="$TOOLCHAIN/bin/${TARGET}${API_LEVEL}-clang++"
AR="$TOOLCHAIN/bin/llvm-ar"
RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
NM="$TOOLCHAIN/bin/llvm-nm"
STRIP="$TOOLCHAIN/bin/llvm-strip"
READELF="$TOOLCHAIN/bin/llvm-readelf"
for tool in "$CC" "$CXX" "$AR" "$RANLIB" "$NM" "$STRIP" "$READELF"; do
    [[ -x "$tool" ]] || { echo "ERROR: missing NDK tool: $tool" >&2; exit 1; }
done

LINK_FLAGS="${OPENGANTRY_16K_LDFLAGS:--Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384}"
COMMON_CFLAGS="-O2 -fPIC -D__BIONIC_NO_PAGE_SIZE_MACRO"
COMMON_CXXFLAGS="$COMMON_CFLAGS"
SOURCES="$WORK_DIR/source-archives"
SRCROOT="$WORK_DIR/source-trees"
BUILDROOT="$WORK_DIR/gmp-mpfr-build"
PREFIX="$WORK_DIR/gmp-mpfr-prefix"
OUT_LIB="$ROOT/app/src/main/jniLibs/$ANDROID_ABI"
OUT_INC="$ROOT/app/src/main/jniImports/gmp/include/$ANDROID_ABI"
mkdir -p "$SOURCES" "$SRCROOT" "$OUT_LIB" "$OUT_INC"

fetch() {
    local url="$1" out="$2"
    [[ -f "$out" ]] && return 0
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --retry-delay 2 -o "$out.part" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$out.part" "$url"
    else
        echo "ERROR: curl or wget is required to download GMP/MPFR sources" >&2
        exit 1
    fi
    mv "$out.part" "$out"
}

verify() {
    local expected="$1" file="$2"
    printf '%s  %s\n' "$expected" "$file" | sha256sum -c -
}

GMP_ARCHIVE="$SOURCES/gmp-${GMP_VERSION}.tar.xz"
MPFR_ARCHIVE="$SOURCES/mpfr-${MPFR_VERSION}.tar.xz"
fetch "$GMP_URL" "$GMP_ARCHIVE"
fetch "$MPFR_URL" "$MPFR_ARCHIVE"
verify "$GMP_SHA256" "$GMP_ARCHIVE"
verify "$MPFR_SHA256" "$MPFR_ARCHIVE"

GMP_SRC="$SRCROOT/gmp-${GMP_VERSION}"
MPFR_SRC="$SRCROOT/mpfr-${MPFR_VERSION}"
rm -rf "$GMP_SRC" "$MPFR_SRC" "$BUILDROOT" "$PREFIX"
tar -C "$SRCROOT" -xf "$GMP_ARCHIVE"
tar -C "$SRCROOT" -xf "$MPFR_ARCHIVE"
mkdir -p "$BUILDROOT/gmp" "$BUILDROOT/mpfr" "$PREFIX"
BUILD_TRIPLE="$(cd "$GMP_SRC" && ./config.guess)"

export CC CXX AR RANLIB NM STRIP
export CFLAGS="$COMMON_CFLAGS"
export CXXFLAGS="$COMMON_CXXFLAGS"
export LDFLAGS="$LINK_FLAGS"

echo "--- Building GMP $GMP_VERSION for $ANDROID_ABI (GMP ABI=$GMP_ABI) with NDK r28 ---"
cd "$BUILDROOT/gmp"
ABI="$GMP_ABI" "$GMP_SRC/configure" \
    --build="$BUILD_TRIPLE" \
    --host="$TARGET" \
    --prefix="$PREFIX" \
    --enable-cxx \
    --disable-shared \
    --enable-static \
    --with-pic
make -j"$N_CORES"
make install

echo "--- Linking Android-facing unversioned GMP shared libraries ---"
"$CC" --shared $LINK_FLAGS -Wl,-soname,libgmp.so \
    -Wl,--whole-archive "$PREFIX/lib/libgmp.a" -Wl,--no-whole-archive \
    -ldl -lm -o "$OUT_LIB/libgmp.so"
"$CXX" --shared $LINK_FLAGS -Wl,-soname,libgmpxx.so \
    -Wl,--whole-archive "$PREFIX/lib/libgmpxx.a" -Wl,--no-whole-archive \
    -L"$OUT_LIB" -Wl,-rpath-link,"$OUT_LIB" -lgmp -ldl -lm \
    -o "$OUT_LIB/libgmpxx.so"

echo "--- Building MPFR $MPFR_VERSION against GMP $GMP_VERSION ---"
cd "$BUILDROOT/mpfr"
CPPFLAGS="-I$PREFIX/include" \
LDFLAGS="-L$OUT_LIB -L$PREFIX/lib $LINK_FLAGS" \
"$MPFR_SRC/configure" \
    --build="$BUILD_TRIPLE" \
    --host="$TARGET" \
    --prefix="$PREFIX" \
    --with-gmp="$PREFIX" \
    --disable-shared \
    --enable-static
make -j"$N_CORES"
make install

"$CC" --shared $LINK_FLAGS -Wl,-soname,libmpfr.so \
    -Wl,--whole-archive "$PREFIX/lib/libmpfr.a" -Wl,--no-whole-archive \
    -L"$OUT_LIB" -Wl,-rpath-link,"$OUT_LIB" -lgmp -ldl -lm \
    -o "$OUT_LIB/libmpfr.so"

cp -f "$PREFIX/include/gmp.h" "$PREFIX/include/gmpxx.h" \
    "$PREFIX/include/mpfr.h" "$PREFIX/include/mpf2mpfr.h" "$OUT_INC/"

for lib in libgmp.so libgmpxx.so libmpfr.so; do
    soname="$($READELF -d "$OUT_LIB/$lib" | sed -n 's/.*SONAME.*\[\(.*\)\].*/\1/p')"
    [[ "$soname" == "$lib" ]] || { echo "ERROR: $lib has unexpected SONAME '$soname'" >&2; exit 1; }
    echo "[BUILT] $lib SONAME=$soname"
done

echo "--- GMP/MPFR built and copied! ---"
