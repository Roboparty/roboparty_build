# D-Robotics RDK X5 (Sunrise 5) development board
BOARD_NAME="RDK X5"
BOARD_VENDOR="d-robotics"
BOARDFAMILY="hobot-x5"
BOARD_MAINTAINER="wentywenty"
INTRODUCED="2026"

# RDK X5 boots from the vendor Miniboot/U-Boot stored in on-board SPI flash.
# The removable image starts at 4 MiB and intentionally contains no bootloader.
BOOTCONFIG="none"
BOOT_FDT_FILE="hobot/x5-rdk-v1p0.dtb"
SERIALCON="ttyS0:115200"

KERNEL_TARGET="vendor,vendor-rt"
KERNEL_TEST_TARGET="vendor"

# Keep this experimental port on the userspace release supported by the
# D-Robotics binary multimedia and BPU packages.
BOARD_MINIMAL_ONLY="no"
KERNEL_HAS_WORKING_HEADERS="yes"
