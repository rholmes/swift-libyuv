#!/usr/bin/env bash
set -euo pipefail

# ---------- paths ----------
# Where this script lives (…/swift-libyuv/Build)
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo root that contains Package.swift
PKG_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# Work area for libyuv sources and build outputs
WORK_DIR="${WORK_DIR:-${PKG_ROOT}/Build/libyuv}"
SRC_DIR="${SRC_DIR:-${WORK_DIR}/src}"     # gclient-managed libyuv checkout
OUT_ROOT="${OUT_ROOT:-${SRC_DIR}/out}"    # ninja out dir under checkout (required by gn wrapper)
DIST_DIR="${DIST_DIR:-${WORK_DIR}/dist}"  # xcframework output

# Headers come from libyuv sources
HEADERS_DIR="${HEADERS_DIR:-${SRC_DIR}/include}"

# ---------- configuration ----------
LIBYUV_REF="06a1c004bbbca3cef3f468a8fe77704b855ca039"
XCFRAMEWORK_NAME="libyuv.xcframework"

IOS_MIN="13.0"
IOS_CATALYST_MIN="14.0"   # Catalyst’s iOS minimum
MAC_MIN="11.0"            # macOS minimum

GN="${GN:-gn}"
NINJA="${NINJA:-ninja}"
XCBUILD="${XCBUILD:-xcodebuild}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: missing tool: $1" >&2; exit 1; }; }
need "${GN}"; need "${NINJA}"; need "${XCBUILD}"

# Ensure a Chromium-style checkout so depot_tools/gn.py is happy.
# - Creates .gclient in WORK_DIR (idempotent)
# - Runs `gclient sync --no-history`
# - Optionally pins to $LIBYUV_REF (tag/branch/sha) if provided
ensure_checkout() {
  # Make depot_tools available (customize if you keep it elsewhere)
  if ! command -v gclient >/dev/null 2>&1; then
    if [[ -n "${DEPOT_TOOLS:-}" && -x "${DEPOT_TOOLS}/gclient" ]]; then
      export PATH="${DEPOT_TOOLS}:${PATH}"
    elif [[ -x "${HOME}/depot_tools/gclient" ]]; then
      export PATH="${HOME}/depot_tools:${PATH}"
    fi
  fi
  command -v gclient >/dev/null 2>&1 || {
    echo "error: depot_tools 'gclient' not found. Install depot_tools and put it on PATH." >&2
    echo "       https://commondatastorage.googleapis.com/chrome-infra-docs/flat/depot_tools/docs/html/depot_tools_tutorial.html" >&2
    exit 1
  }

  mkdir -p "${WORK_DIR}"
  pushd "${WORK_DIR}" >/dev/null

  if [[ ! -f .gclient ]]; then
    cat > .gclient << 'EOF'
solutions = [
  {
    "name": "src",
    "url": "https://chromium.googlesource.com/libyuv/libyuv",
    "deps_file": "DEPS",
    "managed": True,
    "custom_deps": {},
    "safesync_url": "",
  },
]
# Build toolchains we care about
target_os = ["ios", "mac"]
EOF
  fi

  # First-time or update sync (pin if LIBYUV_REF is set)
  local ref_args=()
  if [[ -n "${LIBYUV_REF:-}" ]]; then
    echo "==> gclient sync (pin src@${LIBYUV_REF})" >&2
    ref_args=(-r "src@${LIBYUV_REF}")
  else
    echo "==> gclient sync (latest)" >&2
  fi
  gclient sync --no-history "${ref_args[@]}"

  popd >/dev/null
}

ensure_checkout
mkdir -p "${OUT_ROOT}" "${DIST_DIR}"

# ---------- target matrix ----------
SLICES=(
  ios-device-arm64
  ios-sim-arm64
  ios-sim-x64
  mac-arm64
  mac-x64
  maccatalyst-arm64
  maccatalyst-x64
  tvos-device-arm64
  tvos-sim-arm64
  tvos-sim-x64
)

