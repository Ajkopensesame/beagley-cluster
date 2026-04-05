# BeagleY appliance images must boot via U-Boot distro boot with an explicit
# board DTB so they do not fall through the generic EFI path and pick the
# J722S EVM tree.
UBOOT_EXTLINUX:beagley-ai = "1"
UBOOT_EXTLINUX_CONSOLE:beagley-ai = "console=ttyS2,115200n8"
UBOOT_EXTLINUX_ROOT:beagley-ai = "root=LABEL=root"
UBOOT_EXTLINUX_KERNEL_ARGS:beagley-ai = "rootfstype=ext4 rootwait rw net.ifnames=0 quiet earlycon=ns16550a,mmio32,0x02800000"
UBOOT_EXTLINUX_KERNEL_IMAGE:beagley-ai = "/Image"
UBOOT_EXTLINUX_FDT:beagley-ai = "/dtb/ti/k3-am67a-beagley-ai.dtb"
UBOOT_EXTLINUX_MENU_DESCRIPTION:linux:beagley-ai = "Beagley Cluster"
