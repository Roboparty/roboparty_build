#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ARCHIVE="${SCRIPT_DIR}/UGREEN_AIC-AX300_LinuxDriver_V1.6.zip"
readonly ARCHIVE_SOURCE_DIR="aic8800_linux_drvier"
readonly OUTPUT_DIR="${SCRIPT_DIR}/aic8800"

if ! command -v unzip >/dev/null 2>&1; then
	echo "error: unzip is required" >&2
	exit 1
fi

if [[ ! -f "${ARCHIVE}" ]]; then
	echo "error: archive not found: ${ARCHIVE}" >&2
	exit 1
fi

work_dir="$(mktemp -d "${SCRIPT_DIR}/.unpack-aic8800.XXXXXX")"
trap 'rm -rf -- "${work_dir}"' EXIT

echo "Extracting $(basename -- "${ARCHIVE}")..."
unzip -q "${ARCHIVE}" "${ARCHIVE_SOURCE_DIR}/*" -d "${work_dir}"

source_dir="${work_dir}/${ARCHIVE_SOURCE_DIR}"
if [[ ! -d "${source_dir}/drivers/aic8800" || ! -d "${source_dir}/fw" ]]; then
	echo "error: archive does not contain the expected AIC8800 source tree" >&2
	exit 1
fi

rm -rf -- "${OUTPUT_DIR}"
mv -- "${source_dir}" "${OUTPUT_DIR}"

echo "AIC8800 sources are ready in ${OUTPUT_DIR}"
