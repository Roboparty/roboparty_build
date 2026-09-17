#!/usr/bin/env bash
#
# build-adbd.sh -- reproducible aarch64 cross-build of the device-side adbd
# shipped by the adbd extension.
#
# Source: https://github.com/happyme531/standalone-linux-adbd
#   AOSP ADB 36.0.1 ported to glibc as a fully static standalone Linux daemon,
#   with TCP/VSOCK/USB FunctionFS and Rockchip usbdevice compatibility.
#
# The stripped static aarch64 binary is written to ADBD_OUTPUT (defaults to the
# build cache, never the source tree) and is NOT committed.  A `<OUTPUT>.commit`
# marker keys the cache to the pinned upstream commit, so repeat builds are a
# no-op unless the commit changes (or ADBD_FORCE_REBUILD=1).  extensions/adbd/
# adbd.sh invokes this automatically at image-build time (pre_customize_image).
#
# Requirements on the build host:
#   - git, cmake, ninja, perl
#   - aarch64-linux-gnu-gcc and aarch64-linux-gnu-g++  (e.g. gcc-11/g++-11)
#
# Usage:
#   ./extensions/adbd/build-adbd.sh
#   ADBD_OUTPUT=/tmp/adbd ./extensions/adbd/build-adbd.sh
#   ADBD_UPSTREAM=/path/to/standalone-linux-adbd ./extensions/adbd/build-adbd.sh
#
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

# Immutable upstream revision (parent commit pins the vendored submodules too).
readonly ADBD_UPSTREAM_URL="https://github.com/happyme531/standalone-linux-adbd"
readonly ADBD_UPSTREAM_COMMIT="bdb5cdc4b516b3bc71fd2b805bc36190041a9393"

# All state lives under the build cache (git-ignored via the top-level
# `/cache/` rule) so nothing is ever written back into the source tree.
readonly CACHE_ROOT="${ADBD_CACHE_ROOT:-${REPO_DIR}/cache/sources/adbd}"
readonly WORK_DIR="${ADBD_UPSTREAM:-${CACHE_ROOT}/standalone-linux-adbd}"
readonly BUILD_DIR="${ADBD_BUILD_DIR:-${CACHE_ROOT}/build}"
readonly OUTPUT="${ADBD_OUTPUT:-${CACHE_ROOT}/adbd}"

# Commit-keyed binary cache: `<OUTPUT>.commit` records which upstream commit the
# cached binary was built from. Set ADBD_FORCE_REBUILD=1 to bypass it.
readonly CACHE_MARKER="${OUTPUT}.commit"
readonly FORCE_REBUILD="${ADBD_FORCE_REBUILD:-0}"

readonly CROSS_GCC="${CROSS_GCC:-aarch64-linux-gnu-gcc}"
readonly CROSS_GXX="${CROSS_GXX:-aarch64-linux-gnu-g++}"
readonly CROSS_STRIP="${CROSS_STRIP:-aarch64-linux-gnu-strip}"

log() { printf '[build-adbd] %s\n' "$*" >&2; }
die() { printf '[build-adbd] ERROR: %s\n' "$*" >&2; exit 1; }

cached_binary_is_current() {
	[[ "${FORCE_REBUILD}" == "1" ]] && return 1
	[[ -x "${OUTPUT}" && -f "${CACHE_MARKER}" ]] || return 1
	[[ "$(< "${CACHE_MARKER}")" == "${ADBD_UPSTREAM_COMMIT}" ]]
}

check_tools() {
	local t
	for t in git cmake ninja perl "${CROSS_GCC}" "${CROSS_GXX}" "${CROSS_STRIP}"; do
		command -v "${t}" >/dev/null || die "missing tool: ${t}"
	done
}

sync_upstream() {
	if [[ ! -d "${WORK_DIR}/.git" ]]; then
		log "cloning ${ADBD_UPSTREAM_URL} @ ${ADBD_UPSTREAM_COMMIT:0:12}"
		mkdir -p "$(dirname "${WORK_DIR}")"
		git clone "${ADBD_UPSTREAM_URL}" "${WORK_DIR}"
	fi
	git -C "${WORK_DIR}" fetch --depth 1 origin "${ADBD_UPSTREAM_COMMIT}"
	git -C "${WORK_DIR}" checkout --detach "${ADBD_UPSTREAM_COMMIT}"

	# Only the submodules the adbd-only build needs (the repo also vendors
	# fastboot/e2fsprogs/etc. submodules which we do not want to download).
	local required_submodules=(
		vendor/adb
		vendor/core
		vendor/fmtlib
		vendor/libbase
		vendor/logging
		vendor/third_party/brotli
		vendor/third_party/lz4
		vendor/third_party/zstd
	)
	local missing=() sub
	for sub in "${required_submodules[@]}"; do
		[[ -e "${WORK_DIR}/${sub}/.git" ]] || missing+=("${sub}")
	done
	if (( ${#missing[@]} )); then
		log "syncing required submodules (${#missing[@]})"
		git -C "${WORK_DIR}" submodule update --init --depth 1 "${missing[@]}"
	else
		log "required submodules already present"
	fi
}

build_adbd() {
	local toolchain="${WORK_DIR}/cmake/toolchains/aarch64-linux-gnu.cmake"
	[[ -f "${toolchain}" ]] || die "missing toolchain file: ${toolchain}"

	rm -rf "${BUILD_DIR}"

	log "configuring + building (jobs=${ANDROID_TOOLS_BUILD_JOBS:-$(nproc)})"
	CMAKE_TOOLCHAIN_FILE="${toolchain}" \
		ANDROID_TOOLS_BUILD_JOBS="${ANDROID_TOOLS_BUILD_JOBS:-$(nproc)}" \
		"${WORK_DIR}/scripts/build-linux-adbd.sh" "${BUILD_DIR}"

	local built="${BUILD_DIR}/vendor/adbd"
	[[ -f "${built}" ]] || die "expected artifact not found: ${built}"

	log "stripping and installing to ${OUTPUT}"
	install -D -m 0755 "${built}" "${OUTPUT}"
	"${CROSS_STRIP}" --strip-all "${OUTPUT}"

	file "${OUTPUT}"
	sha256sum "${OUTPUT}"
	# ldd should report "not a dynamic executable" (fully static).
	printf '%s\n' "${ADBD_UPSTREAM_COMMIT}" > "${CACHE_MARKER}"
	log "done: ${OUTPUT}"
}

main() {
	if cached_binary_is_current; then
		log "cache hit: ${OUTPUT} (upstream ${ADBD_UPSTREAM_COMMIT:0:12}); set ADBD_FORCE_REBUILD=1 to rebuild"
		return 0
	fi
	check_tools
	sync_upstream
	build_adbd
}

main "$@"
