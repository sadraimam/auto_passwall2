# 🚀 OpenWrt Passwall2 自动化配置脚本

🌐 **语言:** [English](README.md) | [فارسی](README_fa.md) | [Русский](README_ru.md) | [简体中文](README_zh.md)

专为 OpenWrt 路由器打造的自动化、高可用且功能丰富的 **Passwall2** 安装与配置脚本。

全面适配不同 OpenWrt 版本的包管理器差异，自动解析内核与 DNS 依赖，提供多源发布包下载（包含伊朗本土镜像），并支持可选的区域网络与系统优化。

---

## ✨ 核心特性

| 功能 | 说明 |
| :--- | :--- |
| ⚡ **无缝包管理器兼容** | 完美支持 OpenWrt 新一代版本（OpenWrt 24.10 / 25+ 中的 `apk`）与经典版本（`opkg`），透明处理 `.apk` 和 `.ipk` 格式安装包。 |
| 🌐 **三源安装引擎** | 支持从 SourceForge 官方软件源（默认）、**GitHub Releases** 直链（`-g`）或通过 `scorpian.ir` 的 **伊朗本土 GitHub 镜像**（`-gm`）进行安装。 |
| 📦 **灵活的安装方案** | 提供 **标准方案**（同时安装 Xray 与 Sing-Box）、**全功能方案**（`-f`）、**精简 Xray 方案**（`-x`）、**精简 Sing-Box 方案**（`-s`）以及 **仅 LuCI 界面**（`-l`），满足各种硬件与存储需求。 |
| 🛡️ **核心高可用回退与镜像加速** | 针对上游 Passwall2 发布包剔除核心的问题，提供可靠的自动补全机制。在伊朗镜像模式（`-gm`）下，直接从专用本地镜像（`scorpian.ir/repos/XTLS/Xray-core` 与 `scorpian.ir/repos/sagernet/sing-box`）高速免阻断下载；必要时自动回退至 GitHub 官方发布源与加速节点。 |
| 🛠️ **零中断无缝热更** | 安全将 `dnsmasq` 升级为 `dnsmasq-full` 并安装内核模块（`kmod-nft-tproxy`, `kmod-nft-socket`），通过备用解析器确保升级全过程网络不中断。 |
| 🇮🇷 **伊朗区域优化** | 专属 `-i` 参数，脚本启动阶段立即初始化本土 DNS（`5.200.200.200`）以规避 DNS 阻断，配置 `Asia/Tehran` 时区，修复运营商门户（*Irancell, MCI, TCI*）的 DNS 重绑定问题，并修补 Passwall 状态横幅。 |
| 🔑 **应急密码重置** | 重新映射物理 Reset 按键（`-rb`）：按住 5 秒即可重置 root SSH 密码，无需恢复出厂设置，保留原有网络与配置。 |
| 📶 **一键初始化默认密码** | 快速将 2.4GHz/5GHz Wi-Fi 密码及 root SSH 密码统一配置为 `123456789`（`-rw`）。 |

---

## ⚡ 快速开始

通过 SSH 在 OpenWrt 路由器上执行以下命令进行快速安装：

```bash
rm -f /tmp/set.sh && wget -O /tmp/set.sh https://raw.githubusercontent.com/sadraimam/auto_passwall2/refs/heads/main/set.sh && chmod +x /tmp/set.sh && sh /tmp/set.sh
```

---

## 🎛️ 命令行参数与选项

在执行脚本时添加以下参数来自定义安装配置：

