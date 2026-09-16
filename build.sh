#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

readonly BUILD_MODE="${1:-all}"

common_args=(
	BOARD=robopi2
	BRANCH=current
	RELEASE=noble
	CUSTOM_UBUNTU_MIRROR_PORTS=repo.huaweicloud.com/ubuntu-ports/
	BUILD_MINIMAL=no
	KERNEL_CONFIGURE=no
	VENDOR=roboparty-os
	PACKAGE_LIST_RM=armbian-zsh
)

build_desktop() {
	./compile.sh build \
		"${common_args[@]}" \
		BUILD_DESKTOP=yes \
		DESKTOP_ENVIRONMENT=xfce \
		DESKTOP_TIER=minimal \
		BUILD_ROS2=yes \
		BUILD_ROBOPARTY_PACKAGES=yes
}

build_cli() {
	./compile.sh build \
		"${common_args[@]}" \
		BUILD_DESKTOP=no
}

case "${BUILD_MODE}" in
	desktop)
		build_desktop
		;;
	cli)
		build_cli
		;;
	all)
		build_desktop
		build_cli
		;;
	*)
		echo "Usage: $0 [all|desktop|cli]" >&2
		exit 2
		;;
esac
