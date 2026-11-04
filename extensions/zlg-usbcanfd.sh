# @description Builds the ZLG USBCANFD SocketCAN driver and ships it in the kernel package.
# Driver: ZLG usbcanfd 2.10 (usbcanfd_2.10_251215.zip)
# Upstream: https://manual.zlg.cn/web/#/146 (CAN驱动合集 -> socketcan)

function extension_prepare_config__zlg_usbcanfd() {
	local unpack_script="${SRC}/packages/blobs/zlg/unpack-usbcanfd.sh"

	[[ -x "${unpack_script}" ]] || exit_with_error "ZLG USBCANFD" "Missing ${unpack_script}"
	display_alert "ZLG USBCANFD" "Extracting vendor driver sources" "info"
	run_host_command_logged "${unpack_script}"
}

function artifact_kernel_version_parts__zlg_usbcanfd() {
	local source_root="${SRC}/packages/blobs/zlg"
	local hash_files="undetermined"

	calculate_hash_for_files \
		"${source_root}/usbcanfd_2.10_251215.zip" \
		"${source_root}/usbcanfd_2.10_251215.zip.sha256" \
		"${source_root}/unpack-usbcanfd.sh" \
		"${source_root}/usbcanfd-linux-6.16-compat.patch"

	artifact_version_parts["_ZLG_USBCANFD"]="zlg${hash_files:0:8}"
	artifact_version_part_order+=("0089-_ZLG_USBCANFD")
}

function pre_package_kernel_image__zlg_usbcanfd() {
	local source_root="${SRC}/cache/sources/zlg-usbcanfd"
	local compat_patch="${SRC}/packages/blobs/zlg/usbcanfd-linux-6.16-compat.patch"
	local module_build_dir="${WORKDIR}/zlg-usbcanfd-${kernel_version_family}"
	local module_install_dir="${tmp_kernel_install_dirs[INSTALL_MOD_PATH]}/lib/modules/${kernel_version_family}/extra/zlg-usbcanfd"

	[[ -f "${source_root}/usbcanfd.c" ]] || exit_with_error "ZLG USBCANFD" "Missing driver sources: ${source_root}"
	[[ -f "${compat_patch}" ]] || exit_with_error "ZLG USBCANFD" "Missing compatibility patch: ${compat_patch}"
	display_alert "ZLG USBCANFD" "Building usbcanfd for ${kernel_version_family}" "info"

	rm -rf "${module_build_dir}"
	install -d -m 0755 "${module_build_dir}" "${module_install_dir}"
	cp -a "${source_root}/." "${module_build_dir}/"
	patch --batch --forward -d "${module_build_dir}" -p1 < "${compat_patch}"

	run_kernel_make -C "${kernel_work_dir}" "M=${module_build_dir}" modules
	[[ -f "${module_build_dir}/usbcanfd.ko" ]] || exit_with_error "ZLG USBCANFD" "Missing usbcanfd.ko after build"
	install -m 0644 "${module_build_dir}/usbcanfd.ko" "${module_install_dir}/"
	depmod -b "${tmp_kernel_install_dirs[INSTALL_MOD_PATH]}" "${kernel_version_family}"
	rm -rf "${module_build_dir}"
}
