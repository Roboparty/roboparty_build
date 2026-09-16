#!/usr/bin/env bash

# Include the RoboPi2 WS2812 driver in the kernel artifact cache key.
function artifact_kernel_version_parts__robopi2_ws2812() {
	local driver_source="${SRC}/packages/bsp/roboparty/robopi-ws2812.c"
	local driver_hash

	[[ -f "${driver_source}" ]] || exit_with_error "${BOARD}" "Missing ${driver_source}"
	driver_hash="$(sha256sum "${driver_source}" | cut -c1-8)"
	artifact_version_parts["_WS2812"]="ws2812${driver_hash}"
	artifact_version_part_order+=("0087-_WS2812")
}

# Build the out-of-tree driver with the same tree and toolchain as the target kernel.
function pre_package_kernel_image__robopi2_ws2812() {
	local driver_source="${SRC}/packages/bsp/roboparty/robopi-ws2812.c"
	local module_build_dir="${WORKDIR}/robopi-ws2812-${kernel_version_family}"
	local module_install_dir="${tmp_kernel_install_dirs[INSTALL_MOD_PATH]}/lib/modules/${kernel_version_family}/extra"

	[[ -f "${driver_source}" ]] || exit_with_error "${BOARD}" "Missing ${driver_source}"
	display_alert "${BOARD}" "Building robopi-ws2812.ko for ${kernel_version_family}" "info"

	rm -rf "${module_build_dir}"
	install -d -m 0755 "${module_build_dir}" "${module_install_dir}"
	cp -f "${driver_source}" "${module_build_dir}/robopi-ws2812.c"
	printf '%s\n' 'obj-m := robopi-ws2812.o' > "${module_build_dir}/Makefile"

	run_kernel_make "M=${module_build_dir}" modules
	install -m 0644 "${module_build_dir}/robopi-ws2812.ko" "${module_install_dir}/robopi-ws2812.ko"
	depmod -b "${tmp_kernel_install_dirs[INSTALL_MOD_PATH]}" "${kernel_version_family}"
	rm -rf "${module_build_dir}"
}

# Load the board driver automatically during boot.
function post_family_tweaks__robopi2_ws2812_autoload() {
	install -d -m 0755 "${destination}/etc/modules-load.d"
	printf '%s\n' 'robopi-ws2812' > "${destination}/etc/modules-load.d/robopi-ws2812.conf"
}
