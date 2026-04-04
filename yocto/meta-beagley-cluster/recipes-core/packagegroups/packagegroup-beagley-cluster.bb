SUMMARY = "Runtime dependencies for the Beagley cluster appliance"
LICENSE = "MIT"
inherit packagegroup

RDEPENDS:${PN} = " \
    bash \
    curl \
    ethtool \
    iproute2 \
    kmod \
    kmscube \
    procps \
    rsync \
    util-linux \
"