slice_outdir() { echo "${OUT_ROOT}/$1"; }

gen_args_for_slice() {
  local slice="$1"
  local common='
    is_debug=false
    is_component_build=false
    libyuv_disable_jpeg=true
    libyuv_use_sve=false
    libyuv_use_sme=false
    symbol_level=0
    optimize_for_size=true
  '
  case "$slice" in
    ios-device-arm64)
      echo "${common}
        target_os=\"ios\"
        target_cpu=\"arm64\"
        target_environment=\"device\"
        ios_deployment_target=\"${IOS_MIN}\"
        ios_enable_code_signing=false
        libyuv_use_neon=true
      ";;
    ios-sim-arm64)
      echo "${common}
        target_os=\"ios\"
        target_cpu=\"arm64\"
        target_environment=\"simulator\"
        ios_deployment_target=\"${IOS_MIN}\"
        libyuv_use_neon=true
      ";;
    ios-sim-x64)
      echo "${common}
        target_os=\"ios\"
        target_cpu=\"x64\"
        target_environment=\"simulator\"
        ios_deployment_target=\"${IOS_MIN}\"
        libyuv_use_neon=false
      ";;
    mac-arm64)
      echo "${common}
        target_os=\"mac\"
        target_cpu=\"arm64\"
        mac_deployment_target=\"${MAC_MIN}\"
        libyuv_use_neon=true
      ";;
    mac-x64)
      echo "${common}
        target_os=\"mac\"
        target_cpu=\"x64\"
        mac_deployment_target=\"${MAC_MIN}\"
        libyuv_use_neon=false
      ";;
    maccatalyst-arm64)
      echo "${common}
        target_os=\"ios\"
        target_cpu=\"arm64\"
        target_environment=\"catalyst\"
        mac_deployment_target=\"${MAC_MIN}\"
        ios_deployment_target=\"${IOS_CATALYST_MIN}\"
        libyuv_use_neon=true
      ";;
    maccatalyst-x64)
      echo "${common}
        target_os=\"ios\"
        target_cpu=\"x64\"
        target_environment=\"catalyst\"
        mac_deployment_target=\"${MAC_MIN}\"
        ios_deployment_target=\"${IOS_CATALYST_MIN}\"
        libyuv_use_neon=false
      ";;
    tvos-device-arm64)
      echo "${common}
        target_os=\"ios\"
        target_platform=\"tvos\"
        target_cpu=\"arm64\"
        target_environment=\"device\"
        ios_deployment_target=\"${IOS_MIN}\"
        ios_enable_code_signing=false
        libyuv_use_neon=true
        use_blink=true
      ";;
    tvos-sim-arm64)
      echo "${common}
        target_os=\"ios\"
        target_platform=\"tvos\"
        target_cpu=\"arm64\"
        target_environment=\"simulator\"
        ios_deployment_target=\"${IOS_MIN}\"
        libyuv_use_neon=true
        use_blink=true
      ";;
    tvos-sim-x64)
      echo "${common}
        target_os=\"ios\"
        target_platform=\"tvos\"
        target_cpu=\"x64\"
        target_environment=\"simulator\"
        ios_deployment_target=\"${IOS_MIN}\"
        libyuv_use_neon=false
        use_blink=true
      ";;

    *) echo "error: unknown slice $slice" >&2; exit 1;;
  esac
}

# Emits a filelist of .o files (non-empty only) from one or more dirs.
# Prints the path to the generated filelist on stdout.
# Usage: filelist="$(make_objects_filelist "${outdir}" "${dir1}" "${dir2}" ...)"
make_objects_filelist() {
  local outdir="$1"; shift
  local filelist="${outdir}/pack/objects.txt"
  mkdir -p "${outdir}/pack"
  : > "${filelist}"

  local d obj
  for d in "$@"; do
    [[ -d "$d" ]] || continue
    # NUL-safe enumeration; keep only objects that have at least one symbol.
    while IFS= read -r -d '' obj; do
      if xcrun nm -aj "$obj" 2>/dev/null | grep -q .; then
        printf '%s\n' "$obj" >> "$filelist"
      fi
    done < <(find "$d" -type f -name '*.o' -print0)
  done

  # Deterministic order helps reproducibility
  LC_ALL=C sort -o "$filelist" "$filelist"
  printf '%s\n' "$filelist"
}

