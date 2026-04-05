# meta-beagley-cluster

Yocto layer for the Beagley cluster appliance image.

This layer assumes it is added on top of a TI Processor SDK Linux 11.00
workspace for J722S/AM67A and focuses on:

- the `beagley-cluster` application build
- the staged `eglfs_kms` boot flow with a dedicated GPU probe
- the first-boot provisioning service for boot-media overrides
- the `beagley-cluster-image` appliance image recipe
- the `beagley-cluster-image-diag` boot-diagnostic image recipe

The supported production base is the TI SDK 11.00 Scarthgap flow with the
BeagleY BSP enabled through `MACHINE_POLICY=board-bsp` and `MACHINE=beagley-ai`.
If that BSP is not present in a given SDK checkout, the helper scripts can still
fall back to `j722s-evm`, but that is no longer the preferred appliance target.

For BeagleY images, the boot media is intentionally assembled with both of the
board-specific boot paths that have been useful in diagnosis. The image ships:

- `extlinux/extlinux.conf` with an explicit `ti/k3-am67a-beagley-ai.dtb`
- `EFI/BOOT/bootaa64.efi` and `EFI/BOOT/grub.cfg`
- `uEnv.txt` that also sets `fdtfile=ti/k3-am67a-beagley-ai.dtb` as a fallback
- the BeagleY kernel and DTB directly on the boot partition

That keeps both the U-Boot distro-boot and EFI paths aligned on the BeagleY
device tree instead of falling back to the generic `j722s-evm` tree.

For remote diagnosis, the appliance layer also installs:

- a deterministic wired debug address on the BeagleY CPSW interface at `192.168.0.46/24`
- a deterministic USB recovery address on `usb0` at `192.168.7.2/24` when the gadget interface is present
- persistent systemd journal storage under `/var/log/journal`
- diagnostic stage markers and boot snapshots under `/var/lib/beagley-cluster/diagnostic`
