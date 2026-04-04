SUMMARY = "Beagley production cluster application"
LICENSE = "CLOSED"

inherit cmake pkgconfig qt6-cmake systemd

BEAGLEY_CLUSTER_REPO_ROOT ?= "${@os.path.abspath(os.path.join(d.getVar('THISDIR'), '../../../..'))}"
BEAGLEY_CLUSTER_GIT_URL ?= "git://${BEAGLEY_CLUSTER_REPO_ROOT};protocol=file"
BEAGLEY_CLUSTER_GIT_BRANCH ?= "main"

SRC_URI = " \
    ${BEAGLEY_CLUSTER_GIT_URL};branch=${BEAGLEY_CLUSTER_GIT_BRANCH} \
    file://beagley-cluster.service \
    file://beagley-cluster-gpu-probe.service \
    file://beagley-cluster-provision.service \
    file://05-beagley-eth-debug.network \
    file://55-beagley-usb-recovery.network \
    file://12-en.network \
    file://journald-persistent.conf \
    file://beagley-cluster-journal.conf \
    file://beagley-cluster-launch.sh \
    file://beagley-cluster-gpu-probe.sh \
    file://beagley-gpu-gate.sh \
    file://beagley-cluster-provision.sh \
    file://beagley-cluster.default \
"
SRCREV = "${AUTOREV}"
S = "${WORKDIR}/git"

DEPENDS += " \
    qtbase \
    qtdeclarative \
    qtdeclarative-native \
    qtsvg \
    qtwebsockets \
"

RDEPENDS:${PN} += " \
    qtbase \
    qtdeclarative \
    qtbase-plugins \
    qtdeclarative-qmlplugins \
    qtsvg \
    qtwebsockets \
"

EXTRA_OECMAKE += " \
    -DBEAGLEY_APPLIANCE_PRODUCTION=ON \
    -DWITH_WEBENGINE=OFF \
    -DCMAKE_BUILD_TYPE=Release \
"

SYSTEMD_SERVICE:${PN} = "beagley-cluster.service"
SYSTEMD_SERVICE:${PN} += " beagley-cluster-gpu-probe.service"
SYSTEMD_SERVICE:${PN} += " beagley-cluster-provision.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install:append() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/beagley-cluster.service ${D}${systemd_system_unitdir}/beagley-cluster.service
    install -m 0644 ${WORKDIR}/beagley-cluster-gpu-probe.service ${D}${systemd_system_unitdir}/beagley-cluster-gpu-probe.service
    install -m 0644 ${WORKDIR}/beagley-cluster-provision.service ${D}${systemd_system_unitdir}/beagley-cluster-provision.service

    install -d ${D}${bindir}
    if [ ! -x ${D}${bindir}/beagley_cluster ]; then
        test -x ${B}/beagley_cluster || bbfatal "expected ${B}/beagley_cluster after build, but it was not produced"
        install -m 0755 ${B}/beagley_cluster ${D}${bindir}/beagley_cluster
    fi
    test -x ${D}${bindir}/beagley_cluster || bbfatal "expected ${D}${bindir}/beagley_cluster from the recipe install step, but it was not installed"
    install -m 0755 ${WORKDIR}/beagley-cluster-launch.sh ${D}${bindir}/beagley-cluster-launch.sh
    install -m 0755 ${WORKDIR}/beagley-gpu-gate.sh ${D}${bindir}/beagley-gpu-gate

    install -d ${D}${libexecdir}/beagley-cluster
    install -m 0755 ${WORKDIR}/beagley-cluster-gpu-probe.sh ${D}${libexecdir}/beagley-cluster/beagley-cluster-gpu-probe.sh
    install -m 0755 ${WORKDIR}/beagley-cluster-provision.sh ${D}${libexecdir}/beagley-cluster/beagley-cluster-provision.sh

    install -d ${D}${sysconfdir}/default
    install -m 0644 ${WORKDIR}/beagley-cluster.default ${D}${sysconfdir}/default/beagley-cluster

    install -d ${D}${sysconfdir}/systemd/network
    install -m 0644 ${WORKDIR}/05-beagley-eth-debug.network ${D}${sysconfdir}/systemd/network/05-beagley-eth-debug.network
    install -m 0644 ${WORKDIR}/55-beagley-usb-recovery.network ${D}${sysconfdir}/systemd/network/55-beagley-usb-recovery.network
    install -m 0644 ${WORKDIR}/12-en.network ${D}${sysconfdir}/systemd/network/12-en.network

    install -d ${D}${sysconfdir}/systemd/journald.conf.d
    install -m 0644 ${WORKDIR}/journald-persistent.conf ${D}${sysconfdir}/systemd/journald.conf.d/persistent.conf

    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${WORKDIR}/beagley-cluster-journal.conf ${D}${nonarch_libdir}/tmpfiles.d/beagley-cluster-journal.conf
}

FILES:${PN} += " \
    ${systemd_system_unitdir}/beagley-cluster.service \
    ${systemd_system_unitdir}/beagley-cluster-gpu-probe.service \
    ${systemd_system_unitdir}/beagley-cluster-provision.service \
    ${bindir}/beagley-cluster-launch.sh \
    ${bindir}/beagley-gpu-gate \
    ${libexecdir}/beagley-cluster/beagley-cluster-gpu-probe.sh \
    ${libexecdir}/beagley-cluster/beagley-cluster-provision.sh \
    ${sysconfdir}/default/beagley-cluster \
    ${sysconfdir}/systemd/network/05-beagley-eth-debug.network \
    ${sysconfdir}/systemd/network/55-beagley-usb-recovery.network \
    ${sysconfdir}/systemd/network/12-en.network \
    ${sysconfdir}/systemd/journald.conf.d/persistent.conf \
    ${nonarch_libdir}/tmpfiles.d/beagley-cluster-journal.conf \
"
