<div dir="rtl">

# 🚀 OpenWrt Passwall2 Auto-Configuration Suite

🌐 **زبان‌ها:** [English](README.md) | [فارسی](README_fa.md) | [Русский](README_ru.md) | [简体中文](README_zh.md)

اسکریپت خودکار، مقاوم و پرامکانات برای نصب و پیکربندی **Passwall2** روی روترهای OpenWrt.

این اسکریپت برای مدیریت تفاوت‌های package manager در نسخه‌های مختلف OpenWrt، حل خودکار وابستگی‌های kernel و DNS، دانلود از چند سورس مختلف (شامل میرور اختصاصی ایران) و اعمال بهینه‌سازی‌های شبکه و سیستم طراحی شده است.

---

## ✨ ویژگی‌های کلیدی

| ویژگی | توضیح |
| :--- | :--- |
| ⚡ **Package Manager Agnostic** | پشتیبانی کامل از نسخه‌های جدید OpenWrt (`apk` در OpenWrt 24.10 / 25+) و نسخه‌های قدیمی‌تر (`opkg`) و نصب شفاف پکیج‌های `.apk` و `.ipk`. |
| 🌐 **Triple-Source Engine** | امکان نصب از مخازن رسمی SourceForge (پیش‌فرض)، دانلود مستقیم از **GitHub Releases** (`-g`)، یا **میرور ایرانی GitHub** (`-gm`) از طریق `scorpian.ir`. |
| 📦 **Customizable Profiles** | امکان انتخاب پروفایل‌های نصب **Standard** (هردو هسته Xray و Sing-Box)، **Full Feature** (`-f`)، **Minimal Xray** (`-x`)، **Minimal Sing-Box** (`-s`)، یا **LuCI UI Only** (`-l`) متناسب با حجم حافظه روتر. |
| 🛡️ **Resilient Core Fallback & Mirror Support** | تضمین نصب خودکار هسته‌های پروکسی حتی پس از حذف آن‌ها در آرشیوهای جدید Passwall2. در حالت میرور ایران (`-gm`)، هسته‌ها مستقیماً و با حداکثر سرعت از میرور اختصاصی ایران (`scorpian.ir/repos/XTLS/Xray-core` و `scorpian.ir/repos/sagernet/sing-box`) دانلود می‌شوند و در صورت نیاز به نسخه‌های رسمی گیت‌هاب فال‌بک می‌کنند. |
| 🛠️ **Zero-Downtime Swap** | ارتقای امن `dnsmasq` به `dnsmasq-full` و نصب kernel moduleهای لازم (`kmod-nft-tproxy`, `kmod-nft-socket`) بدون قطعی اینترنت با استفاده از fallback resolverها. |
| 🇮🇷 **Iran Regional Fixes** | سوییچ اختصاصی (`-i`) جهت مقداردهی اولیه فوری DNS داخلی (`5.200.200.200`) در شروع اسکریپت برای عبور از اختلالات شدید DNS، تنظیم timezone به `Asia/Tehran`، حل مشکل DNS Rebinding پورتال اپراتورها (*Irancell, MCI, TCI*) و پچ کردن بنر استاتوس Passwall. |
| 🔑 **Emergency Password Reset** | بازپیکربندی دکمه ریست سخت‌افزاری (`-rb`) جهت پاک کردن پسورد root SSH با نگه داشتن ۵ ثانیه‌ای دکمه بدون پاک شدن تنظیمات روتر. |
| 📶 **Default Passwords Setup** | تنظیم سریع پسورد Wi-Fi (باند 2.4GHz و 5GHz) و پسورد root SSH به `123456789` (`-rw`). |

---

## ⚡ Quick Start

اسکریپت نصب خودکار را از طریق SSH روی روتر OpenWrt خود اجرا کنید:

