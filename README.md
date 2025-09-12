# swift-libyuv

Prebiult libyuv.xcframework for iOS, macOS, Mac Catalyst and tvOS

## Usage

Use as a dependency in C code with `#include <libyuv.h>`, or import as a Swift module with `import Clibyuv`.

## Notes
- Built with Chromium’s GN/Ninja toolchain
- NEON optimizations are enabled for arm64 (`libyuv_use_neon=true`)
- ASM optimizations are enabled for x86 (SSSE3/AVX/AVX2 etc.)
- JPEG is disabled on all platforms
