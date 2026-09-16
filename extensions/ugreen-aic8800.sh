# @description Builds the UGREEN AX300 AIC8800 USB Wi-Fi/Bluetooth driver and installs its firmware.

function extension_prepare_config__ugreen_aic8800() {
	local unpack_script="${SRC}/packages/bsp/ugreen/unpack.sh"

	[[ -x "${unpack_script}" ]] || exit_with_error "UGREEN AIC8800" "Missing ${unpack_script}"
	display_alert "UGREEN AIC8800" "Extracting vendor driver sources" "info"
	run_host_command_logged "${unpack_script}"
	add_packages_to_image eject
}

function artifact_kernel_version_parts__ugreen_aic8800() {
	local vendor_archive="${SRC}/packages/bsp/ugreen/UGREEN_AIC-AX300_LinuxDriver_V1.6.zip"
	local compat_patch="${SRC}/packages/bsp/ugreen/aic8800-linux-6.18-compat.patch"
	local unpack_script="${SRC}/packages/bsp/ugreen/unpack.sh"
	local hash_files="undetermined"

	[[ -f "${vendor_archive}" ]] || exit_with_error "UGREEN AIC8800" "Missing ${vendor_archive}"
	[[ -f "${compat_patch}" ]] || exit_with_error "UGREEN AIC8800" "Missing ${compat_patch}"
	[[ -f "${unpack_script}" ]] || exit_with_error "UGREEN AIC8800" "Missing ${unpack_script}"
	calculate_hash_for_files "${vendor_archive}" "${compat_patch}" "${unpack_script}"

	artifact_version_parts["_UGREEN_AIC"]="ugreen${hash_files:0:8}"
	artifact_version_part_order+=("0088-_UGREEN_AIC")
}

function pre_package_kernel_image__ugreen_aic8800() {
	local source_root="${SRC}/packages/bsp/ugreen/aic8800"
	local compat_patch="${SRC}/packages/bsp/ugreen/aic8800-linux-6.18-compat.patch"
	local module_build_dir="${WORKDIR}/ugreen-aic8800-${kernel_version_family}"
	local module_source_dir="${module_build_dir}/drivers/aic8800"
	local module_install_dir="${tmp_kernel_install_dirs[INSTALL_MOD_PATH]}/lib/modules/${kernel_version_family}/extra/ugreen-aic8800"
	local module_name

	[[ -d "${source_root}/drivers/aic8800" ]] || exit_with_error "UGREEN AIC8800" "Missing driver sources"
	[[ -f "${compat_patch}" ]] || exit_with_error "UGREEN AIC8800" "Missing Linux 6.18 compatibility patch"
	display_alert "UGREEN AIC8800" "Building modules for ${kernel_version_family}" "info"

	rm -rf "${module_build_dir}"
	install -d -m 0755 "${module_build_dir}" "${module_install_dir}"
	cp -a "${source_root}/." "${module_build_dir}/"
	patch --batch --forward -d "${module_build_dir}" -p2 < "${compat_patch}"

	run_kernel_make "M=${module_source_dir}" modules
	for module_name in aic_load_fw/aic_load_fw.ko aic8800_fdrv/aic8800_fdrv.ko; do
		[[ -f "${module_source_dir}/${module_name}" ]] || exit_with_error "UGREEN AIC8800" "Missing ${module_name} after build"
		install -m 0644 "${module_source_dir}/${module_name}" "${module_install_dir}/$(basename "${module_name}")"
	done
	depmod -b "${tmp_kernel_install_dirs[INSTALL_MOD_PATH]}" "${kernel_version_family}"
	rm -rf "${module_build_dir}"
}

function post_family_tweaks__ugreen_aic8800_files() {
	local source_root="${SRC}/packages/bsp/ugreen/aic8800"
	local udev_rules="${SRC}/packages/bsp/ugreen/aic.rules"

	[[ -f "${udev_rules}" ]] || exit_with_error "UGREEN AIC8800" "Missing ${udev_rules}"
	display_alert "UGREEN AIC8800" "Installing firmware and udev configuration" "info"
	install -d -m 0755 \
		"${destination}/lib/firmware" \
		"${destination}/etc/udev/rules.d" \
		"${destination}/etc/modules-load.d"
	cp -a "${source_root}/fw/aic8800DC" "${destination}/lib/firmware/"
	install -m 0644 "${udev_rules}" "${destination}/etc/udev/rules.d/99-ugreen-aic8800.rules"
	printf '%s\n' aic_load_fw aic8800_fdrv > "${destination}/etc/modules-load.d/ugreen-aic8800.conf"
}
