# OpenWrt Passwall2 Auto Configuration with optional Iran specific fixes

Automated configuration script for setting up Passwall2 on the Xiaomi AX3000T and similar OpenWrt devices. 
It supports both newer v25 releases (`apk`) and older releases (`opkg`), resolving dependencies and configuring everything.

Minimum hardware profile:
- Flash `128MB`
- RAM `256MB`

## Installation

Run via SSH:

```bash
rm -f /tmp/set.sh && wget -O /tmp/set.sh https://raw.githubusercontent.com/sadraimam/ax3000t/refs/heads/main/set.sh && chmod +x /tmp/set.sh && sh /tmp/set.sh
```

### Script Options (Flags)

The script accepts several optional arguments so you can customize the installation:

- `-g, --github [VER]` : Install from GitHub releases instead of SourceForge feeds. Optionally specify a version (e.g., `v2.0.1`).
- `-c, --clean` : Perform a clean install (removes existing Passwall packages first).
- `-l, --only-luci` : Install only the LuCI interface (skip binaries). Used with GitHub mode only.
- `-rw, --root-wifi` : Interactive setup to configure a new Root password and WiFi password.
- `-i, --iran` : Apply Iran-specific configurations (Timezone, Passwall banner patch, custom DNS, and DNS Rebind fixes).
- `-h, --help` : Show help message.

**Examples:**
```bash
# Install latest from SourceForge feed with root/wifi setup and Iran configs
sh /tmp/set.sh -rw -i

# Clean install latest from GitHub releases
sh /tmp/set.sh -g -c
```

## Features
- **Package Manager Agnostic:** Automatically uses `apk` or `opkg` depending on your OpenWrt version.
- **Dual Source Installation:** Install from either the official SourceForge feeds or directly from GitHub releases.
- **Dependency Management:** Automatically installs required kernels (`kmod-nft-tproxy`, etc.), swaps `dnsmasq` for `dnsmasq-full`, and ensures DNS resolves correctly during the swap.
- **Interactive Configuration:** Set secure defaults for your WiFi and root password (`-rw`).
- **Region Specific Fixes:** Dedicated Iran configuration flag (`-i`) to set `Asia/Tehran` timezone, add regional DNS, and fix DNS rebinding for local carrier portals (Irancell, MCI, TCI).

## Prerequisites
- OpenWrt installed
- Root access to the router
- Working internet connection

## Default Settings
- Default root & wifi password: `123456789` (You will be prompted to change this if using `-rw`)
- Timezone: `UTC` (Changes to `Asia/Tehran` if using `-i`)
- DNS: Google DNS (`8.8.8.8`, `8.8.4.4`, `1.1.1.1`, `1.0.0.1`, etc.)

## Note on Storage
On the Xiaomi AX3000T, factory partitioning results in an overlay size of approximately 60 MB, compared to around 90-100 MB available on similar routers. The script is optimized to work with this limited storage space although its recommended to flash the router with a UBoot layout (e.g., OpenWrt V25 AX3200t layout) to gain more free storage space (You should get 85 MB total).
