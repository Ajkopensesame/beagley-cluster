FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}/${MACHINE}:"

do_install:append:beagley-ai() {
    install -m 0644 ${WORKDIR}/uEnv-sk.txt ${D}/board-support/prebuilt-images/uEnv.txt
}

do_deploy:append:beagley-ai() {
    install -d ${DEPLOYDIR}
    install -m 0644 ${WORKDIR}/uEnv-sk.txt ${DEPLOYDIR}/uEnv.txt
}
