# OpenGantry OrcaSlicer-Mobile local fork

Base upstream commit: `546b31b989156e3ebd85b67648afef1e95a7b8df` (`0.4.6`).

This branch is maintained locally by OpenGantry and intentionally carries the
Android compatibility changes required by the OpenGantry integration:

- Android NDK `28.2.13676358` for native application and dependency builds.
- 16 KiB ELF page-size linker flags for Android shared libraries.
- Boost.Test `test_exec_moinotr` typo corrected to `test_exec_monitor`.
- All 23 `oneapi/tbb/...` include occurrences in the pinned 0.4.6 source mapped
  to the legacy `tbb/...` API tree actually produced by its Android dependency builder.
- Boost/OCCT generated-header layout normalization after dependency builds.
- Dependency-build paths/toolchain inputs made environment-overridable so the
  OpenGantry host wrapper can supply its isolated Android SDK and work tree.
- Bundled arm64 `libc++_shared.so` and GMP/MPFR prebuilts retired. Gradle/CMake
  packages the matching NDK-r28 `c++_shared` runtime, while GMP 6.2.1 + MPFR 4.2.1
  are rebuilt from pinned release sources with unversioned Android SONAMEs.

The `upstream` Git remote remains read-only by convention. No push remote is
configured automatically. Upstream updates are fetched explicitly and merged or
rebased into this branch only after review.