# Merge ARM64 and x86_64 static libs into a single fat archive for a platform family.
# Usage:
#   uni="$(coalesce_universal "mac"  "$OUT_ROOT/mac-arm64/pack/libyuv.a" \
#                               "$OUT_ROOT/mac-x64/pack/libyuv.a")"
#   # $uni will be the universal path if both existed, or the sole input if only one existed,
#   # or empty if neither existed.
coalesce_universal() {
  local label="$1" arm_path="$2" x64_path="$3"
  local outdir="${OUT_ROOT}/${label}-universal"
  local uni="${outdir}/libyuv.a"

  if [[ -f "$arm_path" && -f "$x64_path" ]]; then
    mkdir -p "$outdir"
    xcrun lipo -create -output "$uni" "$arm_path" "$x64_path"
    printf '%s\n' "$uni"
  elif [[ -f "$arm_path" ]]; then
    printf '%s\n' "$arm_path"
  elif [[ -f "$x64_path" ]]; then
    printf '%s\n' "$x64_path"
  else
    printf ''  # neither exists
  fi
}

# Build a slice with GN and ninja
build_slice() {
  local slice="$1"
  local outdir; outdir="$(slice_outdir "$slice")"
  mkdir -p "${outdir}"
  local log="${outdir}/gn.log"

  local args; args="$(gen_args_for_slice "$slice")"

  echo "==> gn gen ${slice}" >&2
  # Run gn from inside the libyuv checkout so the depot_tools wrapper is happy.
  if ! ( cd "${SRC_DIR}" && "${GN}" gen "${outdir}" --root="${SRC_DIR}" --args="${args}" ) >"${log}" 2>&1; then
    echo "error: gn gen failed for ${slice}. See ${log}" >&2
    sed -n '1,120p' "${log}" >&2
    exit 1
  fi

  [[ -f "${outdir}/build.ninja" ]] || {
    echo "error: gn did not produce ${outdir}/build.ninja for ${slice}" >&2
    sed -n '1,120p' "${log}" >&2
    exit 1
  }

  echo "==> ninja ${slice}" >&2
  "${NINJA}" -C "${outdir}" libyuv >/dev/null  # or libyuv_internal [libyuv_neon]

  # Build a filtered filelist from core (+ NEON if present)
  local filelist
  filelist="$(make_objects_filelist "${outdir}" \
           "${outdir}/obj/libyuv_internal" \
           "${outdir}/obj/libyuv_neon")"

  # Pack non-thin archive from the filelist
  xcrun libtool -static -o "${outdir}/pack/libyuv.a" -filelist "${filelist}"
  # optional: xcrun strip -S -x "${outdir}/pack/libyuv.a"

  # Return ONLY the path (stdout)
  printf '%s\n' "${outdir}/pack/libyuv.a"
}

# Write an overlay of headers + module map, then pass this to -headers
ensure_headers_overlay() {
  OVERLAY_HEADERS="${WORK_DIR}/headers"
  mkdir -p "${OVERLAY_HEADERS}"
  rsync -a --delete "${HEADERS_DIR}/" "${OVERLAY_HEADERS}/"

  # Only create if not present in upstream
  if [[ ! -f "${OVERLAY_HEADERS}/module.modulemap" ]]; then
    cat > "${OVERLAY_HEADERS}/module.modulemap" <<'EOF'
module libyuv [system] {
  umbrella header "libyuv.h"
  export *
}
EOF
  fi
}

