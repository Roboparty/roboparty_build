# D-Robotics RDK X3 (Sunrise 3) development board
BOARD_NAME="RDK X3"
BOARD_VENDOR="d-robotics"
BOARDFAMILY="hobot-x3"
BOARD_MAINTAINER="wentywenty"
INTRODUCED="2026"

# RDK X3 boots from the vendor Miniboot stored in on-board NAND/SPI flash.
# The removable image starts at 4 MiB and intentionally contains no bootloader.
BOOTCONFIG="none"
BOOT_FDT_FILE="hobot/hobot-x3-sdb.dtb"
SERIALCON="ttyS0:921600"

KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"

# Keep this experimental port on the userspace release supported by the
# D-Robotics binary multimedia and BPU packages.
BOARD_MINIMAL_ONLY="no"
KERNEL_HAS_WORKING_HEADERS="yes"