```bash
rm -f /tmp/set.sh && wget -O /tmp/set.sh https://raw.githubusercontent.com/sadraimam/auto_passwall2/refs/heads/main/set.sh && chmod +x /tmp/set.sh && sh /tmp/set.sh
```

---

## 🎛️ Command-Line Reference & Flags

با اضافه کردن سوییچ‌های زیر به دستور اجرای اسکریپت، نصب خود را سفارشی‌سازی کنید:

| Flag | Long Option | توضیح |
| :--- | :--- | :--- |
| `-g [VER]` | `--github [VER]` | نصب مستقیم از GitHub Releases به جای سورس‌های SourceForge. قابلیت تعیین release tag مشخص (مانند `26.8.17-1`). |
| `-gm [VER]` | `--github-mirror [VER]` | نصب از **میرور ایرانی GitHub** (`scorpian.ir`). دور زدن GitHub rate-limiting، DNS pollution و اختلالات ISP در ایران. نام مستعار: `-m`. |
| `-c` | `--clean` | اجرای Clean Installation. پاکسازی پکیج‌های قبلی Passwall2 و binaryهای اجرا شده قبل از نصب جهت جلوگیری از تداخل. |
| `-x` | `--xray` | نصب Minimal فقط با هسته **xray-core** (صرفه‌جویی در فضای فلش با حذف sing-box و باینری‌های اضافی). |
| `-s` | `--singbox` | نصب Minimal فقط با هسته **sing-box** (صرفه‌جویی در فضای فلش با حذف xray-core و باینری‌های اضافی). |
| `-lb` | `--loadbalancing` | نصب و تضمین پکیج‌های Load Balancing (`haproxy` و `microsocks`). قابل استفاده در کنار پروفایل‌های `-s` یا `-x` یا حالت پیش‌فرض؛ در صورت استفاده همزمان با `-f` به دلیل وجود این پکیج‌ها در نصب کامل به صورت خودکار نادیده گرفته می‌شود. |
| `-f` | `--full` | نصب Full Feature. شامل تمام proxy coreها و ابزارها: `chinadns-ng`, `hysteria`, `haproxy`, `microsocks`, `naiveproxy`, `xray-core`, `sing-box`, `geoview`, `v2ray-geoip`, `v2ray-geosite`, `tcping`. |
| `-l` | `--only-luci` | نصب فقط LuCI web interface (`luci-app-passwall2`). بدون دانلود پکیج‌های binary (مفید در صورتی که coreهای سفارشی در فیرمور بیلد شده باشند). |
| `-i` | `--iran` | اعمال بهینه‌سازی‌های ایران: تنظیم فوری DNS محلی `5.200.200.200` در ابتدای اسکریپت، تنظیم timezone به `Asia/Tehran`، حل مشکل DNS Rebinding پورتال اپراتورها (`my.irancell.ir`, `my.mci.ir`, `login.tci.ir`) و پچ کردن بنر استاتوس Passwall. |
| `-rw` | `--root-wifi` | تنظیم پسورد root SSH و وای‌فای 2.4GHz/5GHz به `123456789`. |
| `-rb` | `--reset-button` | بازپیکربندی دکمه ریست سخت‌افزاری: فشردن ۱ ثانیه‌ای برای reboot روتر؛ فشردن ۵ ثانیه‌ای برای پاک کردن پسورد root (`passwd -d root`). |
| `-nf` | `--no-feed` | عدم افزودن فید passwall build؛ نصب هسته‌ها از مخازن فعلی روتر. |
| `-ns` | `--no-restart` | عدم ری‌استارت خودکار سرویس‌های Passwall2 پس از اتمام نصب. |
| `-h` | `--help` | نمایش help و راهنمای سوییچ‌های اسکریپت. |

---

## 💡 Recommended Installation Recipes

### 1. تنظیمات پیشنهادی برای ایران (سرعت و پایداری بالا)
استفاده از میرور ایرانی GitHub، نصب clean، تنظیم پسورد root/Wi-Fi و اعمال بهینه‌سازی‌های ایران:
```bash
sh /tmp/set.sh -gm -c -rw -i
```

