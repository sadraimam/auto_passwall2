#!/bin/bash

# =========================================================
# OpenWrt Passwall2 Auto Installer
# Supports:
#   - opkg (Older OpenWrt)
#   - apk  (New OpenWrt snapshots/releases)
# Single-file portable installer
# =========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# =========================================================
# Root Check
# =========================================================

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root.${NC}"
    exit 1
fi

echo -e "${GREEN}Running as root...${NC}"
sleep 1
clear

# =========================================================
# Detect OpenWrt Version
# =========================================================

OPENWRT_VERSION="$(. /etc/openwrt_release && echo "$DISTRIB_RELEASE")"
OPENWRT_MAJOR="$(echo "$OPENWRT_VERSION" | cut -d. -f1)"
OPENWRT_ARCH="$(. /etc/openwrt_release && echo "$DISTRIB_ARCH")"

echo -e "${CYAN}OpenWrt Version:${NC} $OPENWRT_VERSION"
echo -e "${CYAN}Architecture:${NC} $OPENWRT_ARCH"

# =========================================================
# Detect Package Manager
# =========================================================

if command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
elif command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
else
    echo -e "${RED}No supported package manager found!${NC}"
    exit 1
fi

echo -e "${CYAN}Package Manager:${NC} $PKG_MGR"

# =========================================================
# Package Manager Abstraction
# =========================================================

pkg_update() {
    if [ "$PKG_MGR" = "apk" ]; then
        apk update
    else
        opkg update
    fi
}

pkg_install() {
    if [ "$PKG_MGR" = "apk" ]; then
        apk add "$@"
    else
        opkg install "$@"
    fi
}

pkg_remove() {
    if [ "$PKG_MGR" = "apk" ]; then
        apk del "$@"
    else
        opkg remove "$@"
    fi
}

pkg_installed() {
    if [ "$PKG_MGR" = "apk" ]; then
        apk info -e "$1" >/dev/null 2>&1
    else
        opkg list-installed | grep -q "^$1 "
    fi
}

# =========================================================
# Snapshot Warning
# =========================================================

if grep -q SNAPSHOT /etc/openwrt_release; then
    echo -e "${YELLOW}SNAPSHOT build detected.${NC}"
    echo -e "${YELLOW}Proceeding with APK compatibility mode.${NC}"
fi

# =========================================================
# Initialize Network
# =========================================================

echo -e "${GREEN}Configuring Network...${NC}"

uci del network.wan.dns 2>/dev/null
uci set network.wan.peerdns="0"

uci add_list network.wan.dns="8.8.4.4"
uci add_list network.wan.dns="8.8.8.8"
uci add_list network.wan.dns="1.1.1.1"
uci add_list network.wan.dns="1.0.0.1"
uci add_list network.wan.dns="5.200.200.200"

uci del network.wan6.dns 2>/dev/null
uci set network.wan6.peerdns="0"

uci add_list network.wan6.dns="2001:4860:4860::8888"
uci add_list network.wan6.dns="2001:4860:4860::8844"
uci add_list network.wan6.dns="2606:4700:4700::1111"
uci add_list network.wan6.dns="2606:4700:4700::1001"

uci commit network
/sbin/reload_config >/dev/null

echo -e "${GREEN}Network Initialized.${NC}"

# =========================================================
# Internet Check
# =========================================================

until ping -c1 -W1 8.8.8.8 >/dev/null 2>&1; do
    echo -e "${YELLOW}Waiting for internet...${NC}"
    sleep 2
done

echo -e "${GREEN}Internet reachable.${NC}"

# =========================================================
# Time Configuration
# =========================================================

echo -e "${GREEN}Configuring Time...${NC}"

uci set system.@system[0].zonename='Asia/Tehran'
uci set system.@system[0].timezone='<+0330>-3:30'

uci delete system.ntp.server

uci add_list system.ntp.server='0.asia.pool.ntp.org'
uci add_list system.ntp.server='1.asia.pool.ntp.org'
uci add_list system.ntp.server='0.openwrt.pool.ntp.org'
uci add_list system.ntp.server='1.openwrt.pool.ntp.org'

uci commit system

/etc/init.d/sysntpd restart

echo -e "${YELLOW}Syncing time...${NC}"

ntpd -n -q -p ir.pool.ntp.org || \
ntpd -n -q -p 0.openwrt.pool.ntp.org

echo -e "${CYAN}Current Time:${NC} $(date)"

# =========================================================
# Passwall Feed Setup
# =========================================================

echo -e "${GREEN}Setting up repositories...${NC}"

read release arch <<EOF
$(. /etc/openwrt_release; echo ${DISTRIB_RELEASE%.*} $DISTRIB_ARCH)
EOF

if [ "$PKG_MGR" = "opkg" ]; then

    wget -O /tmp/passwall.pub \
    https://master.dl.sourceforge.net/project/openwrt-passwall-build/ipk.pub

    opkg-key add /tmp/passwall.pub

    rm -f /tmp/passwall.pub

    > /etc/opkg/customfeeds.conf

    for feed in passwall_luci passwall_packages passwall2; do
        echo "src/gz $feed https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-$release/$arch/$feed" \
        >> /etc/opkg/customfeeds.conf
    done

else

    mkdir -p /etc/apk/repositories.d

    cat > /etc/apk/repositories.d/passwall.list <<EOF
https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-$release/$arch/passwall_packages
https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-$release/$arch/passwall_luci
https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-$release/$arch/passwall2
EOF

fi

echo -e "${GREEN}Repositories configured.${NC}"

# =========================================================
# Update Package Lists
# =========================================================

echo -e "${YELLOW}Updating package lists...${NC}"
pkg_update

# =========================================================
# Universal Installer
# =========================================================

