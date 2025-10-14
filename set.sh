#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#root check
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}This script must be run as root. Exiting. ${NC}"
  exit 1
else
  echo -e "${GREEN}Running as root... ${NC}"
  sleep 2
  clear
fi

#Snapshot check
if grep -q SNAPSHOT /etc/openwrt_release; then
    echo -e "${YELLOW}SNAPSHOT Version Detected!${NC}"
    echo -e "${RED}Snapshot builds are not supported.${NC}"
    exit 1
else
    echo -e "${GREEN}Configuring System...${NC}"
fi

# Initialize Network
uci del network.wan.dns 2>/dev/null
uci set network.wan.peerdns="0"
uci add_list network.wan.dns="8.8.4.4"
uci add_list network.wan.dns="8.8.8.8"
uci add_list network.wan.dns="1.0.0.1"
uci add_list network.wan.dns="1.1.1.1"
uci del network.wan6.dns 2>/dev/null
uci set network.wan6.peerdns="0"
uci add_list network.wan6.dns="2001:4860:4860::8844"
uci add_list network.wan6.dns="2001:4860:4860::8888"
uci add_list network.wan6.dns="2606:4700:4700::1001"
uci add_list network.wan6.dns="2606:4700:4700::1111"
uci commit network
/sbin/reload_config >/dev/null 
echo -e "${CYAN}Current DNS:${NC}"
echo -e "${CYAN}IPv4: $(uci get network.wan.dns)${NC}"
echo -e "${CYAN}IPv6: $(uci get network.wan6.dns)${NC}"
echo -e "${GREEN}Network Initialized!${NC}"

# Internet check
until ping -c1 -W1 8.8.8.8 >/dev/null 2>&1; do
    echo -e "${YELLOW}Waiting for Internet...${NC}"
    sleep 2
done
echo -e "${GREEN}Internet is reachable!${NC}"

# Initialize Time/Date
uci set system.@system[0].zonename='Asia/Tehran'
uci set system.@system[0].timezone='<+0330>-3:30'
uci delete system.ntp.server
uci add_list system.ntp.server='0.asia.pool.ntp.org'
uci add_list system.ntp.server='1.asia.pool.ntp.org'
uci add_list system.ntp.server='0.openwrt.pool.ntp.org'
uci add_list system.ntp.server='1.openwrt.pool.ntp.org'
uci commit system
/etc/init.d/sysntpd restart
echo -e "${GREEN}Time/Date Initialized! ${NC}"
  # NTP Sync
echo -e "${YELLOW}Syncing time with NTP...${NC}"
ntpd -n -q -p ir.pool.ntp.org || {
  echo -e "${RED}NTP sync failed! Retrying with global pool...${NC}"
  ntpd -n -q -p 0.openwrt.pool.ntp.org || {
    echo -e "${RED}NTP sync failed again. Please check DNS/network.${NC}"
  }
}
echo -e "${CYAN}Current system time: $(date)${NC}"

# Add Passwall Feeds
wget -O /tmp/passwall.pub https://master.dl.sourceforge.net/project/openwrt-passwall-build/passwall.pub
opkg-key add /tmp/passwall.pub
rm -f /tmp/passwall.pub
> /etc/opkg/customfeeds.conf
read release arch <<EOF
$(. /etc/openwrt_release; echo ${DISTRIB_RELEASE%.*} $DISTRIB_ARCH)
EOF
for feed in passwall_luci passwall_packages passwall2; do
  echo "src/gz $feed https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-$release/$arch/$feed" >> /etc/opkg/customfeeds.conf
done
echo -e "${GREEN}Feed Updated!${NC}"

# Main install
echo -e "${YELLOW}Updating Packages...${NC}"
opkg update

