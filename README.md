# 🚀 OpenWrt Passwall2 Auto-Configuration Suite

🌐 **Languages:** [English](README.md) | [فارسی](README_fa.md) | [Русский](README_ru.md) | [简体中文](README_zh.md)

Automated, resilient, and feature-rich setup script for installing and configuring **Passwall2** on OpenWrt routers.

Designed to handle package management variations across OpenWrt versions, automatically resolve kernel and DNS dependencies, provide multi-source release downloads (including an Iranian local mirror), and apply optional region-specific network & system optimizations.

---

## ✨ Key Features

| Feature | Description |
| :--- | :--- |
| ⚡ **Package Manager Agnostic** | Seamlessly supports both modern OpenWrt releases (`apk` in OpenWrt 24.10 / 25+) and legacy releases (`opkg`), handling `.apk` and `.ipk` packages transparently. |
| 🌐 **Triple-Source Engine** | Install from official SourceForge package feeds (default), direct **GitHub Releases** (`-g`), or the **Iranian Local GitHub Mirror** (`-gm`) via `scorpian.ir`. |
| 📦 **Customizable Profiles** | Choose from **Standard** (both Xray & Sing-Box), **Full Feature** (`-f`), **Minimal Xray** (`-x`), **Minimal Sing-Box** (`-s`), or **LuCI UI Only** (`-l`) installation modes to fit your hardware profile. |
| 🛡️ **Resilient Core Fallback & Mirror Support** | Automatically ensures proxy cores (`xray-core`, `sing-box`) are installed even after upstream removed them from release archives. In Iranian mirror mode (`-gm`), cores are fetched directly from dedicated local mirrors (`scorpian.ir/repos/XTLS/Xray-core` and `scorpian.ir/repos/sagernet/sing-box`) at maximum speed without censorship, with fallback to official GitHub releases. |
| 🛠️ **Zero-Downtime Swap** | Safely upgrades `dnsmasq` to `dnsmasq-full` and installs kernel modules (`kmod-nft-tproxy`, `kmod-nft-socket`) while maintaining active internet connectivity via fallback resolvers. |
| 🇮🇷 **Iran Regional Fixes** | Dedicated flag (`-i`) initializes local DNS (`5.200.200.200`) right at network startup to overcome censorship/DNS blockage, sets `Asia/Tehran` timezone, fixes DNS rebinding for carrier portals (*Irancell, MCI, TCI*), and patches the Passwall status banner. |
| 🔑 **Emergency Password Reset** | Re-maps the physical hardware reset button (`-rb`) so a 5-second press clears the root SSH password without wiping your router's configuration. |
| 📶 **Default Passwords Setup** | Quickly provision uniform Wi-Fi (2.4GHz & 5GHz) and root SSH passwords to `123456789` (`-rw`). |

---

## ⚡ Quick Start

Run the automated installer via SSH on your OpenWrt router:

```bash
rm -f /tmp/set.sh && wget -O /tmp/set.sh https://raw.githubusercontent.com/sadraimam/auto_passwall2/refs/heads/main/set.sh && chmod +x /tmp/set.sh && sh /tmp/set.sh
```

---

## 🎛️ Command-Line Reference & Flags

Customize your installation by appending flags to the script invocation:

