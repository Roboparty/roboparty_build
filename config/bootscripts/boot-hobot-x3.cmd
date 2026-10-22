# RDK X3 vendor U-Boot boot script for Armbian
echo "Armbian boot script loaded from ${devtype} ${devnum}:${devplist}"

setenv imagefile "Image"
setenv uart_baudrate "921600"

setenv rootdev "LABEL=rootfs"
setenv verbosity "7"
setenv console "both"
setenv rootfstype "ext4"
setenv docker_optimizations "on"
# X3 U-Boot keeps its script scratch at scriptaddr (0x3C10000).
setenv load_addr "0x3C10000"

if test -e ${devtype} ${devnum}:${devplist} ${prefix}armbianEnv.txt; then
	ext4load ${devtype} ${devnum}:${devplist} ${load_addr} ${prefix}armbianEnv.txt
	env import -t ${load_addr} ${filesize}
fi

# The vendor U-Boot derives fdtfile from the SoM type (e.g. hobot-x3-sdb.dtb).
# Armbian installs DTBs below /boot/dtb/hobot/, so the value carried in
# armbianEnv.txt is prefixed with the hobot/ sub-directory. Only fall back to
# the RDK X3 SDB DTB when nothing was provided at all.
if test -z "${fdtfile}"; then setenv fdtfile "hobot/hobot-x3-sdb.dtb"; fi

setenv consoleargs ""
if test "${console}" = "display" || test "${console}" = "both"; then setenv consoleargs "console=tty1"; fi
if test "${console}" = "serial" || test "${console}" = "both"; then setenv consoleargs "console=ttyS0,${uart_baudrate} ${consoleargs}"; fi

# The X3 SoM boots the OS from NAND/SPI miniboot; keep the vendor NAND layout
# in the command line so the in-kernel mtdparts match the flashed miniboot.
setenv flash_partitions "ubi.mtd=2,2048 mtdparts=hr_nand.0:6291456@0x0(miniboot),2097152@0x600000(env)"
setenv bootargs "root=${rootdev} rootwait rootfstype=${rootfstype} rw ${consoleargs} consoleblank=0 loglevel=${verbosity} video=hobot:x3sdb-hdmi ${flash_partitions} hobotboot.reason=${reset_reason} ${extraargs} ${extraboardargs}"
if test "${docker_optimizations}" = "on"; then setenv bootargs "${bootargs} cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory"; fi

echo "Loading ${prefix}dtb/${fdtfile}"
ext4load ${devtype} ${devnum}:${devplist} ${fdt_addr_r} ${prefix}dtb/${fdtfile}

if test -e ${devtype} ${devnum}:${devplist} ${prefix}config.txt; then
	dtoverlay ${fdt_addr_r} 0x3D00000 ${prefix}config.txt 0x3E00000
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
# mkimage -C none -A arm -T script -d boot-hobot-x3.cmd boot.scr
