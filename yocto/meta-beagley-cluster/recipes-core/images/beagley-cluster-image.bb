SUMMARY = "Beagley cluster appliance image"
LICENSE = "MIT"

require recipes-core/images/core-image-base.bb

# Keep the BeagleY image dual-bootable so recovery images can expose both the
# board-specific extlinux flow and the EFI path without changing the rootfs.
WKS_FILE:beagley-ai = "beagley-cluster-beagley-ai.wks.in"
WKS_FILE_DEPENDS:append:beagley-ai = " grub-efi"

IMAGE_BOOT_FILES:append:beagley-ai = " \
    Image \
    k3-am67a-beagley-ai.dtb;dtb/ti/k3-am67a-beagley-ai.dtb \
    extlinux.conf;extlinux/extlinux.conf \
"

BEAGLEY_BOOT_KERNEL_ARGS:beagley-ai = "rw net.ifnames=0 quiet earlycon=ns16550a,mmio32,0x02800000 console=ttyS2,115200n8"
TI_WKS_BOOTLOADER_APPEND:beagley-ai = "${BEAGLEY_BOOT_KERNEL_ARGS}"

IMAGE_FEATURES += "ssh-server-openssh"

IMAGE_INSTALL:append = " \
    packagegroup-beagley-cluster \
    beagley-cluster \
"

ROOTFS_POSTPROCESS_COMMAND += "beagley_fix_rootfs_top_level_ownership; "

beagley_fix_rootfs_top_level_ownership() {
    # systemd-tmpfiles refuses to operate when a path transition starts at a
    # non-root-owned /. That leaves /var/volatile/tmp missing, which prevents
    # systemd-resolved and systemd-timesyncd from starting on cold boot.
    chown root:root "${IMAGE_ROOTFS}" "${IMAGE_ROOTFS}/usr"
    chmod 0755 "${IMAGE_ROOTFS}" "${IMAGE_ROOTFS}/usr"
}

# BeagleY's companion R5 boot artifacts currently land in the generic J722S
# deploy directory. Stage them into the BeagleY deploy directory before WIC
# assembles the image so clean workspaces still produce a flashable SD image.
do_stage_beagley_bootloader_aliases() {
    if [ "${MACHINE}" != "beagley-ai" ]; then
        exit 0
    fi

    local dest_dir="${DEPLOY_DIR_IMAGE}"
    local fallback_dir="${TI_COMMON_DEPLOY}/images/j722s-evm"
    local found=0

    install -d "${dest_dir}"

    if ls "${dest_dir}"/tiboot3*.bin >/dev/null 2>&1; then
        bbnote "BeagleY tiboot3 artifacts already present in ${dest_dir}"
        exit 0
    fi

    if [ ! -d "${fallback_dir}" ]; then
        bbfatal "BeagleY tiboot3 fallback directory missing: ${fallback_dir}"
    fi

    for src in "${fallback_dir}"/tiboot3*.bin; do
        if [ -f "${src}" ]; then
            install -m 0644 "${src}" "${dest_dir}/$(basename "${src}")"
            found=1
        fi
    done

    if [ "${found}" -ne 1 ]; then
        bbfatal "No tiboot3*.bin artifacts found in ${fallback_dir}"
    fi

    bbnote "Staged BeagleY tiboot3 artifacts from ${fallback_dir} into ${dest_dir}"
}

# The grub-efi recipe keeps the AArch64 EFI loader in its recipe-local deploy
# directory. Stage it into DEPLOY_DIR_IMAGE so bootimg-efi can install
# EFI/BOOT/bootaa64.efi onto the final BeagleY SD image.
do_stage_beagley_efi_loader() {
    if [ "${MACHINE}" != "beagley-ai" ]; then
        exit 0
    fi

    local dest_path="${DEPLOY_DIR_IMAGE}/grub-efi-bootaa64.efi"
    local src_path

    if [ -f "${dest_path}" ]; then
        bbnote "BeagleY EFI loader already present in ${DEPLOY_DIR_IMAGE}"
        exit 0
    fi

    src_path="$(find "${TMPDIR}/work" -path '*/grub-efi/*/deploy-grub-efi/grub-efi-bootaa64.efi' -print -quit)"
    if [ -z "${src_path}" ] || [ ! -f "${src_path}" ]; then
        bbfatal "Unable to locate grub-efi-bootaa64.efi under ${TMPDIR}/work"
    fi

    install -d "${DEPLOY_DIR_IMAGE}"
    install -m 0644 "${src_path}" "${dest_path}"
    bbnote "Staged BeagleY EFI loader from ${src_path} into ${dest_path}"
}

do_stage_beagley_bootloader_aliases[depends] += "virtual/bootloader:do_deploy"
do_image_wic[depends] += " grub-efi:do_deploy"
addtask do_stage_beagley_bootloader_aliases after do_image before do_image_wic
do_stage_beagley_efi_loader[depends] += "grub-efi:do_deploy"
addtask do_stage_beagley_efi_loader after do_image before do_image_wic

# On the BeagleY image, WIC's explicit sibling workdir intermittently loses the
# generated ext4 rootfs artifact before fsck runs. Let WIC create its own
# internal temp workdir under build-wic so the artifact lifecycle stays inside
# one directory tree.
IMAGE_CMD:wic:beagley-ai () {
    out="${IMGDEPLOYDIR}/${IMAGE_NAME}"
    build_wic="${WORKDIR}/build-wic"
    wks="${WKS_FULL_PATH}"

    if [ -e "$build_wic" ]; then
        rm -rf "$build_wic"
    fi
    install -d "$build_wic"

    if [ -z "$wks" ]; then
        bbfatal "No kickstart files from WKS_FILES were found: ${WKS_FILES}. Please set WKS_FILE or WKS_FILES appropriately."
    fi

    BUILDDIR="${TOPDIR}" PSEUDO_UNLOAD=1 wic create "$wks" --vars "${STAGING_DIR}/${MACHINE}/imgdata/" -e "${IMAGE_BASENAME}" -o "$build_wic/" ${WIC_CREATE_EXTRA_ARGS}

    IMAGER=direct
    eval set -- "${WIC_CREATE_EXTRA_ARGS} --"
    while [ 1 ]; do
        case "$1" in
            --imager|-i)
                shift
                IMAGER=$1
                ;;
            --)
                shift
                break
                ;;
        esac
        shift
    done
    mv "$build_wic/$(basename "${wks%.wks}")"*.${IMAGER} "$out.wic"
}