| 参数 | 完整参数 | 说明 |
| :--- | :--- | :--- |
| `-g [VER]` | `--github [VER]` | 直接从 GitHub Releases 安装而非 SourceForge 源。可选用指定版本标签（例如 `26.8.17-1`）。 |
| `-gm [VER]` | `--github-mirror [VER]` | 从**伊朗 GitHub 镜像**（`scorpian.ir`）安装。可有效规避 GitHub API 速率限制、DNS 污染及 ISP 限速。别名：`-m`。 |
| `-c` | `--clean` | 全新安装（Clean Install）。在安装前自动卸载已有 Passwall2 组件及二进制文件，杜绝冲突。 |
| `-x` | `--xray` | 仅安装 **xray-core** 的精简模式（跳过 sing-box 及附加组件，大幅节省 Flash 存储空间）。 |
| `-s` | `--singbox` | 仅安装 **sing-box** 核心的精简模式（跳过 xray-core 及附加组件，大幅节省 Flash 存储空间）。 |
| `-lb` | `--loadbalancing` | 安装并确保负载均衡组件（`haproxy`, `microsocks`）。可与 `-s`、`-x` 或默认模式配合使用；与 `-f` 同时使用时会自动跳过（全功能模式已包含）。 |
| `-f` | `--full` | 全功能完整安装。包含所有协议核心与辅助工具：`chinadns-ng`, `hysteria`, `haproxy`, `microsocks`, `naiveproxy`, `xray-core`, `sing-box`, `geoview`, `v2ray-geoip`, `v2ray-geosite`, `tcping`。 |
| `-l` | `--only-luci` | 仅安装 LuCI 控制面板（`luci-app-passwall2`）。跳过下载二进制软件包（适用于固件已内置核心的情况）。 |
| `-i` | `--iran` | 应用伊朗区域优化：在脚本启动时初始化本地 `5.200.200.200` DNS，设置 `Asia/Tehran` 时区，修复运营商 DNS 重绑定（`my.irancell.ir`, `my.mci.ir`, `login.tci.ir`），并修补 Passwall 状态横幅。 |
| `-rw` | `--root-wifi` | 将 root SSH 密码及 2.4GHz/5GHz Wi-Fi 密码设为 `123456789`。 |
| `-rb` | `--reset-button` | 重映射物理 Reset 键：轻按 1 秒重启路由器；长按 5 秒清除 root 密码（`passwd -d root`）。 |
| `-nf` | `--no-feed` | 不添加 Passwall 软件源；直接从现有软件源安装核心。 |
| `-ns` | `--no-restart` | 安装完成后不自动重启 Passwall2 服务。 |
| `-h` | `--help` | 显示脚本使用帮助并退出。 |

---

## 💡 推荐安装组合

### 1. 伊朗推荐方案（高速与高可用）
使用伊朗 GitHub 本地镜像、全新安装、初始化 root 与 Wi-Fi 密码并应用区域优化：
```bash
sh /tmp/set.sh -gm -c -rw -i
```

### 2. GitHub 官方源全新安装（双核心）
直接从 GitHub 获取最新发布二进制包，同时确保安装 Xray 与 Sing-box：
```bash
sh /tmp/set.sh -g -c
```

### 3. 精简 Xray 方案（最大化节省存储）
仅安装 `xray-core` 和必要规则数据库，为路由器保留最大可用空间：
```bash
sh /tmp/set.sh -x -c
```

### 4. 精简 Sing-Box 与负载均衡方案
安装轻量级 `sing-box` 核心并附加 `haproxy` 与 `microsocks` 实现多节点负载均衡：
```bash
sh /tmp/set.sh -gm -s -lb -i
```

### 5. 锁定特定版本安装
通过伊朗镜像安装指定的发布版本（例如 `26.8.17-1`）：
```bash
sh /tmp/set.sh -gm 26.8.17-1 -c
```

### 6. 全协议全功能栈安装
安装所有受支持的代理协议核心（Hysteria, NaiveProxy, HAProxy, ChinaDNS-NG 等）：
```bash
sh /tmp/set.sh -f -c
```

---

## 📋 系统要求

- **支持的操作系统：** OpenWrt（支持官方 Release 正式版与 Snapshot 快照版）。
- **CPU 架构：** `x86_64`, `aarch64_cortex-a53`, `aarch64_cortex-a72`, `aarch64_generic`, `arm_cortex-a7`, `arm_cortex-a15`, `mipsel_24kc`, `mips_24kc` 等。
- **最低硬件配置：**
  - **Flash 存储：** 128 MB（overlay 分区可用空间 60 MB+）
  - **运行内存（RAM）：** 256 MB

> [!NOTE]
> **关于小米 AX3000T 等存储受限设备：**
> 小米 AX3000T 原厂分区方案下 overlay 可用空间约为 60 MB。本脚本已针对该空间大小进行专项优化。为达到最佳效果，推荐选用精简 sing-box 模式（`-s`），或刷入自定义 U-Boot 分区布局以获取约 85 MB 的 overlay 存储空间。

---

## 🛠️ 恢复与安全机制

- **配置自动备份：** 修改前会自动备份 `/etc/config/passwall2*` 中的原有配置，并添加带日期的 `.bak` 扩展名。
- **硬件应急重置（`-rb`）：** 若忘记 SSH 密码，长按路由器物理 Reset 键 5 秒即可清除 root 密码，不会破坏已有网络配置与已装插件。
- **空间预检与清理提示：** 脚本下载前会检查 `/tmp` 目录剩余容量，并在空间不足时提供清理建议。

---

## 📄 授权与致谢

- **脚本维护者：** [sadraimam](https://github.com/sadraimam)
- **Passwall2 上游项目：** [Openwrt-Passwall/openwrt-passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2)
- **伊朗镜像提供方：** [scorpian.ir](https://scorpian.ir/repos/Openwrt-Passwall/openwrt-passwall2)
- **鸣谢：** [enxy0](https://github.com/enxy0/passwall2_install)
