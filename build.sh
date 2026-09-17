#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Options shared by every target.
# GHCR_MIRROR=nju pulls build-cache artifacts from ghcr.nju.edu.cn instead of
# the slow ghcr.io (see main-config.sh:294). A cache miss falls back to a local
# build, so it never blocks on ghcr.io. Use REGIONAL_MIRROR=china to also switch
# the git/apt/mainline mirrors.
common_args=(
	CUSTOM_UBUNTU_MIRROR_PORTS=repo.huaweicloud.com/ubuntu-ports/
	KERNEL_CONFIGURE=no
	PACKAGE_LIST_RM=armbian-zsh
	GHCR_MIRROR=nju
	# Armbian excludes /home/* when assembling the image; keep the
	# customize-image-created user home (e.g. /home/robo) instead.
	INCLUDE_HOME_DIR=yes
)

usage() {
	cat >&2 <<-EOF
	Usage: $0 <target> [variant]

	  target:
	    robopi2            RK3588 RoboPi2 (noble)
	    rdk-x5 | rdk       D-Robotics RDK X5 (jammy)

	  variant (default: all):
	    robopi2            all | desktop | cli
	    rdk-x5             all | vendor | vendor-rt

	Backwards compatible: '$0 all|desktop|cli' builds robopi2.
	EOF
}

run_build() {
	./compile.sh build "$@"
}

# ---------------------------------------------------------------- robopi2
robopi2_common=(
	BOARD=robopi2
	BRANCH=current
	RELEASE=noble
	BUILD_MINIMAL=no
	VENDOR=roboparty-os
)

robopi2_desktop() {
	run_build "${robopi2_common[@]}" "${common_args[@]}" \
		BUILD_DESKTOP=yes \
		DESKTOP_ENVIRONMENT=xfce \
		DESKTOP_TIER=minimal \
		BUILD_ROS2=yes \
		BUILD_ROBOPARTY_PACKAGES=yes
}

robopi2_cli() {
	run_build "${robopi2_common[@]}" "${common_args[@]}" \
		BUILD_DESKTOP=no
}

# ---------------------------------------------------------------- RDK X5
rdk_common=(
	BOARD=rdk-x5
	RELEASE=noble
	BUILD_DESKTOP=no
	BUILD_MINIMAL=no
)

rdk_vendor() {
	run_build "${rdk_common[@]}" "${common_args[@]}" \
		BRANCH=vendor
}

rdk_vendor_rt() {
	run_build "${rdk_common[@]}" "${common_args[@]}" \
		BRANCH=vendor-rt
}

# ---------------------------------------------------------------- dispatch
first="${1:-all}"
second="${2:-all}"

case "${first}" in
	all | desktop | cli)
		target="robopi2"
		variant="${first}"
		;;
	robopi2 | rdk-x5 | rdk)
		target="${first}"
		variant="${second}"
		;;
	-h | --help | help)
		usage
		exit 0
		;;
	*)
		usage
		exit 2
		;;
esac

case "${target}" in
	robopi2)
		case "${variant}" in
			all) robopi2_desktop && robopi2_cli ;;
			desktop) robopi2_desktop ;;
			cli) robopi2_cli ;;
			*) usage; exit 2 ;;
		esac
		;;
	rdk-x5 | rdk)
		case "${variant}" in
			all) rdk_vendor && rdk_vendor_rt ;;
			vendor) rdk_vendor ;;
			vendor-rt) rdk_vendor_rt ;;
			*) usage; exit 2 ;;
		esac
		;;
esac
