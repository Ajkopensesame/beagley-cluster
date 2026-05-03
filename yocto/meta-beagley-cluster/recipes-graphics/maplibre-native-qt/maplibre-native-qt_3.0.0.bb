SUMMARY = "MapLibre Native Qt bindings and Qt Location plugin"
HOMEPAGE = "https://github.com/maplibre/maplibre-native-qt"
LICENSE = "BSD-2-Clause & (LGPL-3.0-only | GPL-2.0-only | GPL-3.0-only) & MIT"
LIC_FILES_CHKSUM = " \
    file://LICENSES/BSD-2-Clause.txt;md5=272be00ca1ae12eceb040a3946c3c2cc \
    file://LICENSES/LGPL-3.0-only.txt;md5=e6a600fd5e1d9cbde2d983680233ad02 \
    file://LICENSES/GPL-2.0-only.txt;md5=b234ee4d69f5fce4486a80fdaf4a4263 \
    file://LICENSES/GPL-3.0-only.txt;md5=d32239bcb673463ab874e80d47fae504 \
    file://LICENSES/MIT.txt;md5=65df4f155f66872edd1b34bed8cdc74e \
"

SRC_URI = " \
    https://github.com/maplibre/maplibre-native-qt/releases/download/v${PV}/maplibre-native-qt_v${PV}_Source.tar.bz2;downloadfilename=maplibre-native-qt_v${PV}_Source.tar.bz2 \
    file://0001-respect-build-testing.patch \
"
SRC_URI[sha256sum] = "9689fb0630adc33a34ea476bdf53a3ef7dc76cb3c95da9de056081f9330a9355"
S = "${WORKDIR}/maplibre-native-qt_v${PV}_Source"

inherit cmake pkgconfig qt6-cmake

DEPENDS += " \
    qtbase \
    qtdeclarative \
    qtdeclarative-native \
    qtlocation \
    qtpositioning \
"

EXTRA_OECMAKE += " \
    -DMLN_WITH_OPENGL=ON \
    -DMLN_QT_WITH_LOCATION=ON \
    -DMLN_QT_WITH_WIDGETS=OFF \
    -DMLN_QT_STATIC=OFF \
    -DMLN_WITH_WERROR=OFF \
    -DBUILD_TESTING=OFF \
    -DCMAKE_BUILD_TYPE=Release \
"

SYSROOT_DIRS:append = " ${prefix}/plugins ${prefix}/qml"

do_install:append() {
    if [ -d ${D}${prefix}/qml/MapLibre ]; then
        install -d ${D}${libdir}/qml
        rm -rf ${D}${libdir}/qml/MapLibre
        cp -a ${D}${prefix}/qml/MapLibre ${D}${libdir}/qml/MapLibre
    fi

    if [ -f ${D}${prefix}/plugins/geoservices/libqtgeoservices_maplibre.so ]; then
        install -d ${D}${libdir}/plugins/geoservices
        cp -a ${D}${prefix}/plugins/geoservices/libqtgeoservices_maplibre.so \
            ${D}${libdir}/plugins/geoservices/libqtgeoservices_maplibre.so
    fi
}

RDEPENDS:${PN} += " \
    qtbase \
    qtbase-plugins \
    qtdeclarative \
    qtdeclarative-qmlplugins \
    qtlocation \
    qtpositioning \
"

FILES:${PN} += " \
    ${libdir}/libQMapLibre*.so.* \
    ${libdir}/plugins/geoservices \
    ${libdir}/qml/MapLibre \
    ${prefix}/plugins/geoservices \
    ${prefix}/qml/MapLibre \
"

FILES:${PN}-dev += " \
    ${includedir}/QMapLibre \
    ${includedir}/QMapLibreLocation \
    ${includedir}/mbgl \
    ${libdir}/cmake/QMapLibre \
    ${libdir}/libQMapLibre*.so \
"
