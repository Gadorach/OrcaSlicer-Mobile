# OpenGantry OrcaSlicer-Mobile integration fork

Controlled origin: `https://github.com/Gadorach/OrcaSlicer-Mobile.git`.

Base upstream commit: `546b31b989156e3ebd85b67648afef1e95a7b8df` (`0.4.6`).

This branch is maintained by OpenGantry and intentionally carries the Android
compatibility changes required by the OpenGantry integration:

- Android NDK `28.2.13676358` for native application and dependency builds.
- 16 KiB ELF page-size linker flags for Android shared libraries.
- Boost.Test `test_exec_moinotr` typo corrected to `test_exec_monitor`.
- Vendored zlib declares Android POSIX file-descriptor I/O through `<unistd.h>`,
  required by NDK r28 / Clang 19 for `read`, `write`, `lseek`, and `close`.
- Vendored NLopt/StoGO no longer inherits from removed `std::unary_function`;
  the comparator remains an ordinary callable under modern libc++ / C++17.
- All 23 `oneapi/tbb/...` include occurrences in the pinned 0.4.6 source mapped
  to the legacy `tbb/...` API tree actually produced by its Android dependency builder.
- Boost/OCCT generated-header layout normalization after dependency builds.
- Dependency-build paths/toolchain inputs made environment-overridable so the
  OpenGantry host wrapper can supply its isolated Android SDK and work tree.
- Bundled arm64 `libc++_shared.so` and GMP/MPFR prebuilts retired. Gradle/CMake
  packages the matching NDK-r28 `c++_shared` runtime, while GMP 6.2.1 + MPFR 4.2.1
  are rebuilt from pinned release sources with unversioned Android SONAMEs.

The original `CodeMasterCody3D/OrcaSlicer-Mobile` repository is retained as the
read-only `upstream` remote. Upstream changes are fetched explicitly and merged
or rebased into this branch only after review.
