# The TI multiconfig bootloader path pulls in rust-native for the k3r5 baremetal
# side build. On the low-memory Docker VM we use for appliance builds, the
# default bootstrap settings have repeatedly crashed inside stage0 rustc.
# Tighten those settings right before install so the native bootstrap is more
# conservative without changing the upstream Python do_configure task type.

do_install:prepend:class-native() {
    if [ -f "${B}/config.toml" ]; then
        sed -i '/^\[build\]$/a extended = false' "${B}/config.toml"
        sed -i '/^\[rust\]$/a incremental = false\ndebuginfo-level = 0\ndebuginfo-level-rustc = 0\ndebuginfo-level-std = 0\ndebuginfo-level-tools = 0\ncodegen-units = 1\ncodegen-units-std = 1' "${B}/config.toml"
    fi
}
