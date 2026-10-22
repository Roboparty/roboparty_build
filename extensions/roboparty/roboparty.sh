function post_customize_image__install_roboparty() {
	[[ "${BUILD_ROBOPARTY_PACKAGES}" == "yes" ]] || return 0

	# Temporarily disabled: install the local packages below instead.
	# local roboparty_dist=""
	# [[ "${BOARD}" == "robopi2" ]] && roboparty_dist="${BOARD}"
	# install -d "${SDCARD}/usr/share/keyrings" "${SDCARD}/etc/apt/sources.list.d"
	# curl -fsSL "http://apt.roboparty.com/roboparty.gpg" | gpg --dearmor --yes -o "${SDCARD}/usr/share/keyrings/roboparty-archive-keyring.gpg"
	# chmod 644 "${SDCARD}/usr/share/keyrings/roboparty-archive-keyring.gpg"
	# cat > "${SDCARD}/etc/apt/sources.list.d/roboparty.list" <<- EOF
	# 	deb [arch=arm64 signed-by=/usr/share/keyrings/roboparty-archive-keyring.gpg] http://apt.roboparty.com common main
	# EOF
	# if [[ -n "${roboparty_dist}" ]]; then
	# 	cat >> "${SDCARD}/etc/apt/sources.list.d/roboparty.list" <<- EOF
	# 		deb [arch=arm64 signed-by=/usr/share/keyrings/roboparty-archive-keyring.gpg] http://apt.roboparty.com ${roboparty_dist} main
	# 	EOF
	# fi
	# chroot_sdcard_apt_get_update
	# chroot_sdcard_apt_get upgrade
	# chroot_sdcard_apt_get_install roboparty-all robopi-config

	local roboparty_deb_dir="${ROBOPARTY_DEB_DIR:-${SRC}/../../hex/temp_deb}"
	local roboparty_stage="/tmp/roboparty-debs"
	local deb_file
	local -a roboparty_debs=(
		roboparty-base_1.1.8-2_all.deb
		roboparty-bms_1.5.1-1_arm64.deb
		robopi-addon_1.8.4-1_arm64.deb
		robopi-analyze_1.0.10-1_all.deb
		adbd_1.0.4-1_arm64.deb
	)
	local -a roboparty_install_paths=()
	for deb_file in "${roboparty_debs[@]}"; do
		[[ -f "${roboparty_deb_dir}/${deb_file}" ]] || exit_with_error "Missing local RoboParty package" "${roboparty_deb_dir}/${deb_file}"
		dpkg-deb --info "${roboparty_deb_dir}/${deb_file}" > /dev/null
	done

	# Cached rootfs trees may still contain the previously configured source.
	if [[ -f "${SDCARD}/etc/apt/sources.list.d/roboparty.list" ]]; then
		mv "${SDCARD}/etc/apt/sources.list.d/roboparty.list" "${SDCARD}/etc/apt/sources.list.d/roboparty.list.disabled"
	fi
	install -d -m 0755 "${SDCARD}${roboparty_stage}"
	for deb_file in "${roboparty_debs[@]}"; do
		install -m 0644 "${roboparty_deb_dir}/${deb_file}" "${SDCARD}${roboparty_stage}/${deb_file}"
		roboparty_install_paths+=("${roboparty_stage}/${deb_file}")
	done
	# Resolve dependencies from the distribution sources in one apt transaction.
	chroot_sdcard_apt_get_update
	chroot_sdcard_apt_get_install --allow-downgrades "${roboparty_install_paths[@]}"
	for deb_file in "${roboparty_debs[@]}"; do
		rm -f "${SDCARD}${roboparty_stage}/${deb_file}"
	done
	rmdir "${SDCARD}${roboparty_stage}"

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

# Runs as robo inside the target rootfs, not on the build host.
function roboparty_build_deploy() {
	set -eo pipefail
	cd /home/robo/roboparty_deploy
	source /opt/ros/jazzy/setup.bash

	# Release flags follow the upstream -march=native and keep QEMU builds portable.
	colcon build --symlink-install --parallel-workers 4 \
		--paths src/motors src/imu src/inference src/camera \
		--event-handlers console_direct+ \
		--cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
		'-DCMAKE_C_FLAGS_RELEASE=-O3 -DNDEBUG -march=armv8-a' \
		'-DCMAKE_CXX_FLAGS_RELEASE=-O3 -DNDEBUG -march=armv8-a'

	source install/setup.bash
	local package
	for package in roboparty_motors roboparty_imu roboparty_inference roboparty_camera; do
		ros2 pkg prefix "${package}"
	done
	test -x install/roboparty_inference/lib/roboparty_inference/inference_node
	test -x install/roboparty_camera/lib/roboparty_camera/depth_node
}

# Build the upstream deployment workspace in the target rootfs.
function post_customize_image__clone_roboparty_deploy() {
	[[ "${BUILD_ROBOPARTY_PACKAGES}" == "yes" ]] || return 0

	local repo_url repo_dirname
	case "${BOARD}" in
		rdk-x5 | orangepi5-plus |robopi2)
			repo_url="https://github.com/Roboparty/roboparty_deploy"
			repo_dirname="roboparty_deploy"
			;;
		*)
			return 0
			;;
	esac

	local user_name="robo"
	local user_home="/home/${user_name}"
	local clone_dir="${SDCARD}${user_home}/${repo_dirname}"

	if [[ -d "${clone_dir}/.git" ]]; then
		display_alert "RoboParty deploy" "already present at ${user_home}/${repo_dirname}" "info"
	else
		display_alert "RoboParty deploy" "cloning ${repo_url} -> ${user_home}/${repo_dirname}" "info"
		install -d -m 0755 "${SDCARD}${user_home}"
		run_host_command_logged git clone --depth=1 "${repo_url}" "${clone_dir}"
	fi

	# Follow upstream submodule branches as requested; record their exact revisions.
	run_host_command_logged git -C "${clone_dir}" submodule update --init --recursive --remote --depth=1 --jobs=4
	chroot_sdcard chown -R "${user_name}:${user_name}" "${user_home}/${repo_dirname}"

	[[ "${BUILD_ROS2}" == "yes" ]] || return 0
	[[ -f "${SDCARD}/opt/ros/jazzy/setup.bash" ]] || exit_with_error "RoboParty deploy requires ROS 2 Jazzy"
	chroot_sdcard_apt_get_install build-essential cmake ccache python3-colcon-common-extensions \
		python3-dev pybind11-dev libfmt-dev libspdlog-dev libeigen3-dev libboost-system-dev zlib1g-dev
	{
		printf '#!/usr/bin/env bash\n'
		declare -f roboparty_build_deploy
		printf '\nroboparty_build_deploy\n'
	} > "${SDCARD}/tmp/roboparty-build-deploy.sh"
	chmod 0755 "${SDCARD}/tmp/roboparty-build-deploy.sh"
	display_alert "RoboParty deploy" "building ARM64 workspace inside rootfs" "info"
	chroot_sdcard runuser -u "${user_name}" -- env HOME="${user_home}" CCACHE_DISABLE=1 \
		CMAKE_BUILD_PARALLEL_LEVEL=8 MAKEFLAGS=-j8 /tmp/roboparty-build-deploy.sh
	rm -f "${SDCARD}/tmp/roboparty-build-deploy.sh"
	install -d -m 0755 "${SDCARD}/usr/share/roboparty"
	{
		git -C "${clone_dir}" log -1 --format='deploy %H'
		git -C "${clone_dir}" submodule status --recursive
	} > "${SDCARD}/usr/share/roboparty/deploy-revisions.txt"
}