### 2. Clean Install از GitHub Releases رسمی (هردو هسته)
دانلود مستقیم آخرین release binaryها از GitHub و اطمینان از نصب هردو هسته Xray و Sing-box:
```bash
sh /tmp/set.sh -g -c
```

### 3. نصب Minimal فقط با Xray (حداکثر صرفه‌جویی در فضا)
نصب فقط هسته `xray-core` و geo-databaseهای لازم جهت باقی ماندن حداکثر فضای خالی روی پارتیشن overlay:
```bash
sh /tmp/set.sh -x -c
```

### 4. نصب Minimal همراه با Load Balancing (haproxy و microsocks)
نصب هسته سبک `sing-box` به همراه `haproxy` و `microsocks` برای توزیع بار بین سرورها:
```bash
sh /tmp/set.sh -gm -s -lb -i
```

### 5. نصب یک Release Version مشخص
نصب یک نسخه خاص (مثلاً `26.8.17-1`) از طریق میرور ایران:
```bash
sh /tmp/set.sh -gm 26.8.17-1 -c
```

### 6. Full Feature Stack Installation
نصب تمامی هسته‌ها و ابزارهای پشتیبانی‌شده (Hysteria, NaiveProxy, HAProxy, ChinaDNS-NG و ...):
```bash
sh /tmp/set.sh -f -c
```

---

## 📋 System Requirements

- **Supported OS:** OpenWrt (نسخه‌های رسمی Release و نسخه‌های Snapshot پشتیبانی می‌شوند).
- **Architecture:** `x86_64`, `aarch64_cortex-a53`, `aarch64_cortex-a72`, `aarch64_generic`, `arm_cortex-a7`, `arm_cortex-a15`, `mipsel_24kc`, `mips_24kc` و غیره.
- **حداقل مشخصات سخت‌افزاری:**
  - **Flash:** 128 MB (حداقل 60 MB+ فضای خالی در overlay)
  - **RAM:** 256 MB

> [!NOTE]
> **Xiaomi AX3000T & دستگاه‌های با حافظه محدود:**
> پارتیشن‌بندی فابریک Xiaomi AX3000T فضایی حدود 60 MB برای overlay فراهم می‌کند. این اسکریپت برای اجرا در این فضا بهینه‌سازی شده است. برای بهترین نتیجه، از حالت minimal sing-box (`-s`) یا minimal xray (`-x`) استفاده کنید یا با فلش UBoot سفارشی، فضای overlay را به حدود 85 MB افزایش دهید.

---

## 🛠️ Recovery & Safety Features

- **Configuration Backup:** تنظیمات موجود Passwall در `/etc/config/passwall2*` قبل از اعمال تغییرات، به طور خودکار با پسوند تاریخ‌دار `.bak` بکاپ گرفته می‌شوند.
- **Emergency Hardware Reset (`-rb`):** در صورت قطع دسترسی SSH، نگه داشتن دکمه ریست فیزیکی دستگاه به مدت ۵ ثانیه پسورد root را پاک می‌کند بدون اینکه تنظیمات شبکه یا پکیج‌های نصب‌شده پاک شوند.
- **Space Check & Cleanup Advice:** اسکریپت قبل از دانلود پکیج‌ها فضای `/tmp` را چک کرده و در صورت کمبود فضا راهکارهای disk cleanup ارائه می‌دهد.

---

## 📄 License & Attribution

- **Script Maintainer:** [sadraimam](https://github.com/sadraimam)
- **Passwall2 Upstream Project:** [Openwrt-Passwall/openwrt-passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2)
- **Iranian Mirror Provider:** [scorpian.ir](https://scorpian.ir/repos/Openwrt-Passwall/openwrt-passwall2)
- **Thanks to:** [enxy0](https://github.com/enxy0/passwall2_install)

</div>