| Flag | Long Option | Description |
| :--- | :--- | :--- |
| `-g [VER]` | `--github [VER]` | Install directly from GitHub releases instead of SourceForge feeds. Optionally specify a target release tag (e.g. `26.8.17-1`). |
| `-gm [VER]` | `--github-mirror [VER]` | Install from the **Iranian GitHub Mirror** (`scorpian.ir`). Bypasses GitHub rate-limiting, DNS pollution, and ISP throttling in Iran. Alias: `-m`. |
| `-c` | `--clean` | Perform a clean installation. Removes existing Passwall2 packages and runtime binaries before installing to prevent conflicts. |
| `-x` | `--xray` | Minimal install with **xray-core** only (skips sing-box and extra binaries to conserve flash storage). |
| `-s` | `--singbox` | Minimal install with **sing-box** core only (skips xray-core and extra binaries to conserve flash storage). |
| `-f` | `--full` | Full feature installation. Includes all proxy cores and tools: `chinadns-ng`, `hysteria`, `haproxy`, `microsocks`, `naiveproxy`, `xray-core`, `sing-box`, `geoview`, `v2ray-geoip`, `v2ray-geosite`, `tcping`. |
| `-l` | `--only-luci` | Install only the LuCI web interface (`luci-app-passwall2`). Skips downloading binary packages (useful if custom cores are pre-built into firmware). |
| `-i` | `--iran` | Apply Iran region fixes: initializes local `5.200.200.200` DNS at script startup, sets `Asia/Tehran` timezone, fixes carrier DNS rebinding (`my.irancell.ir`, `my.mci.ir`, `login.tci.ir`), and patches Passwall status banner. |
| `-rw` | `--root-wifi` | Set root SSH password and 2.4GHz/5GHz Wi-Fi passwords to `123456789`. |
| `-rb` | `--reset-button` | Reconfigures hardware reset button: 1-second press reboots router; 5-second press clears root password (`passwd -d root`). |
| `-h` | `--help` | Display script usage help and exit. |

---

## 💡 Recommended Installation Recipes

### 1. Recommended Setup for Iran (High Speed & Reliability)
Uses the Iranian GitHub Mirror, clean package installation, root/Wi-Fi password provisioning, and regional fixes:
```bash
sh /tmp/set.sh -gm -c -rw -i
```

### 2. Clean Install from Official GitHub Releases (Dual Cores)
Fetches the latest release binaries directly from GitHub, ensuring both Xray and Sing-box are installed:
```bash
sh /tmp/set.sh -g -c
```

### 3. Minimal Xray-Only Install (Maximum Storage Savings)
Installs only `xray-core` and essential geo-databases, leaving maximum free storage on your overlay partition:
```bash
sh /tmp/set.sh -x -c
```

### 4. Minimal Sing-Box Install
Installs only `sing-box` core and required geo-databases:
```bash
sh /tmp/set.sh -s -c
```

### 5. Pinning a Specific Release Version
Install a specific release version (e.g., `26.8.17-1`) via the Iranian Mirror:
```bash
sh /tmp/set.sh -gm 26.8.17-1 -c
```

### 6. Full Feature Stack Installation
Installs every supported proxy protocol core (Hysteria, NaiveProxy, HAProxy, ChinaDNS-NG, etc.):
```bash
sh /tmp/set.sh -f -c
```

---

## 📋 System Requirements

- **Supported OS:** OpenWrt (Official release builds; Snapshot builds are unsupported).
- **Architecture:** `x86_64`, `aarch64_cortex-a53`, `aarch64_cortex-a72`, `aarch64_generic`, `arm_cortex-a7`, `arm_cortex-a15`, `mipsel_24kc`, `mips_24kc`, etc.
- **Minimum Hardware Profile:**
  - **Flash:** 128 MB (60 MB+ available overlay storage)
  - **RAM:** 256 MB

> [!NOTE]
> **Xiaomi AX3000T & Storage-Constrained Devices:**
> Stock partitioning on the Xiaomi AX3000T results in an overlay size of ~60 MB. This script is optimized to run efficiently within this space. For best results, consider using minimal sing-box mode (`-s`) or flashing a custom UBoot layout to gain ~85 MB of overlay storage.

---

## 🛠️ Recovery & Safety Features

- **Configuration Backup:** Existing Passwall configurations in `/etc/config/passwall2*` are automatically backed up with a timestamped `.bak` suffix prior to changes.
- **Emergency Hardware Reset (`-rb`):** If locked out of SSH, holding your router's physical reset button for 5 seconds clears the root password without wiping network configs or installed packages.
- **Space Check & Cleanup Advice:** The script verifies `/tmp` space before downloading packages and offers disk cleanup hints if storage limits are reached.

---

## 📄 License & Attribution

- **Script Maintainer:** [sadraimam](https://github.com/sadraimam)
- **Passwall2 Upstream Project:** [Openwrt-Passwall/openwrt-passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2)
- **Iranian Mirror Provider:** [scorpian.ir](https://scorpian.ir/repos/Openwrt-Passwall/openwrt-passwall2)
- **Thanks to:** [enxy0](https://github.com/enxy0/passwall2_install)