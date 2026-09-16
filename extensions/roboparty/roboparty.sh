function post_customize_image__install_roboparty() {
	[[ "${BUILD_ROBOPARTY_PACKAGES}" == "yes" ]] || return 0
	local roboparty_dist="${BOARD}"
	# case "${roboparty_dist}" in robopi1|robopi2|robopi3) ;; *) return 0 ;; esac

	install -d "${SDCARD}/usr/share/keyrings" "${SDCARD}/etc/apt/sources.list.d"
	curl -fsSL "http://apt.roboparty.com/roboparty.gpg" | gpg --dearmor --yes -o "${SDCARD}/usr/share/keyrings/roboparty-archive-keyring.gpg"
	chmod 644 "${SDCARD}/usr/share/keyrings/roboparty-archive-keyring.gpg"
	cat > "${SDCARD}/etc/apt/sources.list.d/roboparty.list" <<- EOF
		deb [arch=arm64 signed-by=/usr/share/keyrings/roboparty-archive-keyring.gpg] http://apt.roboparty.com common main
		deb [arch=arm64 signed-by=/usr/share/keyrings/roboparty-archive-keyring.gpg] http://apt.roboparty.com ${roboparty_dist} main
	EOF
	chroot_sdcard_apt_get_update
	# Bring the base rootfs up to date after adding the RoboParty repository.
	chroot_sdcard_apt_get upgrade
	chroot_sdcard_apt_get_install roboparty-all robopi-config

	local realtime_unit realtime_dropin_dir
	for realtime_unit in rp-server.service bms.service; do
		realtime_dropin_dir="${SDCARD}/etc/systemd/system/${realtime_unit}.d"
		install -d -m 0755 "${realtime_dropin_dir}"
		cat > "${realtime_dropin_dir}/10-realtime.conf" <<- EOF
			[Service]
			LimitRTPRIO=99
			LimitMEMLOCK=infinity
		EOF
	done
	# robopi-config

	# Ensure the selected target locale is generated in the customized rootfs.
	local target_locale="${DEST_LANG:-en_US.UTF-8}"
	if [[ -f "${SDCARD}/etc/locale.gen" ]]; then
		sed -i -E "s|^[#[:space:]]*(${target_locale//./\\.}[[:space:]]+UTF-8)|\\1|" "${SDCARD}/etc/locale.gen" || true
	fi
	chroot_sdcard LC_ALL=C LANG=C locale-gen "${target_locale}"
	chroot_sdcard LC_ALL=C LANG=C update-locale "LANG=${target_locale}" "LANGUAGE=${target_locale}" "LC_MESSAGES=${target_locale}"
}
