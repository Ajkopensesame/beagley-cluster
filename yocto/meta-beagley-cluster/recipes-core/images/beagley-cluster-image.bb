SUMMARY = "Beagley cluster appliance image"
LICENSE = "MIT"

require recipes-core/images/core-image-base.bb

# Keep the BeagleY image EFI-bootable so the board remains discoverable over
# SSH even while we iterate on the board-specific DT handoff.
WKS_FILE:beagley-ai = "beagley-cluster-beagley-ai.wks"

IMAGE_BOOT_FILES:append:beagley-ai = " \
    Image \
    k3-am67a-beagley-ai.dtb;dtb/ti/k3-am67a-beagley-ai.dtb \
"

TI_WKS_BOOTLOADER_APPEND:beagley-ai = "rw net.ifnames=0 quiet earlycon=ns16550a,mmio32,0x02800000 console=ttyS2,115200n8"

IMAGE_FEATURES += "ssh-server-openssh"

IMAGE_INSTALL:append = " \
    packagegroup-beagley-cluster \
    beagley-cluster \
"
