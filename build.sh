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
	REGIONAL_MIRROR=china
	KERNEL_CONFIGURE=no
	PACKAGE_LIST_RM=armbian-zsh
	GHCR_MIRROR=nju
	# Armbian excludes /home/* when assembling the image; keep the
	# customize-image-created user home (e.g. /home/robo) instead.
	INCLUDE_HOME_DIR=yes
	INSTALL_ETHERCAT=yes
)

# Options shared by kernel-only artifact builds. EtherCAT modules are staged
# into the kernel image, so keep INSTALL_ETHERCAT in sync with image builds.
kernel_args=(
	KERNEL_CONFIGURE=no
	REGIONAL_MIRROR=china
	GHCR_MIRROR=nju
	PREFER_DOCKER=no
	INSTALL_ETHERCAT=yes
)

# Options shared by userspace-only artifact builds (no kernel/image compile).
artifact_args=(
	REGIONAL_MIRROR=china
	GHCR_MIRROR=nju
	PREFER_DOCKER=no
)

# amd64 build uses the UEFI x86 board only to select ARCH=amd64.
ethercat_amd64_common=(
	BOARD=uefi-x86
	BRANCH=current
	RELEASE=noble
	VENDOR=roboparty-os
)

usage() {
	cat >&2 <<-EOF
	Usage: $0 <target> [variant]

	  target:
	    robopi2            RK3588 RoboPi2 (noble)
	    opi5plus | orangepi5-plus  RK3588 Orange Pi 5 Plus (noble)
	    rdk-x5 | rdk       D-Robotics RDK X5 (noble)

	  variant (default: all):
	    robopi2            all | desktop | cli | kernel | ethercat | bsp-cli | packages
	    opi5plus           all | desktop | cli | kernel | ethercat | bsp-cli | packages
	    rdk-x5             desktop | kernel | ethercat | bsp-cli | packages

	  kernel builds kernel debs only.
	  ethercat builds userspace ethercat-dev for arm64 and amd64.
	  bsp-cli builds armbian-bsp-cli only.
	  packages builds ethercat + bsp-cli, no kernel/image.
	  rdk-x5 uses vendor-rt for all variants.

	Backwards compatible: '$0 all|desktop|cli' builds robopi2.
	EOF
}

run_build() {
	./compile.sh build "$@"
}

run_kernel() {
	./compile.sh kernel "$@"
}

