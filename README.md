# swift-libyuv

Prebiult libyuv.xcframework for iOS, macOS, Mac Catalyst and tvOS

## Usage

Use as a dependency in C code with `#include <libyuv.h>`, or import as a Swift module with `import libyuv`.

## Notes
- Built with Chromium’s GN/Ninja toolchain
- NEON optimizations are enabled for arm64, SSE2/SSSE3, etc. for x86
- JPEG is disabled on all platforms
