# meta-beagley-cluster

Yocto layer for the Beagley cluster appliance image.

This layer assumes it is added on top of a TI Processor SDK Linux 11.00
workspace for J722S/AM67A and focuses on:

- the `beagley-cluster` application build
- the staged `eglfs_kms` boot flow with a dedicated GPU probe
- the first-boot provisioning service for boot-media overrides
- the `beagley-cluster-image` appliance image recipe

The supported production base is the TI SDK 11.00 Scarthgap flow with the
BeagleY BSP enabled through `MACHINE_POLICY=board-bsp` and `MACHINE=beagley-ai`.
If that BSP is not present in a given SDK checkout, the helper scripts can still
fall back to `j722s-evm`, but that is no longer the preferred appliance target.

For BeagleY production images, the boot media is intentionally assembled on the
non-EFI U-Boot distro-boot path. The image now ships:

- `extlinux/extlinux.conf` with an explicit `ti/k3-am67a-beagley-ai.dtb`
- `uEnv.txt` that also sets `fdtfile=ti/k3-am67a-beagley-ai.dtb` as a fallback
- the BeagleY kernel and DTB directly on the boot partition

That avoids the generic EFI/GRUB flow selecting the default `j722s-evm` tree
at runtime.

For remote diagnosis, the appliance layer also installs:

- a deterministic wired debug address on the BeagleY CPSW interface at `192.168.0.46/24`
- a deterministic USB recovery address on `usb0` at `192.168.7.2/24` when the gadget interface is present
- persistent systemd journal storage under `/var/log/journal`