# Build a single userspace artifact without compiling the kernel or an image.
# WHAT is the Armbian artifact name (e.g. ethercat, armbian-bsp-cli).
run_artifact() {
	local what=$1
	shift
	./compile.sh artifact WHAT="${what}" "$@"
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

robopi2_kernel() {
	run_kernel "${robopi2_common[@]}" "${kernel_args[@]}"
}

# EtherCAT userspace (ethercat-dev) for arm64 and amd64. Kernel modules stay in the kernel.
robopi2_ethercat() {
	run_artifact ethercat "${robopi2_common[@]}" "${artifact_args[@]}" INSTALL_ETHERCAT=yes
	run_artifact ethercat "${ethercat_amd64_common[@]}" "${artifact_args[@]}" INSTALL_ETHERCAT=yes
}

# BSP config package only (armbian-bsp-cli-robopi2).
robopi2_bsp_cli() {
	run_artifact armbian-bsp-cli "${robopi2_common[@]}" "${artifact_args[@]}"
}

# Userspace bundle: EtherCAT + BSP CLI, no kernel/image build.
robopi2_packages() {
	robopi2_ethercat && robopi2_bsp_cli
}

# ---------------------------------------------------------------- Orange Pi 5 Plus
opi5plus_common=(
	BOARD=orangepi5-plus
	BRANCH=current
	RELEASE=noble
	BUILD_MINIMAL=no
	VENDOR=roboparty-os
)

opi5plus_desktop() {
	run_build "${opi5plus_common[@]}" "${common_args[@]}" \
		BUILD_DESKTOP=yes \
		DESKTOP_ENVIRONMENT=xfce \
		DESKTOP_TIER=minimal \
		BUILD_ROS2=yes \
		BUILD_ROBOPARTY_PACKAGES=yes
}

opi5plus_cli() {
	run_build "${opi5plus_common[@]}" "${common_args[@]}" \
		BUILD_DESKTOP=no
}

opi5plus_kernel() {
	run_kernel "${opi5plus_common[@]}" "${kernel_args[@]}"
}

# EtherCAT userspace for arm64 and amd64.
opi5plus_ethercat() {
	run_artifact ethercat "${opi5plus_common[@]}" "${artifact_args[@]}" INSTALL_ETHERCAT=yes
	run_artifact ethercat "${ethercat_amd64_common[@]}" "${artifact_args[@]}" INSTALL_ETHERCAT=yes
}

# BSP config package only (armbian-bsp-cli-orangepi5-plus*).
opi5plus_bsp_cli() {
	run_artifact armbian-bsp-cli "${opi5plus_common[@]}" "${artifact_args[@]}"
}

# Userspace bundle: EtherCAT + BSP CLI, no kernel/image build.
opi5plus_packages() {
	opi5plus_ethercat && opi5plus_bsp_cli
}

# ---------------------------------------------------------------- RDK X5
rdk_common=(
	BOARD=rdk-x5
	BRANCH=vendor-rt
	RELEASE=noble
	BUILD_MINIMAL=no
	VENDOR=roboparty-os
)

rdk_desktop() {
	run_build "${rdk_common[@]}" "${common_args[@]}" \
		BUILD_DESKTOP=yes \
		DESKTOP_ENVIRONMENT=xfce \
		DESKTOP_TIER=minimal \
		BUILD_ROS2=yes \
		BUILD_ROBOPARTY_PACKAGES=yes
}

rdk_kernel() {
	run_kernel "${rdk_common[@]}" "${kernel_args[@]}"
}

# EtherCAT userspace for arm64 and amd64.
rdk_ethercat() {
	run_artifact ethercat "${rdk_common[@]}" "${artifact_args[@]}" INSTALL_ETHERCAT=yes
	run_artifact ethercat "${ethercat_amd64_common[@]}" "${artifact_args[@]}" INSTALL_ETHERCAT=yes
}

# BSP config package only (armbian-bsp-cli-rdk-x5-vendor-rt).
rdk_bsp_cli() {
	run_artifact armbian-bsp-cli "${rdk_common[@]}" "${artifact_args[@]}"
}

# Userspace bundle: EtherCAT + BSP CLI, no kernel/image build.
rdk_packages() {
	rdk_ethercat && rdk_bsp_cli
}

# ---------------------------------------------------------------- dispatch
first="${1:-all}"
second="${2:-all}"

case "${first}" in
	all | desktop | cli | kernel | ethercat | bsp-cli | packages)
		target="robopi2"
		variant="${first}"
		;;
	robopi2 | rdk-x5 | rdk)
		target="${first}"
		variant="${second}"
		;;
	opi5plus | orangepi5-plus)
		target="opi5plus"
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
			kernel) robopi2_kernel ;;
			ethercat) robopi2_ethercat ;;
			bsp-cli) robopi2_bsp_cli ;;
			packages) robopi2_packages ;;
			*) usage; exit 2 ;;
		esac
		;;
	opi5plus)
		case "${variant}" in
			all) opi5plus_desktop && opi5plus_cli ;;
			desktop) opi5plus_desktop ;;
			cli) opi5plus_cli ;;
			kernel) opi5plus_kernel ;;
			ethercat) opi5plus_ethercat ;;
			bsp-cli) opi5plus_bsp_cli ;;
			packages) opi5plus_packages ;;
			*) usage; exit 2 ;;
		esac
		;;
	rdk-x5 | rdk)
		case "${variant}" in
			desktop) rdk_desktop ;;
			kernel) rdk_kernel ;;
			ethercat) rdk_ethercat ;;
			bsp-cli) rdk_bsp_cli ;;
			packages) rdk_packages ;;
			*) usage; exit 2 ;;
		esac
		;;
esac