# Function to install from tmp with optional custom URL
install_tmp() {
  pkg="$1"
  url="$2"  # Optional custom download URL
  # Check if package is already installed
  if opkg list-installed | grep -q "^$pkg - "; then
    echo -e "${YELLOW}$pkg is already installed. Skipping.${NC}"
    return 0
  fi
  echo -e "${YELLOW}Installing $pkg ...${NC}"
  cd /tmp || return 1
  rm -f ${pkg}_*.ipk ${pkg}.custom.ipk  # Clean up previous downloads
  # Download with retry logic
  retry=3
  while [ $retry -gt 0 ]; do
    if [ -n "$url" ]; then
      # Download from custom URL
      echo -e "${YELLOW}Using custom URL:${NC} $url"
      if command -v uclient-fetch >/dev/null; then
        uclient-fetch -O "${pkg}.custom.ipk" "$url"
      elif command -v wget >/dev/null; then
        wget -O "${pkg}.custom.ipk" "$url"
      else
        echo -e "${RED}No download tool (uclient-fetch/wget) found!${NC}"
        return 1
      fi
      # Check if download succeeded
      if [ $? -eq 0 ] && [ -s "${pkg}.custom.ipk" ]; then
        break
      fi
    else
      # Default opkg download
      opkg download "$pkg"
      if [ $? -eq 0 ] && ls ${pkg}_*.ipk >/dev/null 2>&1; then
        break
      fi
    fi
    retry=$((retry - 1))
    if [ $retry -gt 0 ]; then
      echo -e "${RED}Download failed for $pkg. ${retry} attempts remaining. Retrying...${NC}"
      sleep 5
    fi
  done
  # Verify download
  if [ -n "$url" ] && [ -s "${pkg}.custom.ipk" ]; then
    ipk_file="${pkg}.custom.ipk"
  elif ls ${pkg}_*.ipk >/dev/null 2>&1; then
    ipk_file=$(ls -t ${pkg}_*.ipk | head -n1)
  else
    echo -e "${RED}Failed to download $pkg after multiple attempts${NC}"
    return 1
  fi
  # Install package
  opkg install "$ipk_file"
  install_status=$?
  # Cleanup
  rm -f ${pkg}_*.ipk ${pkg}.custom.ipk
  if [ $install_status -ne 0 ]; then
    echo -e "${RED}Installation failed for $pkg${NC}"
  else
    echo -e "${GREEN}Successfully installed $pkg${NC}"
  fi
  sleep 2
  return $install_status
}

ARCH=$(opkg print-architecture | grep -E 'aarch64|arm|mips|x86' | awk '{print $2}')
# Main Install Sequence
opkg remove dnsmasq
install_tmp dnsmasq-full
install_tmp luci-app-passwall2 "https://github.com/xiaorouji/openwrt-passwall2/releases/download/25.7.15-1/luci-24.10_luci-app-passwall2_25.7.15-r1_all.ipk"
install_tmp ipset
install_tmp kmod-tun
install_tmp kmod-nft-tproxy
install_tmp kmod-nft-socket
#install_tmp kmod-netlink-diag
#install_tmp wget-ssl
#install_tmp unzip
#install_tmp ca-bundle
#install_tmp kmod-inet-diag
#install_tmp kernel
install_tmp sing-box "https://github.com/SagerNet/sing-box/releases/download/v1.11.15/sing-box_1.11.15_openwrt_${ARCH}.ipk"
install_tmp hysteria
opkg --force-overwrite upgrade luci-app-passwall2
#opkg --force-overwrite upgrade sing-box

# Function to verify installation
verify_installation() {
    local name="$1"
    local path="$2"
    if [ -e "$path" ]; then
        echo -e "${GREEN}${name} : INSTALLED!${NC}"
    else
        echo -e "${YELLOW}${name} : NOT INSTALLED!${NC}"
    fi
}

# Verify installations
verify_installation "dnsmasq-full" "/usr/lib/opkg/info/dnsmasq-full.control"
verify_installation "Passwall2" "/etc/init.d/passwall2"
verify_installation "XRAY" "/usr/bin/xray"
verify_installation "Sing-box" "/usr/bin/sing-box"
verify_installation "Hysteria" "/usr/bin/hysteria"

# Passwall Patch
wget -O /tmp/status.htm https://raw.githubusercontent.com/sadraimam/ax3000t/refs/heads/main/status.htm
cp /tmp/status.htm /usr/lib/lua/luci/view/passwall2/global/status.htm
cp /tmp/status.htm /usr/lib64/lua/luci/view/passwall2/global/status.htm
echo "/usr/lib/lua/luci/view/passwall2/global/status.htm" >> /lib/upgrade/keep.d/luci-app-passwall2 #issue: installing update wipes the patch
rm -f /tmp/status.htm
echo -e "${GREEN}** Passwall Patched ** ${NC}"

