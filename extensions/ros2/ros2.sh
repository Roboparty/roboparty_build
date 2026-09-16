# ROS 2 rootfs-cache integration from a locally cached ros2-apt-source package.

function ros2_get_distro() {
	echo "jazzy"
}

function ros2_get_apt_source_deb() {
	echo "${SRC}/extensions/ros2/ros2-apt-source_1.3.0.noble_all.deb"
}

function ros2_get_packages() {
	local ros_distro
	ros_distro="$(ros2_get_distro)"

	echo \
		"ros-${ros_distro}-desktop" \
		"ros-${ros_distro}-realsense2-camera" \
		ros-dev-tools \
		python3-colcon-common-extensions \
		ccache \
		libfmt-dev \
		libspdlog-dev \
		libeigen3-dev \
		whiptail \
		parted \
		psmisc \
		bsdextrautils \
		iproute2 \
		ethtool \
		tcpdump \
		net-tools \
		iw \
		wireless-tools \
		joystick \
		can-utils \
		i2c-tools \
		spi-tools \
		usbutils \
		sysstat \
		python3-usb \
		python3-crcmod \
		python3-hid \
		gpiod \
		adb \
		vim \
		dos2unix \
		tshark \
		zip
}

function extension_prepare_config__100_ros2_rootfs_packages() {
	[[ "${BUILD_ROS2}" == "yes" ]] || return 0

	local local_deb
	local_deb="$(ros2_get_apt_source_deb)"
	[[ -f "${local_deb}" ]] || { display_alert "ROS 2" "Missing ${local_deb}" "err"; return 1; }

	add_packages_to_rootfs gnupg2 lsb-release ca-certificates
	add_packages_to_rootfs $(ros2_get_packages)

	declare -g EXTRA_ROOTFS_NAME="${EXTRA_ROOTFS_NAME:-}-ros2-$(ros2_get_distro)"
}

function custom_apt_repo__100_ros2_apt_source() {
	[[ "${BUILD_ROS2}" == "yes" ]] || return 0
	[[ "${CUSTOM_REPO_WHEN}" == "root" || "${CUSTOM_REPO_WHEN}" == "rootfs" ]] || return 0

	local local_deb
	local local_deb_name="ros2-apt-source.deb"
	local_deb="$(ros2_get_apt_source_deb)"
	[[ -f "${local_deb}" ]] || { display_alert "ROS 2" "Missing ${local_deb}" "err"; return 1; }

	display_alert "Adding ROS 2 apt source" "$(ros2_get_distro)" "info"
	cp -f "${local_deb}" "${SDCARD}/tmp/${local_deb_name}"
	chroot "${SDCARD}" dpkg -i "/tmp/${local_deb_name}"
	rm -f "${SDCARD}/tmp/${local_deb_name}"
}

function post_customize_image__100_configure_ros2_shell() {
	[[ "${BUILD_ROS2}" == "yes" ]] || return 0

	local setup_line="source /opt/ros/$(ros2_get_distro)/setup.bash"
	for rc in "${SDCARD}/root/.bashrc" "${SDCARD}/etc/skel/.bashrc"; do
		grep -qxF "${setup_line}" "${rc}" 2>/dev/null || echo "${setup_line}" >> "${rc}"
	done

	chroot "${SDCARD}" apt-get remove -y brltty || true
}
