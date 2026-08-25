#!/usr/bin/env bash
set -euo pipefail

# OPENGANTRY_16K_DEP_LINK_COMPAT
# NDK r28 defaults to flexible/16 KiB ELF alignment, and these flags
# keep Autoconf/libtool and dependency-specific linkers explicit.
export OPENGANTRY_16K_LDFLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"
export LDFLAGS="${LDFLAGS:-} ${OPENGANTRY_16K_LDFLAGS}"
export CFLAGS="${CFLAGS:-} -D__BIONIC_NO_PAGE_SIZE_MACRO"
export CXXFLAGS="${CXXFLAGS:-} -D__BIONIC_NO_PAGE_SIZE_MACRO"

echo "======================================================================="
echo " Building SliceBeam Native Dependencies (Boost, oneTBB, OCCT, GMP/MPFR)"
echo " This process will download and compile massive C++ libraries from source"
echo " using the Android NDK. This will take several hours."
echo "======================================================================="

export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-$ANDROID_SDK_ROOT/ndk/28.2.13676358}"
export CMAKE_BIN="${CMAKE_BIN:-cmake}"
export ABI="arm64-v8a"
export API_LEVEL="21"
export N_CORES="${N_CORES:-$(nproc)}"

ORCA_ROOT="${OPENGANTRY_ORCA_ROOT:-$(pwd)}"
JNI_IMPORTS_DIR="$ORCA_ROOT/app/src/main/jniImports"
mkdir -p "$JNI_IMPORTS_DIR"

WORK_DIR="${OPENGANTRY_ORCA_DEPS_WORK:-/tmp/build_android_deps}"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 1. Build oneTBB
echo "--- Building oneTBB ---"
if [ ! -d "openvdb-android" ]; then
    git clone https://github.com/syoyo/openvdb-android.git
    cd openvdb-android
    git submodule update --init --recursive
    cd ..
fi

cd openvdb-android
rm -rf build-tbb-android
$CMAKE_BIN \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=$ABI \
  -DANDROID_NATIVE_API_LEVEL=$API_LEVEL \
  -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Release \
  -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON \
  -DCMAKE_SHARED_LINKER_FLAGS="$OPENGANTRY_16K_LDFLAGS" \
  -DCMAKE_MODULE_LINKER_FLAGS="$OPENGANTRY_16K_LDFLAGS" \
  -DCMAKE_INSTALL_PREFIX=$(pwd)/dist \
  -DHAS_LIBCPP=1 \
  -DTBB_BUILD_TESTS=Off \
  -DTBB_BUILD_SHARED=Off \
  -DTBB_BUILD_STATIC=On \
  -S tbb-aarch64 \
  -B build-tbb-android

cd build-tbb-android
make -j$N_CORES
make install
cd ../..

# Copy TBB to jniImports
mkdir -p "$JNI_IMPORTS_DIR/oneTBB/lib/$ABI"
cp openvdb-android/dist/lib/libtbb_static.a "$JNI_IMPORTS_DIR/oneTBB/lib/$ABI/libtbb.a"
cp openvdb-android/dist/lib/libtbbmalloc_static.a "$JNI_IMPORTS_DIR/oneTBB/lib/$ABI/libtbbmalloc.a"
mkdir -p "$JNI_IMPORTS_DIR/oneTBB/include"
cp -r openvdb-android/dist/include/* "$JNI_IMPORTS_DIR/oneTBB/include/"
echo "--- oneTBB built and copied! ---"

# 2. Build Boost
echo "--- Building Boost ---"
if [ ! -d "Boost-for-Android" ]; then
    git clone --recursive https://github.com/moritz-wundke/Boost-for-Android.git
fi
cd Boost-for-Android
# Note: Boost-for-Android requires specific configurations for NDK versions.
./build-android.sh --boost=1.85.0 $ANDROID_NDK_ROOT
# After building, copy the compiled Boost .a libraries into jniImports
mkdir -p "$JNI_IMPORTS_DIR/boost/lib/$ABI/lib"
cp -r build/out/arm64-v8a/lib/*.a "$JNI_IMPORTS_DIR/boost/lib/$ABI/lib/"
mkdir -p "$JNI_IMPORTS_DIR/boost/include"
cp -aL build/out/arm64-v8a/include/boost-1_85/. "$JNI_IMPORTS_DIR/boost/include/"
cd ..
echo "--- Boost built and copied! ---"

# 3. Build OCCT
echo "--- Building OCCT ---"
if [ ! -d "OCCT" ]; then
    git clone https://github.com/Open-Cascade-SAS/OCCT.git
fi
cd OCCT
mkdir -p build-android && cd build-android
$CMAKE_BIN \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=$ABI \
  -DANDROID_NATIVE_API_LEVEL=$API_LEVEL \
  -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Release \
  -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON \
  -DCMAKE_SHARED_LINKER_FLAGS="$OPENGANTRY_16K_LDFLAGS" \
  -DCMAKE_MODULE_LINKER_FLAGS="$OPENGANTRY_16K_LDFLAGS" \
  -DBUILD_LIBRARY_TYPE=Shared \
  -DUSE_FREETYPE=OFF \
  ..
make -j$N_CORES
mkdir -p "$JNI_IMPORTS_DIR/../occt/jniLibs/$ABI"
cp lin64/clang/lib/*.so "$JNI_IMPORTS_DIR/../occt/jniLibs/$ABI/"
mkdir -p "$JNI_IMPORTS_DIR/../occt/include/$ABI"
cp -aL include/opencascade/. "$JNI_IMPORTS_DIR/../occt/include/$ABI/"
cd ../..
echo "--- OCCT built and copied! ---"
bash "$ORCA_ROOT/scripts/opengantry_build_gmp_mpfr_android.sh" "$WORK_DIR"
python3 "$ORCA_ROOT/scripts/opengantry_normalize_android_deps.py" --work-dir "$WORK_DIR"

echo "======================================================================="
echo " DONE!"
echo " All native libraries have been compiled and copied to jniImports."
echo " You can now compile the C++ libslic3r core using:"
echo " ./gradlew assembleDebug -PusePrebuiltNative=false"
echo "======================================================================="
