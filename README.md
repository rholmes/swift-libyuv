# swift-libyuv

Prebiult libyuv.xcframework for iOS, macOS, Mac Catalyst and tvOS

## Usage

Works as a dependency for C code like libavif (`#include "dav1d/dav1d.h"`), or import as a Swift module with `import dav1d`.

## Notes
- Built with Chromium’s GN/Ninja toolchain
- NEON optimizations are enabled for arm64, SSE2/SSSE3, etc. for x86
- JPEG is disabled on all platforms
