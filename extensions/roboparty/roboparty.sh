function post_customize_image__install_roboparty() {
	[[ "${BUILD_ROS2}" == "yes" ]] || return 0
	[[ "${BUILD_ROBOPARTY_PACKAGES}" == "yes" ]] || return 0

	# Add the signed RoboParty APT repository and install the robot stack from it.
	local roboparty_dist=""
	[[ "${BOARD}" == "robopi2" ]] && roboparty_dist="${BOARD}"
	install -d "${SDCARD}/usr/share/keyrings" "${SDCARD}/etc/apt/sources.list.d"
	curl -fsSL "https://apt.roboparty.com/roboparty.gpg" \
		| gpg --batch --dearmor --yes -o "${SDCARD}/usr/share/keyrings/roboparty-archive-keyring.gpg"
	chmod 644 "${SDCARD}/usr/share/keyrings/roboparty-archive-keyring.gpg"
	cat > "${SDCARD}/etc/apt/sources.list.d/roboparty.list" <<- EOF
		deb [arch=arm64 signed-by=/usr/share/keyrings/roboparty-archive-keyring.gpg] https://apt.roboparty.com common main
	EOF
	if [[ -n "${roboparty_dist}" ]]; then
		cat >> "${SDCARD}/etc/apt/sources.list.d/roboparty.list" <<- EOF
			deb [arch=arm64 signed-by=/usr/share/keyrings/roboparty-archive-keyring.gpg] https://apt.roboparty.com ${roboparty_dist} main
		EOF
	fi
	chroot_sdcard_apt_get_update
	# chroot_sdcard_apt_get upgrade
	# robopi-tui depends on adbd; installing it pulls in the ADB daemon.
	chroot_sdcard_apt_get_install roboparty-all robopi-tui

	# Local package installation is disabled; keep this block for offline
	# fallback if the public repo is unavailable.
	# local roboparty_deb_dir="${ROBOPARTY_DEB_DIR:-${SRC}/../../hex/temp_deb}"
	# local roboparty_stage="/tmp/roboparty-debs"
	# local deb_file
	# local -a roboparty_debs=(
	# 	roboparty-base_1.1.8-2_all.deb
	# 	roboparty-bms_1.5.1-1_arm64.deb
	# 	robopi-addon_1.8.4-1_arm64.deb
	# 	robopi-analyze_1.0.10-1_all.deb
	# 	adbd_1.0.6-1_arm64.deb
	# )
	# local -a roboparty_install_paths=()
	# for deb_file in "${roboparty_debs[@]}"; do
	# 	[[ -f "${roboparty_deb_dir}/${deb_file}" ]] || exit_with_error "Missing local RoboParty package" "${roboparty_deb_dir}/${deb_file}"
	# 	dpkg-deb --info "${roboparty_deb_dir}/${deb_file}" > /dev/null
	# done

	# install -d -m 0755 "${SDCARD}${roboparty_stage}"
	# for deb_file in "${roboparty_debs[@]}"; do
	# 	install -m 0644 "${roboparty_deb_dir}/${deb_file}" "${SDCARD}${roboparty_stage}/${deb_file}"
	# 	roboparty_install_paths+=("${roboparty_stage}/${deb_file}")
	# done
	# chroot_sdcard_apt_get_update
	# chroot_sdcard_apt_get_install --allow-downgrades "${roboparty_install_paths[@]}"
	# for deb_file in "${roboparty_debs[@]}"; do
	# 	rm -f "${SDCARD}${roboparty_stage}/${deb_file}"
	# done
	# rmdir "${SDCARD}${roboparty_stage}"

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
	[[ "${BUILD_ROS2:-no}" == "yes" ]] || return 0
	cd /home/robo/roboparty_deploy

	if [[ -n "${ROS_SETUP:-}" && -f "${ROS_SETUP}" ]]; then
		source "${ROS_SETUP}"
	elif [[ -n "${ROS_DISTRO:-}" && -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
		source "/opt/ros/${ROS_DISTRO}/setup.bash"
	else
		local ros_setup
		for ros_setup in /opt/ros/*/setup.bash; do
			[[ -f "${ros_setup}" ]] && source "${ros_setup}" && break
		done
	fi

	# Release flags follow the upstream -march=native and keep QEMU builds portable.
	colcon build --symlink-install --parallel-workers 4 \
		--paths src/motors src/imu src/inference src/camera \
		--event-handlers console_direct+ \
		--cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
		'-DCMAKE_C_FLAGS_RELEASE=-O3 -DNDEBUG -march=armv8-a' \
		'-DCMAKE_CXX_FLAGS_RELEASE=-O3 -DNDEBUG -march=armv8-a'

	source install/setup.bash
	local package
	for package in roboparty_motors roboparty_imu roboparty_inference; do
		ros2 pkg prefix "${package}"
	done
}

# Build the upstream deployment workspace in the target rootfs.
function post_customize_image__clone_roboparty_deploy() {
	[[ "${BUILD_ROS2}" == "yes" ]] || return 0

	local repo_url="https://github.com/Roboparty/roboparty_deploy"
	local repo_dirname="roboparty_deploy"

	local user_name="robo"
	local user_home="/home/${user_name}"
	local clone_dir="${SDCARD}${user_home}/${repo_dirname}"

	# Route GitHub through GITHUB_SOURCE (REGIONAL_MIRROR=china sets ghproxy).
	local deploy_url="${repo_url}"
	local -a git_env=()
	if [[ "${GITHUB_MIRROR:-}" == "ghproxy" && -n "${GITHUB_SOURCE:-}" ]]; then
		deploy_url="${GITHUB_SOURCE}/${repo_url#https://github.com/}"
		local mirror_cfg="${WORKDIR}/git-mirror-${repo_dirname}.gitconfig"
		cp -f "${HOME}/.gitconfig" "${mirror_cfg}" 2>/dev/null || :
		git config --file "${mirror_cfg}" url."${GITHUB_SOURCE}/".insteadOf "https://github.com/"
		git_env=("GIT_CONFIG_GLOBAL=${mirror_cfg}")
	fi

	local cache_deploy="${SRC}/cache/sources/roboparty_deploy"
	local source_dir=""

	if [[ -d "${cache_deploy}/src" ]]; then
		source_dir="${cache_deploy}"
	else
		source_dir="${cache_deploy}"
		install -d -m 0755 "$(dirname "${source_dir}")"
		rm -rf "${source_dir}"
		display_alert "RoboParty deploy" "cloning ${deploy_url} -> cache ${source_dir}" "info"
		local clone_ok="no" attempt
		for attempt in 1 2 3; do
			if run_host_command_logged "${git_env[@]}" git clone --depth=1 "${deploy_url}" "${source_dir}"; then
				clone_ok="yes"
				break
			fi
			rm -rf "${source_dir}"
			sleep 5
		done
		[[ "${clone_ok}" == "yes" ]] || exit_with_error "RoboParty deploy" "clone failed: ${deploy_url}"

		# Submodule updates re-read the global config, so pass the mirror config explicitly.
		run_host_command_logged "${git_env[@]}" git -C "${source_dir}" submodule update --init --recursive --remote --depth=1 --jobs=4
	fi

	if [[ "${ROBOPARTY_DEPLOY_UPDATE:-no}" == "yes" && "${source_dir}" == "${cache_deploy}" ]]; then
		display_alert "RoboParty deploy" "updating cached snapshot ${source_dir}" "info"
		run_host_command_logged "${git_env[@]}" git -C "${source_dir}" fetch --depth=1 origin
		run_host_command_logged "${git_env[@]}" git -C "${source_dir}" reset --hard FETCH_HEAD
		run_host_command_logged "${git_env[@]}" git -C "${source_dir}" submodule update --init --recursive --remote --depth=1 --jobs=4
	fi

	display_alert "RoboParty deploy" "using ${source_dir} -> ${user_home}/${repo_dirname}" "info"
	install -d -m 0755 "${clone_dir}"
	rsync -a --delete-excluded --exclude='.git' --exclude='/build' --exclude='/install' --exclude='/log' \
		"${source_dir}/" "${clone_dir}/"
	chroot_sdcard chown -R "${user_name}:${user_name}" "${user_home}/${repo_dirname}"

	local ros_setup_found="no" ros_setup_path
	for ros_setup_path in "${SDCARD}"/opt/ros/*/setup.bash; do
		[[ -f "${ros_setup_path}" ]] && { ros_setup_found="yes"; break; }
	done
	[[ "${ros_setup_found}" == "yes" ]] || exit_with_error "RoboParty deploy requires ROS 2"
	{
		printf '#!/usr/bin/env bash\n'
		declare -f roboparty_build_deploy
		printf '\nroboparty_build_deploy\n'
	} > "${SDCARD}/tmp/roboparty-build-deploy.sh"
	chmod 0755 "${SDCARD}/tmp/roboparty-build-deploy.sh"
	display_alert "RoboParty deploy" "building ARM64 workspace inside rootfs" "info"
	chroot_sdcard runuser -u "${user_name}" -- env \
		-u ROS_DISTRO -u ROS_SETUP -u AMENT_PREFIX_PATH -u CMAKE_PREFIX_PATH \
		-u COLCON_PREFIX_PATH -u ROS_PACKAGE_PATH \
		BUILD_ROS2="${BUILD_ROS2}" HOME="${user_home}" CCACHE_DISABLE=1 \
		CMAKE_BUILD_PARALLEL_LEVEL=8 MAKEFLAGS=-j8 /tmp/roboparty-build-deploy.sh
	rm -f "${SDCARD}/tmp/roboparty-build-deploy.sh"
}
