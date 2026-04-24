SUMMARY = "Runtime dependencies for the Beagley cluster appliance"
LICENSE = "MIT"
inherit packagegroup

RDEPENDS:${PN} = " \
    bash \
    ca-certificates \
    cc33calibrator \
    cc33conf \
    cc33xx-fw \
    cc33xx-target-scripts \
    curl \
    ethtool \
    iproute2 \
    iw \
    kernel-module-cc33xx \
    kernel-module-cc33xx-sdio \
    kmod \
    kmscube \
    procps \
    rsync \
    util-linux \
    wireless-regdb-static \
    wpa-supplicant \
    wpa-supplicant-cli \
    wpa-supplicant-passphrase \
"