# Write a manifest with the libyuv version and build configuration
write_manifest() {
  local mf="${DIST_DIR}/BUILD-METADATA.txt"
  {
    echo "libyuv commit: $(cd "${SRC_DIR}" && git rev-parse --short=12 HEAD 2>/dev/null || echo 'unknown')"
    echo "Built on: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "iOS min: 13.0 | macOS min: 11.0 | Catalyst iOS min: 14.0 | tvOS min: 13.0"
    echo "Flags: symbol_level=0 optimize_for_size=true libyuv_disable_jpeg=true neon(arm64)=on sve=sme=off"
  } > "${mf}"
}

# ---------- build all slices ----------
declare -a LIBS=()
for s in "${SLICES[@]}"; do
  LIBS+=( "$(build_slice "$s")" )
done

# ---------- build fat libs ----------

# macOS
mac_uni="$(coalesce_universal "mac" \
          "${OUT_ROOT}/mac-arm64/pack/libyuv.a" \
          "${OUT_ROOT}/mac-x64/pack/libyuv.a")"

# Mac Catalyst
cat_uni="$(coalesce_universal "maccatalyst" \
          "${OUT_ROOT}/maccatalyst-arm64/pack/libyuv.a" \
          "${OUT_ROOT}/maccatalyst-x64/pack/libyuv.a")"

# iOS Simulator
ios_sim_uni="$(coalesce_universal "ios-sim" \
          "${OUT_ROOT}/ios-sim-arm64/pack/libyuv.a" \
          "${OUT_ROOT}/ios-sim-x64/pack/libyuv.a")"

# tvOS Simulator
tvos_sim_uni="$(coalesce_universal "tvos-sim" \
          "${OUT_ROOT}/tvos-sim-arm64/pack/libyuv.a" \
          "${OUT_ROOT}/tvos-sim-x64/pack/libyuv.a")"


# Rebuild LIBS with exactly one entry per family.
# Keep device as-is; replace family pairs with the coalesced result if present.
new_libs=()
for lib in "${LIBS[@]}"; do
  case "$lib" in
    */mac-arm64/*|*/mac-x64/*) ;;           # skip; replaced by $mac_uni
    */maccatalyst-arm64/*|*/maccatalyst-x64/*) ;;  # skip; replaced by $cat_uni
    */ios-sim-arm64/*|*/ios-sim-x64/*) ;;   # skip; replaced by $ios_sim_uni
    */tvos-sim-arm64/*|*/tvos-sim-x64/*) ;;   # skip; replaced by tvos_sim_uni
    *) new_libs+=("$lib") ;;
  esac
done
[[ -n "$mac_uni" ]] && new_libs+=("$mac_uni")
[[ -n "$cat_uni" ]] && new_libs+=("$cat_uni")
[[ -n "$ios_sim_uni" ]] && new_libs+=("$ios_sim_uni")
[[ -n "$tvos_sim_uni" ]] && new_libs+=("$tvos_sim_uni")
LIBS=("${new_libs[@]}")

for lib in "${LIBS[@]}"; do
  printf '✓ %s (%s)\n' "$lib" "$(xcrun lipo -info "$lib" 2>/dev/null || echo 'thin')"
done >&2

# ---------- create XCFramework ----------
ensure_headers_overlay

XC_ARGS=()
for lib in "${LIBS[@]}"; do
  XC_ARGS+=( -library "$lib" -headers "$OVERLAY_HEADERS" )
done

XC_OUT="${DIST_DIR}/${XCFRAMEWORK_NAME}"
rm -rf "${XC_OUT}"
echo "==> xcodebuild -create-xcframework" >&2
"${XCBUILD}" -create-xcframework "${XC_ARGS[@]}" -output "${XC_OUT}"

echo "==> Wrote ${XC_OUT}"

# ---------- write manifest ----------
write_manifest
echo "==> Wrote manifest to ${DIST_DIR}/BUILD-METADATA.txt"
