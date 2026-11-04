#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# packages/blobs/zlg -> repo root (bsp/roboparty_build)
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
readonly ARCHIVE="${SCRIPT_DIR}/usbcanfd_2.10_251215.zip"
readonly ARCHIVE_SOURCE_DIR="usbcanfd_2.10_251215/usbcanfd200_400u_2.10"
# Extract into the build cache, never into the source tree.
readonly OUTPUT_DIR="${REPO_ROOT}/cache/sources/zlg-usbcanfd"
readonly CACHE_ROOT="${REPO_ROOT}/cache/sources"

if ! command -v unzip >/dev/null 2>&1; then
	echo "error: unzip is required" >&2
	exit 1
fi

if [[ ! -f "${ARCHIVE}" ]]; then
	echo "error: archive not found: ${ARCHIVE}" >&2
	exit 1
fi

expected_hash="$(awk '{print $1}' "${ARCHIVE}.sha256")"
actual_hash="$(sha256sum "${ARCHIVE}" | awk '{print $1}')"
if [[ "${expected_hash}" != "${actual_hash}" ]]; then
	echo "error: checksum mismatch for $(basename -- "${ARCHIVE}")" >&2
	exit 1
fi

mkdir -p "${CACHE_ROOT}"
work_dir="$(mktemp -d "${CACHE_ROOT}/.unpack-usbcanfd.XXXXXX")"
trap 'rm -rf -- "${work_dir}"' EXIT

echo "Extracting $(basename -- "${ARCHIVE}")..."
unzip -q "${ARCHIVE}" "${ARCHIVE_SOURCE_DIR}/*" -d "${work_dir}"

source_dir="${work_dir}/${ARCHIVE_SOURCE_DIR}"
if [[ ! -f "${source_dir}/usbcanfd.c" || ! -f "${source_dir}/Makefile" ]]; then
	echo "error: archive does not contain the expected usbcanfd source tree" >&2
	exit 1
fi

rm -rf -- "${OUTPUT_DIR}"
mv -- "${source_dir}" "${OUTPUT_DIR}"

echo "ZLG usbcanfd sources are ready in ${OUTPUT_DIR}"
