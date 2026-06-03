# OpenWrt Passwall2 Auto Configuration
Automated configuration script for setting up Passwall2 on the Xiaomi AX3000T running OpenWrt.
Also compatible with similar OpenWrt-supported hardware. Minimum hardware profile:
- Flash `128MB`
- RAM `256MB`

## Installation
⚠ Openwrt V25: Consider flashing AX3200 with UBoot Layout to gain extra 15mb (85mb total). use set_t.sh to install without any preconfiguration!
### Run from ssh
```bash
rm -f /tmp/set.sh && wget -O /tmp/set.sh https://raw.githubusercontent.com/sadraimam/ax3000t/refs/heads/main/set.sh && chmod +x /tmp/set.sh && sh /tmp/set.sh
```
⚠ Manual Upgrade Required: Only Sing-box must be manually upgraded via the Passwall2 App Update page due to router storage limits; all other packages install automatically at their latest versions.

```bash
rm -f /tmp/set.sh && wget -O /tmp/set.sh https://raw.githubusercontent.com/sadraimam/ax3000t/refs/heads/main/set_t.sh && chmod +x /tmp/set.sh && sh /tmp/set.sh
```

## Features
- Advanced custom package installer using RAM with retry download logic and optional custom URL
- Installs and configures Passwall2 with recommended defaults.
- Sets up optimized DNS and network settings
- Configures WiFi with secure defaults
- Adds custom routing rules for Iranian networks

## Prerequisites
- OpenWrt installed (non-SNAPSHOT version)
- Root access to the router
- Working internet connection

## Default Settings
- Default root & wifi password: 123456789 (Change after installation!)
- Timezone: Asia/Tehran
- DNS: Google DNS (8.8.4.4, 2001:4860:4860::8844)

## Passwall2 Update Mechanism
Passwall2 uses its own mechanism to update cores (Xray, Sing-box, and Hysteria). It calls the backend API to fetch package versions and determine whether an update is needed. The update process downloads the raw binary data and extracts/replaces the existing files. Note that it does not use the `opkg upgrade` command, which allows it to bypass storage limitations. In future versions of the script, we will mimic this behavior and use the Passwall2 API to automatically install the latest version of all cores.

## Note on Storage
On Xiaomi AX3000T, factory partitioning results in an overlay size of approximately 60 MB, compared to around 90-100 MB available on similar routers. The script is optimized to work with this limited storage space. To regain more free space, you would need to modify the factory partitioning via UART or directly flash the ROM chip (not recommended). If you modify the factory partitions, recovering the original firmware is only possible using these methods.

## Future Plans (work in progress)
- Add script call input parameter to skip options --wifi --rootpw --iran `set.sh`
- Auto-update cores using Passwall2 API `app.sh`
- Advanced DNS config for Iran Network `adv.sh`
