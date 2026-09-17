# RDK X5 vendor U-Boot boot script for Armbian
echo "Armbian boot script loaded from ${devtype} ${devnum}:${devplist}"

setenv imagefile "Image"
setenv fdtfile "hobot/x5-rdk-v1p0.dtb"
setenv uart_baudrate "115200"
# The vendor environment does not define ramdisk_addr_r. Keep the initramfs
# above the RDK multimedia carveouts (ending at 0xd4100000) and below 4 GiB.
setenv ramdisk_addr_r "0xd8000000"

if test "${hb_board_id}" = "0x0201"; then setenv fdtfile "hobot/x5-evb-lp4-1_a.dtb"; fi
if test "${hb_board_id}" = "0x0202"; then setenv fdtfile "hobot/x5-evb-lp4-1_b.dtb"; fi
if test "${hb_board_id}" = "0x0203"; then setenv fdtfile "hobot/x5-evb-lp4-v1p2.dtb"; fi
if test "${hb_board_id}" = "0x0204"; then setenv fdtfile "hobot/x5-evb-lp4-v1p3.dtb"; fi
if test "${hb_board_id}" = "0x0301"; then setenv fdtfile "hobot/x5-rdk.dtb"; fi
if test "${hb_board_id}" = "0x0302"; then setenv fdtfile "hobot/x5-rdk-v1p0.dtb"; fi
if test "${hb_board_id}" = "0x0501"; then setenv fdtfile "hobot/x5-md-v0p1.dtb"; fi
if test "${hb_board_id}" = "0x0502"; then setenv fdtfile "hobot/x5-md-v0p2.dtb"; setenv uart_baudrate "921600"; fi
if test "${hb_board_id}" = "0x0503"; then setenv fdtfile "hobot/x5-md-v0p2.dtb"; setenv uart_baudrate "921600"; fi
if test "${hb_board_id}" = "0x0504"; then setenv fdtfile "hobot/x5-md-v0p2.dtb"; setenv uart_baudrate "921600"; fi
if test "${hb_board_id}" = "0x0505"; then setenv fdtfile "hobot/x5-md-v0p2.dtb"; setenv uart_baudrate "921600"; fi
if test "${hb_board_id}" = "0x0506"; then setenv fdtfile "hobot/x5-md-v1p2.dtb"; setenv uart_baudrate "921600"; fi

setenv rootdev "LABEL=rootfs"
setenv verbosity "7"
setenv console "both"
setenv rootfstype "ext4"
setenv docker_optimizations "on"
setenv load_addr "0x85800000"

if test -e ${devtype} ${devnum}:${devplist} ${prefix}armbianEnv.txt; then
	ext4load ${devtype} ${devnum}:${devplist} ${load_addr} ${prefix}armbianEnv.txt
	env import -t ${load_addr} ${filesize}
fi

setenv consoleargs ""
if test "${console}" = "display" || test "${console}" = "both"; then setenv consoleargs "console=tty1"; fi
if test "${console}" = "serial" || test "${console}" = "both"; then setenv consoleargs "console=ttyS0,${uart_baudrate} ${consoleargs}"; fi

setenv flash_partitions "mtdparts=spi7.0:0x700000@0x0(miniboot),0x180000@0x700000(ubootenv)"
setenv bootargs "root=${rootdev} rootwait rootfstype=${rootfstype} rw ${consoleargs} consoleblank=0 loglevel=${verbosity} earlycon=uart8250,mmio32,0x32120000,115200 ${flash_partitions} hobotboot.reason=${reset_reason} ${extraargs} ${extraboardargs}"
if test "${docker_optimizations}" = "on"; then setenv bootargs "${bootargs} cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory"; fi

echo "Loading ${prefix}dtb/${fdtfile}"
ext4load ${devtype} ${devnum}:${devplist} ${fdt_addr_r} ${prefix}dtb/${fdtfile}

if test -e ${devtype} ${devnum}:${devplist} ${prefix}config.txt; then
	dtoverlay ${fdt_addr_r} 0x85000000 ${prefix}config.txt 0x85800000
	setpin ${prefix}config.txt 0x85800000
fi

echo "Loading ${prefix}${imagefile}"
ext4load ${devtype} ${devnum}:${devplist} ${kernel_addr_r} ${prefix}${imagefile}

echo "Loading ${prefix}uInitrd at ${ramdisk_addr_r}"
if ext4load ${devtype} ${devnum}:${devplist} ${ramdisk_addr_r} ${prefix}uInitrd; then
	echo "Loaded initramfs: ${filesize} bytes"
	setenv ramdisk_arg "${ramdisk_addr_r}:${filesize}"
else
	setenv ramdisk_arg "-"
fi

booti ${kernel_addr_r} ${ramdisk_arg} ${fdt_addr_r}

# Recompile with:
# mkimage -C none -A arm -T script -d boot-hobot-x5.cmd boot.scr