# Passwall2 Settings
uci set passwall2.@global_forwarding[0]=global_forwarding
uci set passwall2.@global_forwarding[0].tcp_no_redir_ports='disable'
uci set passwall2.@global_forwarding[0].udp_no_redir_ports='disable'
uci set passwall2.@global_forwarding[0].tcp_redir_ports='1:65535'
uci set passwall2.@global_forwarding[0].udp_redir_ports='1:65535'
uci set passwall2.@global[0].remote_dns='8.8.4.4'
uci set passwall2.@global[0].remote_dns_ipv6='https://dns.google/dns-query'

  # Delete unused rules and sub
uci delete passwall2.GooglePlay
uci delete passwall2.Netflix
uci delete passwall2.OpenAI
uci delete passwall2.China
uci delete passwall2.QUIC
uci delete passwall2.Proxy
uci delete passwall2.UDP
uci delete passwall2.@global_subscribe[0].filter_discard_list

uci set passwall2.Direct=shunt_rules
uci set passwall2.Direct.network='tcp,udp'
uci set passwall2.Direct.remarks='IRAN'

  # Optimized IP List (includes geoip:ir + all private/special ranges)
uci set passwall2.Direct.ip_list='0.0.0.0/8
10.0.0.0/8
100.64.0.0/10
127.0.0.0/8
169.254.0.0/16
172.16.0.0/12
192.0.0.0/24
192.0.2.0/24
192.88.99.0/24
192.168.0.0/16
198.19.0.0/16
198.51.100.0/24
203.0.113.0/24
224.0.0.0/4
240.0.0.0/4
255.255.255.255/32
::/128
::1/128
::ffff:0:0:0/96
64:ff9b::/96
100::/64
2001::/32
2001:20::/28
2001:db8::/32
2002::/16
fc00::/7
fe80::/10
ff00::/8
geoip:ir'

  # Improved Domain List: geo-based + known local portals
uci set passwall2.Direct.domain_list='regexp:^.+\.ir$
geosite:category-ir
geosite:ir
full:my.irancell.ir
full:my.mci.ir
full:login.tci.ir
full:local.tci.ir'

uci set passwall2.myshunt.Direct='_direct'
uci set passwall2.myshunt.DirectGame='_direct'
uci set passwall2.myshunt.remarks='MainShunt'

  # Save and apply
uci commit passwall2
echo -e "${GREEN}** Passwall Configured ** ${NC}"

# DNS Rebind Fix
uci set dhcp.@dnsmasq[0].rebind_domain='my.irancell.ir my.mci.ir login.tci.ir local.tci.ir 192.168.1.1.mci 192.168.1.1.irancell'
uci commit dhcp
/etc/init.d/dnsmasq restart
echo -e "${GREEN}** DNS Rebind Fixed ** ${NC}"

rm -f /root/set.sh
/sbin/reload_config
echo -e "${CYAN}** Installation Completed ** ${NC}"

# Set Wifi
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
echo -e "${GREEN}** Wifi Configured ** ${NC}"

# Set Root Password
(echo "123456789"; echo "123456789") | passwd root >/dev/null 2>&1 || sed -i '/^root:/s|:[^:]*|:$5$S5bxda0buJo3RfO4$soovbPY4JGEbfMmggEPdo9mW/1qkTaAgVn9bbAfJeD7|' /etc/shadow
echo -e "${CYAN}** Root password is set: 123456789 ** ${NC}"

# Reboot or Exit
while true; do
    printf "${YELLOW}Press [r] to reboot or [e] to exit: ${NC}"
    read -rsn1 input
    case "$input" in
        r|R)
            echo -e "${GREEN}\nRebooting system...${NC}"
            reboot
            exit 0
            ;;
        e|E)
            echo -e "${RED}\nExiting script.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}\nInvalid choice! Press 'r' or 'e'.${NC}"
            sleep 1
            ;;
    esac
done
