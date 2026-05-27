#!/bin/sh

# =========================================================
# OpenWrt 25.x Passwall2 Installer
# Native APK + manual Passwall IPK install
# =========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# =========================================================
# Root Check
# =========================================================

if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}Run as root.${NC}"
    exit 1
fi

# =========================================================
# OpenWrt Version Check
# =========================================================

OPENWRT_VERSION="$(. /etc/openwrt_release && echo $DISTRIB_RELEASE)"
ARCH="$(. /etc/openwrt_release && echo $DISTRIB_ARCH)"

echo -e "${CYAN}OpenWrt:${NC} $OPENWRT_VERSION"
echo -e "${CYAN}Arch:${NC} $ARCH"

if ! command -v apk >/dev/null 2>&1; then
    echo -e "${RED}This script requires OpenWrt 25.x with APK.${NC}"
    exit 1
fi

# =========================================================
# Network Init
# =========================================================

echo -e "${GREEN}Initializing network...${NC}"

uci set network.wan.peerdns='0'
uci delete network.wan.dns 2>/dev/null

uci add_list network.wan.dns='1.1.1.1'
uci add_list network.wan.dns='8.8.8.8'
uci add_list network.wan.dns='8.8.4.4'

uci commit network
/etc/init.d/network restart

# =========================================================
# Internet Check
# =========================================================

echo -e "${YELLOW}Checking internet...${NC}"

until ping -c1 8.8.8.8 >/dev/null 2>&1; do
    sleep 2
done

echo -e "${GREEN}Internet OK${NC}"

# =========================================================
# APK Update
# =========================================================

echo -e "${GREEN}Updating APK repositories...${NC}"

apk update

# =========================================================
# Base Packages
# =========================================================

echo -e "${GREEN}Installing required packages...${NC}"

apk add \
wget \
curl \
ca-bundle \
dnsmasq-full \
kmod-tun \
kmod-nft-tproxy \
kmod-nft-socket \
kmod-netlink-diag \
kmod-inet-diag \
ipset \
unzip \
tar

# =========================================================
# Create TMP Workspace
# =========================================================

WORKDIR="/tmp/passwall"

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

cd "$WORKDIR" || exit 1

# =========================================================
# Passwall Feed Variables
# =========================================================

BASE_URL="https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12"

PKG_URL="$BASE_URL/$ARCH/passwall_packages"
LUCI_URL="$BASE_URL/$ARCH/passwall_luci"
PW2_URL="$BASE_URL/$ARCH/passwall2"

# =========================================================
# Download Helper
# =========================================================

download_ipk() {

    URL="$1"

    FILE="$(basename "$URL")"

    echo -e "${CYAN}Downloading:${NC} $FILE"

    wget -q --show-progress "$URL"

    if [ ! -f "$FILE" ]; then
        echo -e "${RED}Download failed:${NC} $FILE"
        exit 1
    fi
}

# =========================================================
# Download Core Packages
# =========================================================

echo -e "${GREEN}Downloading Passwall packages...${NC}"

# IMPORTANT:
# Update versions if newer builds appear

download_ipk "$PKG_URL/sing-box_1.12.0-r1_${ARCH}.ipk"
download_ipk "$PW2_URL/luci-app-passwall2_26.5.15-r1_all.ipk"

# =========================================================
# Install IPK Packages
# =========================================================

echo -e "${GREEN}Installing Passwall packages...${NC}"

for PKG in *.ipk; do

    echo -e "${YELLOW}Installing:${NC} $PKG"

    apk add --allow-untrusted "./$PKG"

    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed:${NC} $PKG"
        exit 1
    fi
done

# =========================================================
# Verify Installation
# =========================================================

echo -e "${GREEN}Verifying installation...${NC}"

if [ ! -f /etc/init.d/passwall2 ]; then
    echo -e "${RED}Passwall2 missing.${NC}"
    exit 1
fi

if [ ! -f /usr/bin/sing-box ]; then
    echo -e "${RED}Sing-box missing.${NC}"
    exit 1
fi

echo -e "${GREEN}Passwall2 Installed Successfully.${NC}"

# =========================================================
# Enable Services
# =========================================================

/etc/init.d/passwall2 enable

# =========================================================
# DNS Fix
# =========================================================

uci set dhcp.@dnsmasq[0].rebind_domain='my.irancell.ir my.mci.ir'

uci commit dhcp

/etc/init.d/dnsmasq restart

# =========================================================
# Cleanup
# =========================================================

rm -rf "$WORKDIR"

# =========================================================
# Final
# =========================================================

echo
echo -e "${GREEN}====================================${NC}"
echo -e "${GREEN} Passwall2 Installation Complete ${NC}"
echo -e "${GREEN}====================================${NC}"
echo

echo -e "${CYAN}LuCI:${NC} Services -> Passwall2"

echo
echo -e "${YELLOW}Reboot is recommended.${NC}"
