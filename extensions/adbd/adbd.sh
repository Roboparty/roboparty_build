#!/usr/bin/env bash

# The adbd binary is NOT committed and NOT written into the source tree. It is
# an AOSP ADB 36.0.1 build for Linux (fully static aarch64), produced at
# image-build time by extensions/adbd/build-adbd.sh and cached (keyed by the
# pinned upstream commit) under cache/sources/adbd. See extensions/adbd/README.md.

function add_host_dependencies__adbd_build_tools() {
	display_alert "Extension: ${EXTENSION}" "Adding adbd build tools to host dependencies" "debug"

	EXTRA_BUILD_DEPS+=("build-tools::cmake" "build-tools::ninja-build" "build-tools::perl")
	# The cross C++ compiler is skipped on hosts where it does not exist.
	if [[ "${host_arch}" != "riscv64" ]]; then
		EXTRA_BUILD_DEPS+=("cross-arm64::g++-aarch64-linux-gnu")
	fi
	EXTRA_BUILD_DEPS+=("native-toolchain::g++")
}

function pre_customize_image__adbd_build() {
	[[ "${BOARD}" == "robopi2" ]] || return 0

	local cache_root="${SRC}/cache/sources/adbd"

	display_alert "adbd" "Building standalone Linux adbd from source" "info"
	ADBD_OUTPUT="${cache_root}/adbd" \
		ADBD_BUILD_DIR="${cache_root}/build" \
		ANDROID_TOOLS_BUILD_JOBS="${ANDROID_TOOLS_BUILD_JOBS:-$(nproc)}" \
		"${SRC}/extensions/adbd/build-adbd.sh" || exit_with_error "adbd" "Failed to build adbd"
}

function post_customize_image__install_adbd() {
	[[ "${BOARD}" == "robopi2" ]] || return 0

	local files_dir="${SRC}/extensions/adbd/files"
	local binary="${SRC}/cache/sources/adbd/adbd"
	[[ -x "${binary}" ]] || exit_with_error "adbd" "adbd binary missing: ${binary}"

	install -Dm755 "${binary}" "${SDCARD}/usr/bin/adbd"
	install -Dm755 "${files_dir}/usr/bin/usbdevice" "${SDCARD}/usr/bin/usbdevice"
	install -Dm644 "${files_dir}/usr/lib/systemd/system/usbdevice.service" "${SDCARD}/usr/lib/systemd/system/usbdevice.service"
	install -Dm644 "${files_dir}/etc/profile.d/usbdevice.sh" "${SDCARD}/etc/profile.d/usbdevice.sh"
	install -Dm644 "${files_dir}/etc/modules-load.d/usb-gadget.conf" "${SDCARD}/etc/modules-load.d/usb-gadget.conf"
	chroot_sdcard systemctl enable usbdevice.service
}