install_pkg() {

    pkg="$1"

    if pkg_installed "$pkg"; then
        echo -e "${YELLOW}$pkg already installed.${NC}"
        return 0
    fi

    echo -e "${YELLOW}Installing $pkg ...${NC}"

    if [ "$PKG_MGR" = "apk" ]; then

        apk add "$pkg"

    else

        cd /tmp || return 1

        rm -f ${pkg}_*.ipk

        retry=3

        while [ $retry -gt 0 ]; do

            opkg download "$pkg"

            if ls ${pkg}_*.ipk >/dev/null 2>&1; then
                break
            fi

            retry=$((retry - 1))

            echo -e "${RED}Retrying $pkg download...${NC}"
            sleep 3
        done

        ipk_file=$(ls -t ${pkg}_*.ipk 2>/dev/null | head -n1)

        if [ -z "$ipk_file" ]; then
            echo -e "${RED}Failed downloading $pkg${NC}"
            return 1
        fi

        opkg install "$ipk_file"

        rm -f ${pkg}_*.ipk
    fi

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}$pkg installed.${NC}"
    else
        echo -e "${RED}$pkg installation failed.${NC}"
    fi

    sleep 1
}

# =========================================================
# Main Install
# =========================================================

echo -e "${GREEN}Starting installation...${NC}"

pkg_remove dnsmasq

install_pkg dnsmasq-full
install_pkg sing-box
install_pkg luci-app-passwall2
install_pkg ipset
install_pkg kmod-tun
install_pkg kmod-nft-tproxy
install_pkg kmod-nft-socket
install_pkg kmod-netlink-diag
install_pkg wget-ssl
install_pkg unzip
install_pkg ca-bundle
install_pkg kmod-inet-diag

# =========================================================
# Verify Installation
# =========================================================

verify_installation() {

    local name="$1"
    local path="$2"

    if [ -e "$path" ]; then
        echo -e "${GREEN}${name}: INSTALLED${NC}"
    else
        echo -e "${RED}${name}: MISSING${NC}"
    fi
}

verify_installation "Passwall2" "/etc/init.d/passwall2"
verify_installation "Sing-box" "/usr/bin/sing-box"

# =========================================================
# Passwall Patch
# =========================================================

echo -e "${GREEN}Applying Passwall patch...${NC}"

wget -O /tmp/status.htm \
https://raw.githubusercontent.com/sadraimam/ax3000t/refs/heads/main/status.htm

cp /tmp/status.htm \
/usr/lib/lua/luci/view/passwall2/global/status.htm 2>/dev/null

cp /tmp/status.htm \
/usr/lib64/lua/luci/view/passwall2/global/status.htm 2>/dev/null

echo "/usr/lib/lua/luci/view/passwall2/global/status.htm" \
>> /lib/upgrade/keep.d/luci-app-passwall2 2>/dev/null

rm -f /tmp/status.htm

echo -e "${GREEN}Passwall patched.${NC}"

# =========================================================
# Passwall Configuration
# =========================================================

echo -e "${GREEN}Configuring Passwall2...${NC}"

uci set passwall2.@global_forwarding[0]=global_forwarding
uci set passwall2.@global_forwarding[0].tcp_no_redir_ports='disable'
uci set passwall2.@global_forwarding[0].udp_no_redir_ports='disable'
uci set passwall2.@global_forwarding[0].tcp_redir_ports='1:65535'
uci set passwall2.@global_forwarding[0].udp_redir_ports='1:65535'

uci set passwall2.@global[0].remote_dns='8.8.4.4'
uci set passwall2.@global[0].remote_dns_ipv6='https://dns.google/dns-query'

uci commit passwall2

echo -e "${GREEN}Passwall configured.${NC}"

# =========================================================
# DNS Rebind Fix
# =========================================================

uci set dhcp.@dnsmasq[0].rebind_domain='my.irancell.ir my.mci.ir login.tci.ir local.tci.ir'

uci commit dhcp

/etc/init.d/dnsmasq restart

echo -e "${GREEN}DNS Rebind fixed.${NC}"

# =========================================================
# WiFi Configuration
# =========================================================

echo -e "${GREEN}Configuring WiFi...${NC}"

uci set wireless.radio0.cell_density='0'
uci set wireless.default_radio0.encryption='sae-mixed'
uci set wireless.default_radio0.key='123456789'
uci set wireless.default_radio0.ocv='0'
uci set wireless.radio0.disabled='0'

uci set wireless.radio1.cell_density='0'
uci set wireless.default_radio1.encryption='sae-mixed'
uci set wireless.default_radio1.key='123456789'
uci set wireless.default_radio1.ocv='0'
uci set wireless.radio1.disabled='0'

uci commit wireless

wifi reload

echo -e "${GREEN}WiFi configured.${NC}"

# =========================================================
# Root Password
# =========================================================

echo -e "${GREEN}Setting root password...${NC}"

(
echo "123456789"
echo "123456789"
) | passwd root >/dev/null 2>&1

echo -e "${CYAN}Root Password: 123456789${NC}"

# =========================================================
# Cleanup
# =========================================================

rm -f /root/set.sh
/sbin/reload_config

echo -e "${GREEN}Installation Completed.${NC}"

# =========================================================
# Reboot Prompt
# =========================================================

while true; do

    printf "${YELLOW}Press [r] reboot or [e] exit: ${NC}"

    read -rsn1 input

    case "$input" in

        r|R)
            echo -e "${GREEN}\nRebooting...${NC}"
            reboot
            exit 0
            ;;

        e|E)
            echo -e "${RED}\nExiting.${NC}"
            exit 0
            ;;

        *)
            echo -e "${RED}\nInvalid choice.${NC}"
            ;;
    esac
done
