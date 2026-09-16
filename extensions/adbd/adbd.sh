#!/usr/bin/env bash

function post_customize_image__install_adbd() {
	[[ "${BOARD}" == "robopi2" ]] || return 0

	local files_dir="${SRC}/extensions/adbd/files"
	install -Dm755 "${files_dir}/usr/bin/adbd" "${SDCARD}/usr/bin/adbd"
	install -Dm755 "${files_dir}/usr/bin/usbdevice" "${SDCARD}/usr/bin/usbdevice"
	install -Dm644 "${files_dir}/usr/lib/systemd/system/usbdevice.service" "${SDCARD}/usr/lib/systemd/system/usbdevice.service"
	install -Dm644 "${files_dir}/etc/profile.d/usbdevice.sh" "${SDCARD}/etc/profile.d/usbdevice.sh"
	install -Dm644 "${files_dir}/etc/modules-load.d/usb-gadget.conf" "${SDCARD}/etc/modules-load.d/usb-gadget.conf"
	chroot_sdcard systemctl enable usbdevice.service
}
