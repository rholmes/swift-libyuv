# swift-libyuv — prebuilt XCFramework for libyuv

This repository packages [libyuv](https://chromium.googlesource.com/libyuv/libyuv) as a **binary Swift Package** via an XCFramework built with Chromium’s GN/Ninja toolchain.

It includes a build script that fetches libyuv with **gclient**, compiles **per-slice** archives with size-oriented flags, coalesces simulator/mac/catalyst slices into fat archives, then emits a clean `libyuv.xcframework` and drops it into `Sources/` for SwiftPM consumption.

---

## Contents

```
swift-libyuv/
├─ Package.swift
├─ Build/
│  ├─ build-libyuv-xcframework.sh   ← the build script
│  └─ build-libyuv/                 ← work area (created/managed by the script)
│     ├─ .gclient
│     ├─ src/                       ← gclient-managed libyuv checkout
│     ├─ src/out/                   ← GN/Ninja outputs (per-slice)
│     └─ dist/                      ← build artifacts (XCFramework, metadata)
└─ Sources/
   └─ libyuv.xcframework            ← vendored binary target (created by script)
```

---

## Prerequisites

- **Xcode** (and Command Line Tools) on macOS.
- **depot_tools** on your PATH (for `gclient` and the `gn` wrapper).
  - Typical install path: `~/depot_tools`
- **git**, **python3** (depot_tools uses Python).
- (Optional) **Homebrew GN**: `brew install gn`  
  *Not required if you’re using the depot_tools `gn` wrapper; the script builds inside a gclient checkout.*

---

## One-time setup

```bash
# Ensure depot_tools is discoverable
export PATH="$HOME/depot_tools:$PATH"
```

---

## Usage

From the [repository root]/Build directory (where your Bash script lives):

```bash
chmod +x build-libyuv-xcframework.sh

# Standard multi-platform build (iOS, iOS Sim, macOS, Catalyst, tvOS)
./build-libyuv-xcframework.sh
```

### Optional toggles (environment variables)

- **Strip symbols for smaller archives:**
  ```bash
  STRIP=1 ./build-libyuv-xcframework.sh
  ```

---
  
## Script Overview

What happens:

1. **ensure_checkout**: creates/updates a Chromium-style checkout in `build-libyuv/` by writing `.gclient` and running `gclient sync`.  
   - If `LIBYUV_REF` is set (commit, tag, or branch), it pins the solution via `gclient sync -r src@<ref>`.
2. **Per-slice builds** using GN/Ninja (out of `build-libyuv/src/out/...`) with size-focused flags:
   - `symbol_level=0`, `optimize_for_size=true`
   - `libyuv_disable_jpeg=true`
   - `libyuv_use_neon=true` (arm64 only), `libyuv_use_sve=false`, `libyuv_use_sme=false`
   - **iOS device** signing disabled (`ios_enable_code_signing=false`)
   - **Deployment targets**:
     - iOS device/sim: **13.0**
     - macOS: **11.0**
     - Mac Catalyst: **iOS 14.0 / macOS 11.0**
     - tvOS device/sim (if enabled): set via `ios_deployment_target` for tvOS slices  
       *(tvOS is built with `target_os="ios"` + `target_platform="tvos"`; if you see tvOS compile errors, ensure `use_blink=true` is set in those slices.)*
3. **Object harvesting**: the script collects `.o` files from `obj/libyuv_internal` (and `obj/libyuv_neon` on arm64), filters out empty objects with `nm`, and re-archives them with `xcrun libtool -static` into **non-thin** per-slice libs.
4. **Coalescing** (fat/universal archives):  
   - iOS **simulator** → arm64 + x86_64  
   - **macOS** → arm64 + x86_64  
   - **Mac Catalyst** → arm64 + x86_64  
   - tvOS **simulator** → arm64 + x86_64  
   *(iOS device and tvOS device remain arm64)*
5. **Headers**: an overlay headers dir is prepared (copy of `src/include`) and copied into each slice's `Headers` directory.
6. **XCFramework packaging**: `xcodebuild -create-xcframework` is called with **paired** `-library … -headers …` for each platform slice.
7. **Output**:
   - `build-libyuv/dist/libyuv.xcframework`
   - `build-libyuv/dist/BUILD-METADATA.txt` (commit, flags, mins)

---

## Pinning the libyuv revision (reproducible builds)

To build a specific commit/tag/branch:

```bash
# Examples:
export LIBYUV_REF=main                 # track branch tip
export LIBYUV_REF=9f2c3a1              # exact commit
export LIBYUV_REF=refs/tags/2024-08-01 # tag

./build-libyuv-xcframework.sh
```

The script uses `gclient sync -r "src@${LIBYUV_REF}"`, ensuring DEPS and toolchain match that ref. The exact commit used is recorded in `BUILD-METADATA.txt`.

---

## Supported platforms & architectures

- **iOS (device)**: `arm64` (min iOS **13.0**)  
- **iOS (simulator)**: `arm64` + `x86_64` (fat) (min iOS **13.0**)  
- **macOS**: `arm64` + `x86_64` (fat) (min macOS **11.0**)  
- **Mac Catalyst**: `arm64` + `x86_64` (fat) (min iOS **14.0**, macOS **11.0**)  
- **tvOS (device)**: `arm64` (min tvOS **13.0**)  
- **tvOS (simulator)**: `arm64` + `x86_64` (fat) (min tvOS **13.0**)  

> Deliberately **not** building `arm64e`. It provides no benefit for libyuv and complicates distribution.

---

## Consuming the package (SwiftPM)

`Package.swift` should declare the binary target at the vendored path:

```swift
// Package.swift (excerpt)
.targets = [
  .binaryTarget(
    name: "libyuv",
    path: "Sources/libyuv.xcframework"
  ),
],
```

Then in your code:

```swift
import libyuv
// Call libyuv APIs (e.g., I420ToARGB, ARGBToI420, etc.)
```

---

## Verify the build

```bash
# Confirm fat archives include both arches where expected
xcrun lipo -info build-libyuv/src/out/macos-universal/libyuv.a
xcrun lipo -info build-libyuv/src/out/maccatalyst-universal/libyuv.a
xcrun lipo -info build-libyuv/src/out/ios-sim-universal/libyuv.a

# Inspect one slice in the XCFramework
ls -1 Sources/libyuv.xcframework

# Confirm the minimum OS embedded in objects (optional, requires vtool)
# Expect iOS 13.0 / macOS 11.0 / Catalyst 11.0 / tvOS <your-min>
```

---

## Troubleshooting

- **`gn.py: Could not find checkout…`**  
  Ensure the script wrote `.gclient` under `build-libyuv/` and that you have `gclient` on `PATH`. The script runs all GN work **inside the checkout** and places `out/` under `src/` specifically to satisfy the wrapper.

- **Duplicate platform error in `-create-xcframework`**  
  (“Both … represent two equivalent library definitions.”)  
  Means two inputs described the same platform. The script **coalesces** sim/mac/catalyst into **one fat lib each** before packaging.

- **`libtool: file: … is not an object file (not allowed in a library)`**  
  Comes from trying to re-archive **thin** `.a` files. The script avoids this by archiving from the **`.o` files**, not from thin `.a`s.

- **“has no symbols” warnings**  
  Benign; the script filters empties with `nm` to quiet logs.

- **tvOS compile errors**  
  Make sure the tvOS slices set `target_platform="tvos"` and (if necessary) `use_blink=true`. Deployment minimum is set via `ios_deployment_target`.

---

## Customization

- **Minimum OS versions**: tweak the constants in the script if you need different floors (device/sim must match for each platform).
- **Pinning**: set `LIBYUV_REF` as shown above.
- **Work directories**: override `WORK_DIR`, `SRC_DIR`, `OUT_ROOT`, `DIST_DIR`, `HEADERS_DIR` via environment variables if needed.
- **Excluding platforms**: remove slices from the matrix in the script, or gate tvOS behind an env var if you prefer.

---

## Licensing

- libyuv is licensed under its own terms. Include libyuv’s LICENSE in your repo or release notes as appropriate.
- This repo’s build script and packaging are provided as-is.

---

## Release checklist

- [ ] Build succeeds on a clean machine.
- [ ] `Sources/libyuv.xcframework` updated.
- [ ] `Build/build-libyuv/dist/BUILD-METADATA.txt` recorded.
- [ ] Swift sample compiles with `import libyuv`.
- [ ] Tag your release and note the libyuv commit used.
