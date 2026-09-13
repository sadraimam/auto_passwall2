#!/bin/sh

PACKAGE_MANAGER=""
PACKAGE_TYPE=""
REPO_URL="https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall2/releases"
BASE_DOWNLOAD_URL="https://github.com/Openwrt-Passwall/openwrt-passwall2/releases/download"
MIRROR_API_URL="https://scorpian.ir/api/repos/Openwrt-Passwall/openwrt-passwall2/releases"
MIRROR_ASSET_BASE_URL="https://scorpian.ir/proxy/asset/Openwrt-Passwall/openwrt-passwall2"
MIRROR_XRAY_API_URL="https://scorpian.ir/api/repos/XTLS/Xray-core/releases"
MIRROR_XRAY_ASSET_BASE_URL="https://scorpian.ir/proxy/asset/XTLS/Xray-core"
MIRROR_SINGBOX_API_URL="https://scorpian.ir/api/repos/sagernet/sing-box/releases"
MIRROR_SINGBOX_ASSET_BASE_URL="https://scorpian.ir/proxy/asset/sagernet/sing-box"
TEMP_DIR="/tmp/passwall2_update"
CONFIG_DIR="/etc/config"
BACKUP_SUFFIX=$(date +%Y%m%d)
MIN_SPACE_KB=20480

trap 'rm -rf "$TEMP_DIR" /tmp/passwall2-*.XXXXXX /tmp/passwall2-* 2>/dev/null' EXIT INT TERM

FEED_BASE_URL="https://master.dl.sourceforge.net/project/openwrt-passwall-build"
FEED_NAMES="passwall_luci passwall_packages passwall2"
FEED_RUNTIME_PACKAGES="xray-core sing-box geoview v2ray-geoip v2ray-geosite tcping"
FEED_RUNTIME_PACKAGES_FULL="xray-core sing-box chinadns-ng geoview shadowsocks-rust shadowsocksr-libev simple-obfs v2ray-plugin v2ray-geoip v2ray-geosite tcping haproxy microsocks"
FEED_RUNTIME_PACKAGES_SINGBOX="sing-box geoview v2ray-geoip v2ray-geosite tcping"
FEED_RUNTIME_PACKAGES_XRAY="xray-core geoview v2ray-geoip v2ray-geosite tcping"

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'

msg() {
    case "$1" in
        ok)    echo -e "${C_GREEN}[OK]${C_RESET} $2" ;;
        err)   echo -e "${C_RED}[ERROR]${C_RESET} $2"; exit 1 ;;
        warn)  echo -e "${C_YELLOW}[WARN]${C_RESET} $2" ;;
        info)  echo -e "${C_CYAN}[INFO]${C_RESET} $2" ;;
        head)  echo -e "\n${C_BOLD}$2${C_RESET}" ;;
        *)     echo "$1" ;;
    esac
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_package_manager() {
    if command_exists apk; then
        PACKAGE_MANAGER="apk"
        PACKAGE_TYPE="apk"
    elif command_exists opkg; then
        PACKAGE_MANAGER="opkg"
        PACKAGE_TYPE="ipk"
    else
        msg err "No supported package manager found: need apk or opkg"
    fi
}

pkg_update() {
    case "$PACKAGE_MANAGER" in
        apk) apk update ;;
        opkg) opkg update ;;
    esac
}

pkg_install() {
    case "$PACKAGE_MANAGER" in
        apk) apk add --upgrade "$@" ;;
        opkg) opkg install "$@" ;;
    esac
}

pkg_install_feed() {
    case "$PACKAGE_MANAGER" in
        apk)
            if [ "$ALLOW_UNTRUSTED_FEEDS" = true ]; then
                apk add --upgrade --allow-untrusted "$@"
            else
                apk add --upgrade "$@"
            fi
            ;;
        opkg) opkg install "$@" ;;
    esac
}

pkg_update_feed() {
    local log_file="$1"

    if pkg_update >"$log_file" 2>&1; then
        return 0
    fi

    if [ "$PACKAGE_MANAGER" = "apk" ] && grep -q 'UNTRUSTED signature' "$log_file"; then
        cat "$log_file"
        msg warn "Passwall apk feed signature is not trusted by apk; retrying with --allow-untrusted"
        ALLOW_UNTRUSTED_FEEDS=true
        if apk update --allow-untrusted >"$log_file" 2>&1; then
            return 0
        fi
    fi

    if [ "$PACKAGE_MANAGER" = "apk" ] && apk search --allow-untrusted --from repositories --exact luci-app-passwall2 2>/dev/null | grep -q '^luci-app-passwall2-'; then
        msg warn "Using cached package indexes after failed refresh"
        ALLOW_UNTRUSTED_FEEDS=true
        return 0
    fi

    return 1
}

pkg_install_local() {
    case "$PACKAGE_MANAGER" in
        apk) apk add --allow-untrusted --force-reinstall "$1" ;;
        opkg) opkg install "$1" --force-reinstall ;;
    esac
}

pkg_remove() {
    case "$PACKAGE_MANAGER" in
        apk) apk del "$@" ;;
        opkg) opkg remove "$@" ;;
    esac
}

pkg_remove_force() {
    case "$PACKAGE_MANAGER" in
        apk) apk del "$@" ;;
        opkg) opkg remove "$@" --force-depends ;;
    esac
}

ensure_direct_resolver() {
    [ -f /tmp/resolv.conf ] || return 0

    local has_loopback=false
    local has_direct=false
    local key value

    while read -r key value _; do
        [ "$key" = "nameserver" ] || continue
        case "$value" in
            127.*|::1) has_loopback=true ;;
            *) has_direct=true ;;
        esac
    done < /tmp/resolv.conf

    if [ "$has_direct" = false ]; then
        cp /tmp/resolv.conf /tmp/resolv.conf.passwall2.bak 2>/dev/null || true
        {
            grep '^search ' /tmp/resolv.conf 2>/dev/null            
            echo 'nameserver 8.8.8.8'
            echo 'nameserver 1.1.1.1'
            if [ "$IRAN_CONFIG" = true ]; then
                echo 'nameserver 5.200.200.200'
            fi
        } > /tmp/resolv.conf
        if [ "$has_loopback" = true ]; then
            msg warn "Using temporary direct resolvers while replacing dnsmasq"
        else
            msg warn "Using temporary direct resolvers because no system resolver is configured"
        fi
    elif [ "$IRAN_CONFIG" = true ] && ! grep -q 'nameserver 5.200.200.200' /tmp/resolv.conf 2>/dev/null; then
        sed -i '1inameserver 5.200.200.200' /tmp/resolv.conf 2>/dev/null || true
    fi
}

ensure_command() {
    local path="$1"
    local package="$2"

    [ -x "$path" ] && return 0
    msg warn "Installing $package"
    pkg_update && pkg_install "$package" || msg err "Failed to install $package"
}

pkg_is_installed() {
    case "$PACKAGE_MANAGER" in
        apk) apk info -e "$1" >/dev/null 2>&1 ;;
        opkg) opkg list-installed | grep -q "^$1 " ;;
    esac
}

pkg_list_installed() {
    case "$PACKAGE_MANAGER" in
        apk) apk info | sort -u ;;
        opkg) opkg list-installed | awk '{print $1}' | sort -u ;;
    esac
}

pkg_list_upgradable() {
    case "$PACKAGE_MANAGER" in
        apk)
            apk list --upgradable 2>/dev/null | awk '{print $1}' | sed 's/-[0-9][^-[:space:]]*-r[0-9].*$//' | sort -u
            ;;
        opkg) opkg list-upgradable | awk '{print $1}' | sort -u ;;
    esac
}

pkg_available() {
    case "$PACKAGE_MANAGER" in
        apk)
            if [ "$ALLOW_UNTRUSTED_FEEDS" = true ]; then
                apk search --allow-untrusted --from repositories --exact "$1" 2>/dev/null | grep -q "^$1-"
            else
                apk search --from repositories --exact "$1" 2>/dev/null | grep -q "^$1-"
            fi
            ;;
        opkg) opkg list "$1" 2>/dev/null | grep -q "^$1 -" ;;
    esac
}

prompt_continue_luci_or_exit() {
    local reason="$1"
    [ -n "$reason" ] && msg warn "$reason"
    while true; do
        printf "${C_YELLOW}Press [c] to continue with installation without runtime packages (luci-only) or [e] to exit: ${C_RESET}"
        read -rsn1 input
        echo
        case "$input" in
            c|C)
                ONLY_LUCI=true
                FEED_RUNTIME_PACKAGES=""
                msg info "Continuing with LuCI-only installation..."
                return 0
                ;;
            e|E)
                msg err "Installation aborted."
                ;;
            *)
                msg warn "Invalid choice! Press 'c' or 'e'"
                ;;
        esac
    done
}

ensure_feed_packages_available() {
    local missing=""
    local package=""

    if ! pkg_available luci-app-passwall2; then
        msg err "Required package luci-app-passwall2 is unavailable in feeds. Use --github or retry after feed refresh works."
    fi

    [ "$ONLY_LUCI" = true ] && return 0

    for package in $FEED_RUNTIME_PACKAGES; do
        if ! pkg_available "$package"; then
            missing="$missing $package"
        fi
    done

    missing=$(echo "$missing" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$missing" ]; then
        prompt_continue_luci_or_exit "Some feed packages are unavailable: $missing"
    fi
}

get_apk_feed_version() {
    local package="$1"

    apk --allow-untrusted policy "$package" 2>/dev/null | awk -v feed_base="$FEED_BASE_URL" '
        $1 ~ /:$/ {
            version=$1
            sub(/:$/, "", version)
            next
        }
        index($0, feed_base) && version != "" {
            print version
            exit
        }
    '
}

get_feed_install_args() {
    local packages="$1"
    local args=""
    local package=""
    local version=""

    case "$PACKAGE_MANAGER" in
        apk)
            for package in $packages; do
                version=$(get_apk_feed_version "$package")

                if [ -n "$version" ]; then
                    args="$args $package=$version"
                else
                    args="$args $package"
                fi
            done
            ;;
        opkg) args="$packages" ;;
    esac

    echo "$args" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

install_available_feed_packages() {
    local packages="$1"
    local available=""
    local package=""
    local install_args=""

    for package in $packages; do
        if pkg_available "$package"; then
            available="$available $package"
        else
            msg warn "Package not available in feeds: $package"
        fi
    done

    available=$(echo "$available" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$available" ] || return 0

    install_args=$(get_feed_install_args "$available")
    msg info "Installing: $install_args"
    pkg_install_feed $install_args
}

ensure_dnsmasq_full() {
    msg info "Checking dnsmasq-full"
    if pkg_is_installed dnsmasq-full; then
        msg ok "dnsmasq-full already installed"
        return 0
    fi

    ensure_direct_resolver
    case "$PACKAGE_MANAGER" in
        opkg)
            if pkg_is_installed dnsmasq; then
                msg info "Removing dnsmasq"
                pkg_remove dnsmasq || msg err "Failed to remove dnsmasq"
            fi
            ;;
    esac

    msg info "Installing dnsmasq-full"
    pkg_install dnsmasq-full || msg err "Failed to install dnsmasq-full"
    msg ok "dnsmasq-full installed"

    if [ -x /etc/init.d/dnsmasq ]; then
        /etc/init.d/dnsmasq restart >/dev/null 2>&1 || msg warn "dnsmasq restart failed; check DNS manually"
    fi
}

list_installed_named_packages() {
    local packages="$1"
    local installed=""
    local package=""

    for package in $packages; do
        if pkg_is_installed "$package"; then
            installed="$installed $package"
        fi
    done

    echo "$installed" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

pkg_print_architectures() {
    case "$PACKAGE_MANAGER" in
        apk)
            get_architecture
            ;;
        opkg)
            opkg print-architecture | awk '{print $2}' | awk '{a[NR]=$0} END {for(i=NR;i>0;i--) print a[i]}'
            ;;
    esac
}

get_local_package_name() {
    local file="$1"

    case "$PACKAGE_TYPE" in
        apk) basename "$file" ".$PACKAGE_TYPE" | sed 's/-[0-9][^-[:space:]]*-r[0-9].*$//' ;;
        ipk) basename "$file" ".$PACKAGE_TYPE" | cut -d'_' -f1 ;;
    esac
}

get_feed_key_url() {
    case "$PACKAGE_MANAGER" in
        apk) echo "${FEED_BASE_URL}/apk.pub" ;;
        opkg) echo "${FEED_BASE_URL}/ipk.pub" ;;
    esac
}

download_file() {
    local url="$1"
    local output="$2"

    curl -s -L --fail --retry 3 --connect-timeout 20 -o "$output" "$url"
}

install_feed_key() {
    local key_file=""
    local key_url=""

    key_url=$(get_feed_key_url)
    case "$PACKAGE_MANAGER" in
        apk)
            key_file="/etc/apk/keys/openwrt-passwall-build.pub"
            if [ -s "$key_file" ]; then
                msg ok "Feed key already exists"
                return 0
            fi

            if ! download_file "$key_url" /tmp/passwall.pub && \
               ! download_file "https://sourceforge.net/projects/openwrt-passwall-build/files/apk.pub/download" /tmp/passwall.pub; then
                msg warn "Failed to download feed key. Skipping feed key and continuing with installation..."
                rm -f /tmp/passwall.pub 2>/dev/null
                return 0
            fi
            mkdir -p /etc/apk/keys 2>/dev/null
            if cp /tmp/passwall.pub "$key_file" 2>/dev/null; then
                msg ok "Feed key added"
            else
                msg warn "Failed to save feed key to $key_file; continuing..."
            fi
            ;;
        opkg)
            if ! download_file "$key_url" /tmp/passwall.pub && \
               ! download_file "https://sourceforge.net/projects/openwrt-passwall-build/files/ipk.pub/download" /tmp/passwall.pub; then
                msg warn "Failed to download feed key. Skipping feed key and continuing with installation..."
                rm -f /tmp/passwall.pub 2>/dev/null
                return 0
            fi
            if opkg-key add /tmp/passwall.pub >/dev/null 2>&1; then
                msg ok "Feed key added"
            else
                msg warn "Failed to add feed key with opkg-key; continuing..."
            fi
            ;;
    esac

    rm -f /tmp/passwall.pub 2>/dev/null
    return 0
}

get_feed_url() {
    local feed="$1"

    case "$PACKAGE_MANAGER" in
        apk) echo "${FEED_BASE_URL}/releases/packages-${RELEASE_VER}/${ARCH}/${feed}/packages.adb" ;;
        opkg) echo "${FEED_BASE_URL}/releases/packages-${RELEASE_VER}/${ARCH}/${feed}" ;;
    esac
}

configure_feeds() {
    msg head "Feed configuration"

    if [ -z "$RELEASE_VER" ]; then
        msg warn "OpenWrt release not detected; skipping feed configuration."
        return 0
    fi

    msg info "Configuring SourceForge feeds"
    msg info "Downloading feed key"
    install_feed_key

    msg info "Writing feed entries"
    case "$PACKAGE_MANAGER" in
        apk)
            mkdir -p /etc/apk/repositories.d 2>/dev/null
            FEED_CONFIG="/etc/apk/repositories.d/customfeeds.list"
            [ -f "$FEED_CONFIG" ] && cp "$FEED_CONFIG" "$FEED_CONFIG.bak"
            > "$FEED_CONFIG"
            ;;
        opkg)
            FEED_CONFIG="/etc/opkg/customfeeds.conf"
            [ -f "$FEED_CONFIG" ] && cp "$FEED_CONFIG" "$FEED_CONFIG.bak"
            > "$FEED_CONFIG"
            ;;
    esac

    for feed in $FEED_NAMES; do
        FEED_URL=$(get_feed_url "$feed")
        case "$PACKAGE_MANAGER" in
            apk) echo "$FEED_URL" >> "$FEED_CONFIG" ;;
            opkg) echo "src/gz $feed $FEED_URL" >> "$FEED_CONFIG" ;;
        esac
        msg ok "Added feed: $feed"
    done
}

get_architecture() {
    local arch=""

    if [ -r /etc/openwrt_release ]; then
        arch=$(. /etc/openwrt_release; echo "$DISTRIB_ARCH")
    fi

    if [ -n "$arch" ]; then
        echo "$arch"
        return
    fi

    if [ "$PACKAGE_MANAGER" = "opkg" ]; then
        arch=$(opkg print-architecture 2>/dev/null | awk '{print $2}' | tail -1)
    elif [ "$PACKAGE_MANAGER" = "apk" ]; then
        arch=$(apk --print-arch 2>/dev/null)
    fi

    echo "$arch"
}

get_release_version() {
    if [ -r /etc/openwrt_release ]; then
        . /etc/openwrt_release
        case "$DISTRIB_RELEASE" in
            *.*.*) echo "${DISTRIB_RELEASE%.*}" ;;
            *) echo "$DISTRIB_RELEASE" ;;
        esac
    fi
}

list_feed_packages() {
    case "$PACKAGE_MANAGER" in
        apk)
            apk search 2>/dev/null | awk '{print $1}' | sed 's/-[0-9][^-[:space:]]*-r[0-9].*$//' | grep -E '^(luci-app-passwall2|luci-i18n-passwall2-)' | sort -u
            ;;
        opkg)
            for feed_file in /var/opkg-lists/passwall_luci /var/opkg-lists/passwall_packages /var/opkg-lists/passwall2; do
                [ -f "$feed_file" ] || continue
                gzip -dc "$feed_file" 2>/dev/null || cat "$feed_file" 2>/dev/null
            done | awk '/^Package: / {print $2}' | sort -u
            ;;
    esac
}

list_installed_packages() {
    pkg_list_installed
}

list_upgradable_packages() {
    pkg_list_upgradable
}

print_pkg_warnings() {
    local log_file="$1"

    if [ "$PACKAGE_MANAGER" = "opkg" ] && grep -qE 'resolve_conffiles:|^Collected errors:$' "$log_file"; then
        msg warn "opkg reported warnings"
        grep -E 'resolve_conffiles:|^Collected errors:$|^ \* ' "$log_file" | sed 's/^/  /'
    fi
}

print_space_hint() {
    local log_file="$1"

    if grep -qiE '(space|No space left|disk full|available on filesystem|needs|verify_pkg_installable)' "$log_file"; then
        msg warn "Suggestion: try --clean to free space"
    fi
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        msg err "This script must be run as root. Exiting."
    else
        msg ok "Running as root..."
        sleep 2
    fi

    if grep -q SNAPSHOT /etc/openwrt_release 2>/dev/null; then
        msg warn "SNAPSHOT Version Detected!"
        msg err "Snapshot builds are not supported."
    fi
}

initialize_network() {
    msg info "Initializing Network..."
    uci del network.wan.dns 2>/dev/null
    uci set network.wan.peerdns="0"
    uci add_list network.wan.dns="8.8.4.4"
    uci add_list network.wan.dns="8.8.8.8"
    uci add_list network.wan.dns="1.0.0.1"
    uci add_list network.wan.dns="1.1.1.1"
    if [ "$IRAN_CONFIG" = true ]; then
        uci add_list network.wan.dns="5.200.200.200"
    fi
    uci del network.wan6.dns 2>/dev/null
    uci set network.wan6.peerdns="0"
    uci add_list network.wan6.dns="2001:4860:4860::8844"
    uci add_list network.wan6.dns="2001:4860:4860::8888"
    uci add_list network.wan6.dns="2606:4700:4700::1001"
    uci add_list network.wan6.dns="2606:4700:4700::1111"
    uci commit network
    /sbin/reload_config >/dev/null 
    if [ "$IRAN_CONFIG" = true ]; then
        [ -f /tmp/resolv.conf ] && sed -i '1inameserver 5.200.200.200' /tmp/resolv.conf 2>/dev/null || true
        msg ok "Network Initialized with local Iran DNS (5.200.200.200)!"
    else
        msg ok "Network Initialized!"
    fi
}

initialize_time_date() {
    msg info "Syncing time with NTP..."
    ntpd -n -q -p 162.159.200.1 -p 216.239.35.0 -p 0.openwrt.pool.ntp.org || msg warn "NTP sync failed."
    msg ok "Current system time: $(date)"
}

apply_iran_config() {
    msg head "Applying Iran Specific Configurations"
    
    msg info "Setting Tehran Timezone..."
    uci set system.@system[0].zonename='Asia/Tehran'
    uci set system.@system[0].timezone='<+0330>-3:30'
    uci commit system
    /etc/init.d/sysntpd restart
    msg ok "Timezone set to Tehran."
    
    if ! uci get network.wan.dns 2>/dev/null | grep -q '5.200.200.200'; then
        msg info "Adding 5.200.200.200 to WAN DNS..."
        uci add_list network.wan.dns="5.200.200.200"
        uci commit network
        /sbin/reload_config >/dev/null
        msg ok "Iran DNS Configured."
    else
        msg ok "Iran DNS (5.200.200.200) already active in WAN."
    fi
    
    msg info "Applying DNS Rebind Fix..."
    uci set dhcp.@dnsmasq[0].rebind_domain='my.irancell.ir my.mci.ir login.tci.ir local.tci.ir 192.168.1.1.mci 192.168.1.1.irancell'
    uci commit dhcp
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
    msg ok "DNS Rebind Fixed."
    
    msg info "Patching Passwall Status Banner..."
    curl -s -L --fail -o /tmp/status.htm https://raw.githubusercontent.com/sadraimam/auto_passwall2/refs/heads/main/status.htm
    if [ -s /tmp/status.htm ]; then
        mkdir -p /usr/lib/lua/luci/view/passwall2/global/
        mkdir -p /usr/lib64/lua/luci/view/passwall2/global/
        cp /tmp/status.htm /usr/lib/lua/luci/view/passwall2/global/status.htm 2>/dev/null || true
        cp /tmp/status.htm /usr/lib64/lua/luci/view/passwall2/global/status.htm 2>/dev/null || true
        mkdir -p /lib/upgrade/keep.d/
        grep -q "/usr/lib/lua/luci/view/passwall2/global/status.htm" /lib/upgrade/keep.d/luci-app-passwall2 2>/dev/null || echo "/usr/lib/lua/luci/view/passwall2/global/status.htm" >> /lib/upgrade/keep.d/luci-app-passwall2
        rm -f /tmp/status.htm
        msg ok "Passwall Status Banner Patched."
    else
        msg err "Failed to download status banner patch."
    fi
}

setup_root_wifi() {
    msg head "Root and WiFi Setup"
    
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
    msg ok "Wifi Configured"
    msg warn "Wifi password is set: 123456789"

    (echo "123456789"; echo "123456789") | passwd root >/dev/null 2>&1 || sed -i '/^root:/s|:[^:]*|:$5$S5bxda0buJo3RfO4$soovbPY4JGEbfMmggEPdo9mW/1qkTaAgVn9bbAfJeD7|' /etc/shadow
    msg warn "Root password is set: 123456789"
}

setup_reset_button() {
    msg warn "Configuring hardware reset button..."
    
    cat << 'EOF' > /etc/rc.button/reset
#!/bin/sh

# Only execute when the button is released
[ "${ACTION}" = "released" ] || exit 0

. /lib/functions.sh

logger "Reset button pressed for ${SEEN} seconds"

# If held for 5 seconds or longer, clear root password
if [ "${SEEN}" -ge 5 ]; then
    logger "Reset button action: Removing root password"
    passwd -d root
    sync
elif [ "${SEEN}" -ge 1 ]; then
    logger "Reset button action: Rebooting device"
    sync
    reboot
fi

return 0
EOF

    chmod +x /etc/rc.button/reset
    msg ok "Reset button modified: 5s hold clears root password, 1s hold reboots."
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Description:"
    echo "  Install Passwall2 from SourceForge feed (default), GitHub releases, or Iranian mirror."
    echo "  Automatically uses apk or opkg, depending on availability."
    echo ""
    echo "Options:"
    echo "  -g, --github [VER]         Install from GitHub releases. Optional version (e.g., v2.0.1)."
    echo "  -gm, --github-mirror [VER] Install from Iranian GitHub mirror (scorpian.ir). Optional version."
    echo "  -c, --clean                Clean install (remove old packages first)."
    echo "  -l, --only-luci            Install only LuCI interface (skip binaries)."
    echo "  -f, --full                 Full feature install (includes chinadns-ng hysteria haproxy microsocks naiveproxy)."
    echo "  -s, --singbox              Minimal install with only sing-box core (no extra cores or features)."
    echo "  -x, --xray                 Minimal install with only xray core (no extra cores or features)."
    echo "  -i, --iran                 Apply Iran specific configurations."
    echo "  -rw, --root-wifi           Root and WiFi setup (sets passwords to 123456789)."
    echo "  -rb, --reset-button        Modify reset button to clear root password (5s press) instead of factory reset."
    echo "  -h, --help                 Show this help message."
    echo ""
    echo "Examples:"
    echo "  $0                         Install latest from SourceForge feed with both cores (default)"
    echo "  $0 -x                      Install latest from SourceForge feed with xray core only"
    echo "  $0 -s                      Install latest from SourceForge feed with sing-box core only"
    echo "  $0 -g                      Install latest from GitHub"
    echo "  $0 -g -x                   Install latest from GitHub with xray core only"
    echo "  $0 -gm                     Install latest from Iranian GitHub mirror (scorpian.ir)"
    echo "  $0 -gm -x                  Install latest from Iranian GitHub mirror with xray core only"
    echo "  $0 -g 26.8.17-1            Install specific version from GitHub"
    echo "  $0 -g -c                   Clean install from GitHub (latest)"
    echo "  $0 -gm -c                  Clean install from Iranian GitHub mirror (latest)"
    echo ""
    exit 0
}

GITHUB_MODE=false
MIRROR_MODE=false
TARGET_VERSION=""
CLEAN_INSTALL=false
ONLY_LUCI=false
ALLOW_UNTRUSTED_FEEDS=false
ROOT_WIFI=false
IRAN_CONFIG=false
FULL_FEATURE=false
SINGBOX_ONLY=false
XRAY_ONLY=false
MOD_RESET_BTN=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) show_help ;;
        -g|--github)
            GITHUB_MODE=true
            shift
            case "$1" in
                ""|-*) ;;
                *) TARGET_VERSION="$1"; shift ;;
            esac
            ;;
        -gm|--github-mirror|-m|--mirror)
            MIRROR_MODE=true
            shift
            case "$1" in
                ""|-*) ;;
                *) TARGET_VERSION="$1"; shift ;;
            esac
            ;;
        -c|--clean) CLEAN_INSTALL=true; shift ;;
        -l|--only-luci) ONLY_LUCI=true; shift ;;
        -f|--full) FULL_FEATURE=true; shift ;;
        -s|--singbox) SINGBOX_ONLY=true; shift ;;
        -x|--xray) XRAY_ONLY=true; shift ;;
        -rw|--root-wifi) ROOT_WIFI=true; shift ;;
        -i|--iran) IRAN_CONFIG=true; shift ;;
        -rb|--reset-button) MOD_RESET_BTN=true; shift ;;
        -*) msg err "Unknown option: $1" ;;
        *) msg err "Unknown argument: $1. Use --github or --github-mirror flag to specify version." ;;
    esac
done

count_profiles=0
[ "$FULL_FEATURE" = true ] && count_profiles=$((count_profiles + 1))
[ "$SINGBOX_ONLY" = true ] && count_profiles=$((count_profiles + 1))
[ "$XRAY_ONLY" = true ] && count_profiles=$((count_profiles + 1))

if [ "$count_profiles" -gt 1 ]; then
    echo -e "${C_RED}[ERROR]${C_RESET} Options --full, --singbox, and --xray cannot be used together."
    while true; do
        printf "${C_YELLOW}Choose installation profile: (f)ull feature, (s)ingbox only, or (x)ray only? [f/s/x]: ${C_RESET}"
        read -rsn1 input
        echo
        case "$input" in
            f|F)
                FULL_FEATURE=true
                SINGBOX_ONLY=false
                XRAY_ONLY=false
                msg info "Proceeding with Full Feature installation."
                break
                ;;
            s|S)
                FULL_FEATURE=false
                SINGBOX_ONLY=true
                XRAY_ONLY=false
                msg info "Proceeding with minimal Sing-box installation."
                break
                ;;
            x|X)
                FULL_FEATURE=false
                SINGBOX_ONLY=false
                XRAY_ONLY=true
                msg info "Proceeding with minimal Xray installation."
                break
                ;;
            *)
                msg warn "Invalid choice! Press 'f', 's', or 'x'"
                ;;
        esac
    done
fi

if [ "$FULL_FEATURE" = true ]; then
    FEED_RUNTIME_PACKAGES="$FEED_RUNTIME_PACKAGES_FULL"
elif [ "$XRAY_ONLY" = true ]; then
    FEED_RUNTIME_PACKAGES="$FEED_RUNTIME_PACKAGES_XRAY"
elif [ "$SINGBOX_ONLY" = true ]; then
    FEED_RUNTIME_PACKAGES="$FEED_RUNTIME_PACKAGES_SINGBOX"
else
    FEED_RUNTIME_PACKAGES="$FEED_RUNTIME_PACKAGES"
fi

msg head "System checks"

check_root

detect_package_manager
msg ok "Package manager: ${C_BOLD}$PACKAGE_MANAGER${C_RESET}"

initialize_network

msg info "Checking connectivity"
if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 5 5.200.200.200 >/dev/null 2>&1; then
    msg ok "Connectivity confirmed"
else
    msg err "No internet connection"
fi

initialize_time_date

ensure_direct_resolver

ensure_command /usr/bin/unzip unzip
ensure_command /usr/bin/curl curl
ensure_command /usr/bin/jsonfilter jsonfilter

DEVICE_MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "Unknown Device")
msg info "Device: ${C_BOLD}$DEVICE_MODEL${C_RESET}"

FREE_SPACE=$(df -k /tmp | awk 'NR==2 {print $4}')
if [ "$FREE_SPACE" -lt "$MIN_SPACE_KB" ]; then
    msg err "Not enough space in /tmp: need ${MIN_SPACE_KB} KB, found ${FREE_SPACE} KB"
else
    msg ok "Space available in /tmp: ${FREE_SPACE} KB"
fi

msg head "Dependencies"

ensure_dnsmasq_full

msg info "Checking kernel modules"
for module in kmod-nft-tproxy kmod-nft-socket; do
    if ! pkg_is_installed "$module"; then
        msg info "Installing $module"
        pkg_install "$module" || msg err "Failed to install $module"
        msg ok "$module installed"
    else
        msg ok "$module already installed"
    fi
done

msg head "Platform"

ARCH=$(get_architecture)
if [ -z "$ARCH" ]; then
    msg err "Failed to detect architecture"
fi
msg ok "Architecture: ${C_BOLD}$ARCH${C_RESET}"

RELEASE_VER=$(get_release_version)
if [ -n "$RELEASE_VER" ]; then
    msg ok "OpenWrt release: ${C_BOLD}$RELEASE_VER${C_RESET}"
fi

msg head "Preparation"
rm -rf "$TEMP_DIR" && mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR" || msg err "Failed to prepare temp directory"

for config_file in "$CONFIG_DIR"/passwall2*; do
    [ -f "$config_file" ] || continue
    case "$config_file" in
        *.bak*) continue ;;
    esac
    BACKUP_FILE="$config_file-$BACKUP_SUFFIX.bak"
    cp "$config_file" "$BACKUP_FILE"
    msg ok "Backed up config: $BACKUP_FILE"
done

get_xray_arch() {
    case "$ARCH" in
        x86_64) echo "64" ;;
        *i386*|*i486*|*i686*) echo "32" ;;
        aarch64*) echo "arm64-v8a" ;;
        arm_cortex-a7*|arm_cortex-a15*|arm_cortex-a9*|arm*v7*) echo "arm32-v7a" ;;
        arm*) echo "arm32-v5" ;;
        mipsel*) echo "mips32le" ;;
        mips*) echo "mips32" ;;
        riscv64*) echo "riscv64" ;;
        *) echo "" ;;
    esac
}

get_singbox_arch() {
    case "$ARCH" in
        x86_64) echo "amd64" ;;
        *i386*|*i486*|*i686*) echo "386" ;;
        aarch64*) echo "arm64" ;;
        arm_cortex-a7*|arm_cortex-a15*|arm_cortex-a9*|arm*v7*) echo "armv7" ;;
        mipsel*) echo "mipsle" ;;
        mips*) echo "mips" ;;
        riscv64*) echo "riscv64" ;;
        *) echo "" ;;
    esac
}

install_xray_from_github() {
    local xray_arch
    xray_arch=$(get_xray_arch)
    if [ -z "$xray_arch" ]; then
        msg warn "Unsupported architecture for official Xray binary: $ARCH"
        return 1
    fi

    local zip_name="Xray-linux-${xray_arch}.zip"
    local tmp_zip="/tmp/${zip_name}"

    # Tier A: Try Iranian GitHub mirror (scorpian.ir) if in mirror mode
    if [ "$MIRROR_MODE" = true ]; then
        msg info "Attempting to install xray-core from Iranian mirror (scorpian.ir)..."
        local xray_meta="/tmp/passwall2-xray-mirror.json"
        if curl -s -L --fail --connect-timeout 15 "$MIRROR_XRAY_API_URL" > "$xray_meta" 2>/dev/null && [ -s "$xray_meta" ]; then
            local asset_id=""
            if command_exists jsonfilter; then
                asset_id=$(jsonfilter -i "$xray_meta" -e "@.releases[0].assets[@.name='$zip_name'].id" 2>/dev/null)
            fi
            if [ -z "$asset_id" ]; then
                local xobj
                xobj=$(grep -o '{"url"[^}]*"name":"'"$zip_name"'"[^}]*}' "$xray_meta" | head -n 1)
                asset_id=$(echo "$xobj" | grep -o '"id":[0-9]*' | head -n 1 | cut -d: -f2)
            fi
            rm -f "$xray_meta" 2>/dev/null

            if [ -n "$asset_id" ]; then
                local mirror_url="${MIRROR_XRAY_ASSET_BASE_URL}/${asset_id}"
                msg info "Downloading ${zip_name} from mirror (asset ID: ${asset_id})..."
                if download_file "$mirror_url" "$tmp_zip" && [ -s "$tmp_zip" ]; then
                    mkdir -p /tmp/xray_extract
                    unzip -q -o "$tmp_zip" -d /tmp/xray_extract/ 2>/dev/null
                    if [ -f /tmp/xray_extract/xray ]; then
                        cp -f /tmp/xray_extract/xray /usr/bin/xray
                        chmod +x /usr/bin/xray
                        mkdir -p /usr/share/v2ray /usr/share/xray 2>/dev/null
                        [ -f /tmp/xray_extract/geoip.dat ] && cp -f /tmp/xray_extract/geoip.dat /usr/share/v2ray/ 2>/dev/null && cp -f /tmp/xray_extract/geoip.dat /usr/share/xray/ 2>/dev/null
                        [ -f /tmp/xray_extract/geosite.dat ] && cp -f /tmp/xray_extract/geosite.dat /usr/share/v2ray/ 2>/dev/null && cp -f /tmp/xray_extract/geosite.dat /usr/share/xray/ 2>/dev/null
                    fi
                    rm -rf /tmp/xray_extract "$tmp_zip" 2>/dev/null
                    if [ -x /usr/bin/xray ]; then
                        msg ok "xray-core binary installed successfully from mirror: /usr/bin/xray"
                        return 0
                    fi
                fi
                rm -f "$tmp_zip" 2>/dev/null
                msg warn "Mirror download for xray-core failed. Falling back to GitHub..."
            fi
        else
            rm -f "$xray_meta" 2>/dev/null
            msg warn "Failed to fetch xray-core metadata from mirror. Falling back to GitHub..."
        fi
    fi

    # Tier B: Official GitHub release (direct / ghfast / ghproxy)
    msg info "Attempting to install xray-core from official GitHub release..."
    local tag
    tag=$(curl -s --fail https://api.github.com/repos/XTLS/Xray-core/releases/latest 2>/dev/null | jsonfilter -e '@.tag_name' 2>/dev/null)
    if [ -z "$tag" ]; then
        tag=$(curl -s -I https://github.com/XTLS/Xray-core/releases/latest 2>/dev/null | grep -i '^location:' | sed 's/.*tag\///' | tr -d '\r\n')
    fi
    [ -n "$tag" ] || tag="v25.2.21"

    local dl_url="https://github.com/XTLS/Xray-core/releases/download/${tag}/${zip_name}"

    msg info "Downloading ${zip_name} (${tag})..."
    if download_file "$dl_url" "$tmp_zip" || \
       download_file "https://ghfast.top/${dl_url}" "$tmp_zip" || \
       download_file "https://ghproxy.net/${dl_url}" "$tmp_zip"; then
        if [ -s "$tmp_zip" ]; then
            mkdir -p /tmp/xray_extract
            unzip -q -o "$tmp_zip" -d /tmp/xray_extract/ 2>/dev/null
            if [ -f /tmp/xray_extract/xray ]; then
                cp -f /tmp/xray_extract/xray /usr/bin/xray
                chmod +x /usr/bin/xray
                mkdir -p /usr/share/v2ray /usr/share/xray 2>/dev/null
                [ -f /tmp/xray_extract/geoip.dat ] && cp -f /tmp/xray_extract/geoip.dat /usr/share/v2ray/ 2>/dev/null && cp -f /tmp/xray_extract/geoip.dat /usr/share/xray/ 2>/dev/null
                [ -f /tmp/xray_extract/geosite.dat ] && cp -f /tmp/xray_extract/geosite.dat /usr/share/v2ray/ 2>/dev/null && cp -f /tmp/xray_extract/geosite.dat /usr/share/xray/ 2>/dev/null
            fi
            rm -rf /tmp/xray_extract "$tmp_zip" 2>/dev/null
            if [ -x /usr/bin/xray ]; then
                msg ok "xray-core binary installed successfully: /usr/bin/xray"
                return 0
            fi
        fi
    fi

    rm -rf /tmp/xray_extract "$tmp_zip" 2>/dev/null
    msg warn "Failed to install official xray-core binary from GitHub"
    return 1
}

install_singbox_from_github() {
    local sb_arch
    sb_arch=$(get_singbox_arch)
    if [ -z "$sb_arch" ]; then
        msg warn "Unsupported architecture for official sing-box binary: $ARCH"
        return 1
    fi

    local tmp_tar="/tmp/sing-box-download.tar.gz"

    # Tier A: Try Iranian GitHub mirror (scorpian.ir) if in mirror mode
    if [ "$MIRROR_MODE" = true ]; then
        msg info "Attempting to install sing-box from Iranian mirror (scorpian.ir)..."
        local sb_meta="/tmp/passwall2-singbox-mirror.json"
        if curl -s -L --fail --connect-timeout 15 "$MIRROR_SINGBOX_API_URL" > "$sb_meta" 2>/dev/null && [ -s "$sb_meta" ]; then
            local sb_obj=""
            # Prioritize stable release asset (sing-box-1.x.x-linux-ARCH.tar.gz)
            sb_obj=$(grep -o '{"url"[^}]*"name":"sing-box-[0-9.]*-linux-'"$sb_arch"'\.tar\.gz"[^}]*}' "$sb_meta" | head -n 1)
            # Fallback to any matching release asset
            [ -z "$sb_obj" ] && sb_obj=$(grep -o '{"url"[^}]*"name":"sing-box-[^"]*-linux-'"$sb_arch"'\.tar\.gz"[^}]*}' "$sb_meta" | head -n 1)

            local asset_id="" tar_name=""
            if [ -n "$sb_obj" ]; then
                asset_id=$(echo "$sb_obj" | grep -o '"id":[0-9]*' | head -n 1 | cut -d: -f2)
                tar_name=$(echo "$sb_obj" | grep -o '"name":"[^"]*"' | head -n 1 | cut -d'"' -f4)
            fi
            rm -f "$sb_meta" 2>/dev/null

            if [ -n "$asset_id" ]; then
                [ -n "$tar_name" ] || tar_name="sing-box-linux-${sb_arch}.tar.gz"
                tmp_tar="/tmp/${tar_name}"
                local mirror_url="${MIRROR_SINGBOX_ASSET_BASE_URL}/${asset_id}"
                msg info "Downloading ${tar_name} from mirror (asset ID: ${asset_id})..."
                if download_file "$mirror_url" "$tmp_tar" && [ -s "$tmp_tar" ]; then
                    mkdir -p /tmp/sb_extract
                    tar -xzf "$tmp_tar" -C /tmp/sb_extract/ 2>/dev/null
                    if [ -f /tmp/sb_extract/*/sing-box ]; then
                        cp -f /tmp/sb_extract/*/sing-box /usr/bin/sing-box
                    elif [ -f /tmp/sb_extract/sing-box ]; then
                        cp -f /tmp/sb_extract/sing-box /usr/bin/sing-box
                    fi
                    chmod +x /usr/bin/sing-box 2>/dev/null
                    rm -rf /tmp/sb_extract "$tmp_tar" 2>/dev/null
                    if [ -x /usr/bin/sing-box ]; then
                        msg ok "sing-box binary installed successfully from mirror: /usr/bin/sing-box"
                        return 0
                    fi
                fi
                rm -rf /tmp/sb_extract "$tmp_tar" 2>/dev/null
                msg warn "Mirror download for sing-box failed. Falling back to GitHub..."
            fi
        else
            rm -f "$sb_meta" 2>/dev/null
            msg warn "Failed to fetch sing-box metadata from mirror. Falling back to GitHub..."
        fi
    fi

    # Tier B: Official GitHub release (direct / ghfast / ghproxy)
    msg info "Attempting to install sing-box from official GitHub release..."
    local tag
    tag=$(curl -s --fail https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null | jsonfilter -e '@.tag_name' 2>/dev/null)
    if [ -z "$tag" ]; then
        tag=$(curl -s -I https://github.com/SagerNet/sing-box/releases/latest 2>/dev/null | grep -i '^location:' | sed 's/.*tag\///' | tr -d '\r\n')
    fi
    [ -n "$tag" ] || tag="v1.11.4"

    local ver_clean="${tag#v}"
    local tar_name="sing-box-${ver_clean}-linux-${sb_arch}.tar.gz"
    local dl_url="https://github.com/SagerNet/sing-box/releases/download/${tag}/${tar_name}"
    tmp_tar="/tmp/${tar_name}"

    msg info "Downloading ${tar_name} (${tag})..."
    if download_file "$dl_url" "$tmp_tar" || \
       download_file "https://ghfast.top/${dl_url}" "$tmp_tar" || \
       download_file "https://ghproxy.net/${dl_url}" "$tmp_tar"; then
        if [ -s "$tmp_tar" ]; then
            mkdir -p /tmp/sb_extract
            tar -xzf "$tmp_tar" -C /tmp/sb_extract/ 2>/dev/null
            if [ -f /tmp/sb_extract/*/sing-box ]; then
                cp -f /tmp/sb_extract/*/sing-box /usr/bin/sing-box
            elif [ -f /tmp/sb_extract/sing-box ]; then
                cp -f /tmp/sb_extract/sing-box /usr/bin/sing-box
            fi
            chmod +x /usr/bin/sing-box 2>/dev/null
            rm -rf /tmp/sb_extract "$tmp_tar" 2>/dev/null
            if [ -x /usr/bin/sing-box ]; then
                msg ok "sing-box binary installed successfully: /usr/bin/sing-box"
                return 0
            fi
        fi
    fi

    rm -rf /tmp/sb_extract "$tmp_tar" 2>/dev/null
    msg warn "Failed to install official sing-box binary from GitHub"
    return 1
}

ensure_cores() {
    [ "$ONLY_LUCI" = true ] && return 0

    local wanted=""
    if [ "$XRAY_ONLY" = true ]; then
        wanted="xray-core"
    elif [ "$SINGBOX_ONLY" = true ]; then
        wanted="sing-box"
    else
        wanted="xray-core sing-box"
    fi

    msg head "Proxy cores verification"

    local core=""
    for core in $wanted; do
        local bin_name=""
        [ "$core" = "xray-core" ] && bin_name="xray"
        [ "$core" = "sing-box" ] && bin_name="sing-box"

        if [ -x "/usr/bin/$bin_name" ] || pkg_is_installed "$core"; then
            msg ok "$core is already installed"
            continue
        fi

        msg info "Installing $core..."
        ensure_direct_resolver

        # Tier 1: Try package manager from feeds
        local core_log
        core_log=$(mktemp /tmp/passwall2-core.XXXXXX 2>/dev/null) || core_log="/tmp/passwall2-core.log"
        if pkg_install "$core" >"$core_log" 2>&1 && [ -x "/usr/bin/$bin_name" ]; then
            rm -f "$core_log"
            msg ok "$core installed from package repository"
            continue
        fi
        rm -f "$core_log"

        # Tier 2: Fallback to Iranian mirror (if in mirror mode) or official GitHub binary
        if [ "$MIRROR_MODE" = true ]; then
            msg warn "$core package was not found in package repository. Trying Iranian mirror (scorpian.ir)..."
        else
            msg warn "$core package was not found in package repository. Trying official GitHub release..."
        fi
        if [ "$core" = "xray-core" ]; then
            install_xray_from_github
        elif [ "$core" = "sing-box" ]; then
            install_singbox_from_github
        fi
    done
}

install_from_feed() {
    msg head "Feed installation"

    if [ -z "$RELEASE_VER" ]; then
        msg err "OpenWrt release not detected"
    fi

    msg head "Package discovery"
    msg info "Checking installed Passwall packages"

    msg head "Install"
    msg info "Updating package lists"
    UPDATE_LOG=$(mktemp /tmp/passwall2-update.XXXXXX) || msg err "Failed to create temp file"
    if pkg_update_feed "$UPDATE_LOG"; then
        cat "$UPDATE_LOG"
        rm -f "$UPDATE_LOG"
    else
        cat "$UPDATE_LOG"
        rm -f "$UPDATE_LOG"
        msg err "Failed to update package lists"
    fi

    FEED_PACKAGES_FILE=$(mktemp /tmp/passwall2-feed-packages.XXXXXX) || msg err "Failed to create temp file"
    INSTALLED_PACKAGES_FILE=$(mktemp /tmp/passwall2-installed-packages.XXXXXX) || msg err "Failed to create temp file"
    UPGRADABLE_PACKAGES_FILE=$(mktemp /tmp/passwall2-upgradable-packages.XXXXXX) || msg err "Failed to create temp file"

    list_feed_packages > "$FEED_PACKAGES_FILE"
    list_installed_packages > "$INSTALLED_PACKAGES_FILE"
    list_upgradable_packages > "$UPGRADABLE_PACKAGES_FILE"

    ensure_feed_packages_available

    PASSWALL_INSTALLED_PACKAGES=$(grep -Fxf "$INSTALLED_PACKAGES_FILE" "$FEED_PACKAGES_FILE" | grep -vx "luci-app-passwall2" | grep -v "luci-i18n-passwall2-" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    PASSWALL_UPGRADABLE_PACKAGES=$(grep -Fxf "$UPGRADABLE_PACKAGES_FILE" "$FEED_PACKAGES_FILE" | grep -vx "luci-app-passwall2" | grep -v "luci-i18n-passwall2-" | tr '\n' ' ' | sed 's/[[:space:]]*$//')

    rm -f "$FEED_PACKAGES_FILE" "$INSTALLED_PACKAGES_FILE" "$UPGRADABLE_PACKAGES_FILE"

    if [ "$CLEAN_INSTALL" = true ]; then
        msg head "Cleanup"
        msg info "Removing existing Passwall installation"

        REMOVE_LOG=$(mktemp /tmp/passwall2-remove.XXXXXX) || msg err "Failed to create temp file"

        if pkg_is_installed luci-app-passwall2; then
            msg info "Removing luci-app-passwall2"
            if ! pkg_remove_force luci-app-passwall2 >"$REMOVE_LOG" 2>&1; then
                cat "$REMOVE_LOG"
                rm -f "$REMOVE_LOG"
                msg err "Failed to remove Passwall2"
            fi
        fi

        if [ -n "$PASSWALL_INSTALLED_PACKAGES" ]; then
            msg info "Removing: $PASSWALL_INSTALLED_PACKAGES"
            if ! pkg_remove_force $PASSWALL_INSTALLED_PACKAGES >"$REMOVE_LOG" 2>&1; then
                cat "$REMOVE_LOG"
                rm -f "$REMOVE_LOG"
                msg err "Failed to remove Passwall packages"
            fi
        else
            msg info "No additional installed Passwall feed packages to remove"
        fi

        if [ "$ONLY_LUCI" = false ] && [ -n "$FEED_RUNTIME_PACKAGES" ]; then
            RUNTIME_INSTALLED_PACKAGES=$(list_installed_named_packages "$FEED_RUNTIME_PACKAGES")
            if [ -n "$RUNTIME_INSTALLED_PACKAGES" ]; then
                msg info "Removing runtime packages: $RUNTIME_INSTALLED_PACKAGES"
                if ! pkg_remove_force $RUNTIME_INSTALLED_PACKAGES >"$REMOVE_LOG" 2>&1; then
                    cat "$REMOVE_LOG"
                    rm -f "$REMOVE_LOG"
                    msg err "Failed to remove Passwall runtime packages"
                fi
            else
                msg info "No installed Passwall runtime packages to remove"
            fi
        fi

        rm -f "$REMOVE_LOG"
        msg ok "Existing packages removed"
    fi

    msg head "Install"
    msg info "Installing Passwall2"
    INSTALL_LOG=$(mktemp /tmp/passwall2-install.XXXXXX) || msg err "Failed to create temp file"
    if pkg_install_feed luci-app-passwall2 >"$INSTALL_LOG" 2>&1; then
        cat "$INSTALL_LOG"
        print_pkg_warnings "$INSTALL_LOG"
        rm -f "$INSTALL_LOG"
        msg ok "Passwall2 installed"
    else
        cat "$INSTALL_LOG"
        print_space_hint "$INSTALL_LOG"
        rm -f "$INSTALL_LOG"
        msg err "Failed to install Passwall2"
    fi

    if [ "$ONLY_LUCI" = false ] && [ -n "$FEED_RUNTIME_PACKAGES" ]; then
        msg head "Runtime packages"
        RUNTIME_LOG=$(mktemp /tmp/passwall2-runtime.XXXXXX) || msg err "Failed to create temp file"
        if install_available_feed_packages "$FEED_RUNTIME_PACKAGES" >"$RUNTIME_LOG" 2>&1; then
            cat "$RUNTIME_LOG"
            print_pkg_warnings "$RUNTIME_LOG"
            rm -f "$RUNTIME_LOG"
            msg ok "Runtime packages installed"
        else
            cat "$RUNTIME_LOG"
            print_space_hint "$RUNTIME_LOG"
            rm -f "$RUNTIME_LOG"
            prompt_continue_luci_or_exit "Failed to install runtime packages"
        fi
    fi

    ensure_cores

    msg head "Passwall packages"
    if [ "$CLEAN_INSTALL" = true ]; then
        TARGET_PASSWALL_PACKAGES="$PASSWALL_INSTALLED_PACKAGES"
    else
        TARGET_PASSWALL_PACKAGES="$PASSWALL_UPGRADABLE_PACKAGES"
    fi

    if [ -n "$TARGET_PASSWALL_PACKAGES" ]; then
        if [ "$CLEAN_INSTALL" = true ]; then
            msg info "Installing: $TARGET_PASSWALL_PACKAGES"
        else
            msg info "Refreshing: $TARGET_PASSWALL_PACKAGES"
        fi

        REFRESH_LOG=$(mktemp /tmp/passwall2-refresh.XXXXXX) || msg err "Failed to create temp file"
        if pkg_install_feed $TARGET_PASSWALL_PACKAGES >"$REFRESH_LOG" 2>&1; then
            cat "$REFRESH_LOG"
            print_pkg_warnings "$REFRESH_LOG"
            rm -f "$REFRESH_LOG"
            if [ "$CLEAN_INSTALL" = true ]; then
                msg ok "Passwall packages installed"
            else
                msg ok "Passwall packages refreshed"
            fi
        else
            cat "$REFRESH_LOG"
            print_space_hint "$REFRESH_LOG"
            rm -f "$REFRESH_LOG"
            if [ "$CLEAN_INSTALL" = true ]; then
                msg warn "Failed to install Passwall packages"
            else
                msg warn "Failed to refresh Passwall packages"
            fi
            while true; do
                printf "${C_YELLOW}Do you want to continue with installation anyway? [y/n]: ${C_RESET}"
                read -rsn1 input
                echo
                case "$input" in
                    y|Y)
                        msg info "Continuing installation..."
                        break
                        ;;
                    n|N)
                        msg err "Installation aborted."
                        ;;
                    *)
                        msg warn "Invalid choice! Press 'y' or 'n'"
                        ;;
                esac
            done
        fi
    else
        if [ "$CLEAN_INSTALL" = true ]; then
            msg info "No installed Passwall packages to refresh"
        else
            msg info "No Passwall package updates available"
        fi
    fi
}

install_from_mirror() {
    msg head "Iranian GitHub Mirror installation"
    msg info "Fetching release metadata from scorpian.ir"

    API_RESPONSE=$(curl -s --fail "$MIRROR_API_URL")
    if [ $? -ne 0 ]; then
        msg err "Failed to fetch release metadata from scorpian.ir mirror"
    fi

    if [ -z "$TARGET_VERSION" ]; then
        RELEASE_TAG=$(echo "$API_RESPONSE" | jsonfilter -e '@.releases[0].tag_name')
        RELEASE_INDEX=0
    else
        RELEASE_TAG="$TARGET_VERSION"
        RELEASE_INDEX=$(echo "$API_RESPONSE" | jsonfilter -e '@.releases[*].tag_name' | grep -n "^${TARGET_VERSION}$" | cut -d: -f1)
        if [ -n "$RELEASE_INDEX" ]; then
            RELEASE_INDEX=$((RELEASE_INDEX - 1))
        else
            msg err "Version $TARGET_VERSION not found in mirror releases."
        fi
    fi

    if [ -z "$RELEASE_TAG" ]; then
        msg err "Failed to parse release tag from mirror."
    fi

    msg ok "Release: ${C_BOLD}$RELEASE_TAG${C_RESET}"

    case "$PACKAGE_TYPE" in
        apk) LUCI_FILENAME=$(echo "$API_RESPONSE" | jsonfilter -e "@.releases[${RELEASE_INDEX}].assets[*].name" | grep "^luci-app-passwall2-" | grep -E "\.${PACKAGE_TYPE}$" | head -n 1) ;;
        ipk) LUCI_FILENAME=$(echo "$API_RESPONSE" | jsonfilter -e "@.releases[${RELEASE_INDEX}].assets[*].name" | grep "^luci-app-passwall2_" | grep -E "\.${PACKAGE_TYPE}$" | head -n 1) ;;
    esac

    LUCI_ASSET_ID=$(echo "$API_RESPONSE" | jsonfilter -e "@.releases[${RELEASE_INDEX}].assets[@.name='$LUCI_FILENAME'].id" 2>/dev/null)
    if [ -z "$LUCI_ASSET_ID" ]; then
        LUCI_ASSET_ID=$(echo "$API_RESPONSE" | jsonfilter -e "@.releases[${RELEASE_INDEX}].assets[*]" 2>/dev/null | awk -v target="$LUCI_FILENAME" '
            /"name":/ || /"name" :/ { name=$0; sub(/.*"name"[[:space:]]*:[[:space:]]*"/, "", name); sub(/".*/, "", name) }
            /"id":/ || /"id" :/ { id=$0; sub(/.*"id"[[:space:]]*:[[:space:]]*/, "", id); sub(/,.*/, "", id); sub(/[[:space:]].*/, "", id); if (name == target) { print id; exit } }
        ')
    fi

    ZIP_FILENAME=""
    ZIP_ASSET_ID=""

    if [ "$ONLY_LUCI" = false ]; then
        msg info "Resolving package set"
        SUPPORTED_ARCHS=$(pkg_print_architectures)

        for arch in $SUPPORTED_ARCHS; do
            CANDIDATE_NAME="passwall_packages_${PACKAGE_TYPE}_${arch}.zip"

            if echo "$API_RESPONSE" | jsonfilter -e "@.releases[${RELEASE_INDEX}].assets[*].name" | grep -q "^${CANDIDATE_NAME}$"; then
                ZIP_FILENAME="$CANDIDATE_NAME"
                ZIP_ASSET_ID=$(echo "$API_RESPONSE" | jsonfilter -e "@.releases[${RELEASE_INDEX}].assets[@.name='$ZIP_FILENAME'].id" 2>/dev/null)
                if [ -z "$ZIP_ASSET_ID" ]; then
                    ZIP_ASSET_ID=$(echo "$API_RESPONSE" | jsonfilter -e "@.releases[${RELEASE_INDEX}].assets[*]" 2>/dev/null | awk -v target="$ZIP_FILENAME" '
                        /"name":/ || /"name" :/ { name=$0; sub(/.*"name"[[:space:]]*:[[:space:]]*"/, "", name); sub(/".*/, "", name) }
                        /"id":/ || /"id" :/ { id=$0; sub(/.*"id"[[:space:]]*:[[:space:]]*/, "", id); sub(/,.*/, "", id); sub(/[[:space:]].*/, "", id); if (name == target) { print id; exit } }
                    ')
                fi
                msg ok "Binary package: ${C_BOLD}$ZIP_FILENAME${C_RESET}"
                break
            fi
        done

        if [ -z "$ZIP_FILENAME" ]; then
            msg warn "No binary package matched detected architectures"
            echo "$SUPPORTED_ARCHS"
            msg warn "Available release assets:"
            echo "$API_RESPONSE" | jsonfilter -e "@.releases[${RELEASE_INDEX}].assets[*].name" | grep ".zip"
            prompt_continue_luci_or_exit "No compatible binary package found in mirror release."
        fi
    else
        msg info "Skipping binary package lookup"
    fi

    msg head "Download"

    if [ -n "$LUCI_FILENAME" ] && [ -n "$LUCI_ASSET_ID" ]; then
        msg info "Downloading LuCI package from mirror"
        curl -L -s --fail -o "$LUCI_FILENAME" "$MIRROR_ASSET_BASE_URL/$LUCI_ASSET_ID"
        [ -s "$LUCI_FILENAME" ] || msg err "Failed to download LuCI package from mirror."
    else
        msg err "LuCI package not found in release assets."
    fi

    if [ "$ONLY_LUCI" = false ] && [ -n "$ZIP_FILENAME" ] && [ -n "$ZIP_ASSET_ID" ]; then
        msg info "Downloading binary archive from mirror"
        curl -L -s --fail -o "$ZIP_FILENAME" "$MIRROR_ASSET_BASE_URL/$ZIP_ASSET_ID"

        if [ -s "$ZIP_FILENAME" ]; then
            msg ok "Binary archive downloaded"
            unzip -q -j "$ZIP_FILENAME" && rm "$ZIP_FILENAME"
            msg ok "Binary archive unpacked"
        else
            msg err "Failed to download binary ZIP from mirror. File is empty."
        fi
    fi

    if [ "$CLEAN_INSTALL" = true ]; then
        msg head "Cleanup"
        msg info "Removing existing installation"
        pkg_remove_force luci-app-passwall2 >/dev/null 2>&1

        if [ "$ONLY_LUCI" = false ]; then
            for pkg_file in *."$PACKAGE_TYPE"; do
                [ -f "$pkg_file" ] || continue
                [ "$pkg_file" = "$LUCI_FILENAME" ] && continue
                pkg_name=$(get_local_package_name "$pkg_file")
                if [ "$pkg_name" != "libc" ] && [ "$pkg_name" != "kernel" ]; then
                    [ "$pkg_name" = "simple-obfs-client" ] && pkg_remove_force simple-obfs >/dev/null 2>&1
                    pkg_remove_force "$pkg_name" >/dev/null 2>&1
                fi
            done
            if [ "$XRAY_ONLY" = true ]; then
                pkg_remove_force sing-box >/dev/null 2>&1
                rm -f /usr/bin/sing-box 2>/dev/null
            elif [ "$SINGBOX_ONLY" = true ]; then
                pkg_remove_force xray-core >/dev/null 2>&1
                rm -f /usr/bin/xray 2>/dev/null
            else
                pkg_remove_force xray-core sing-box >/dev/null 2>&1
                rm -f /usr/bin/xray /usr/bin/sing-box 2>/dev/null
            fi
        fi
        msg ok "Existing packages removed"
    fi

    msg head "Install"

    if [ "$ONLY_LUCI" = false ]; then
        msg info "Installing packages"
        for pkg_file in *."$PACKAGE_TYPE"; do
            [ -f "$pkg_file" ] || continue
            [ "$pkg_file" = "$LUCI_FILENAME" ] && continue

            if [ "$SINGBOX_ONLY" = true ]; then
                pkg_name=$(get_local_package_name "$pkg_file")
                case "$pkg_name" in
                    sing-box|geoview|v2ray-geoip|v2ray-geosite|tcping)
                        # allowed
                        ;;
                    *)
                        echo -e "${C_CYAN}[INFO]${C_RESET} Skipping $pkg_name (minimal sing-box mode)"
                        continue
                        ;;
                esac
            elif [ "$XRAY_ONLY" = true ]; then
                pkg_name=$(get_local_package_name "$pkg_file")
                case "$pkg_name" in
                    xray-core|geoview|v2ray-geoip|v2ray-geosite|tcping)
                        # allowed
                        ;;
                    *)
                        echo -e "${C_CYAN}[INFO]${C_RESET} Skipping $pkg_name (minimal xray mode)"
                        continue
                        ;;
                esac
            fi

            ERROR_LOG=$(mktemp)
            if pkg_install_local "$pkg_file" >/dev/null 2>"$ERROR_LOG"; then
                echo -e "${C_GREEN}[OK]${C_RESET} ${pkg_file}"
                rm "$pkg_file"
            else
                echo -e "${C_RED}[ERROR]${C_RESET} ${pkg_file}"
                if [ -s "$ERROR_LOG" ]; then
                    echo -e "${C_YELLOW}[WARN]${C_RESET} Error details:"
                    cat "$ERROR_LOG" | sed 's/^/    /'
                    if grep -qiE "(space|No space left|disk full|available on filesystem|needs|verify_pkg_installable)" "$ERROR_LOG"; then
                        echo -e "${C_YELLOW}[WARN]${C_RESET} Suggestion: try --clean to free space"
                    fi
                fi
            fi
            rm -f "$ERROR_LOG"
        done

        ensure_cores
    fi

    msg info "Installing LuCI package"
    ERROR_LOG=$(mktemp)
    if pkg_install_local "$LUCI_FILENAME" >/dev/null 2>"$ERROR_LOG"; then
        rm "$LUCI_FILENAME"
        rm -f "$ERROR_LOG"
        msg ok "LuCI installed"
    else
        if [ -s "$ERROR_LOG" ]; then
            echo -e "${C_YELLOW}[WARN]${C_RESET} Error details:"
            cat "$ERROR_LOG" | sed 's/^/  /'
            if grep -qiE "(space|No space left|disk full|available on filesystem|needs|verify_pkg_installable)" "$ERROR_LOG"; then
                echo -e "${C_YELLOW}[WARN]${C_RESET} Suggestion: try --clean to free space"
            fi
        fi
        rm -f "$ERROR_LOG"
        msg err "Failed to install LuCI package"
    fi
}

install_from_github() {
    msg head "GitHub installation"
    msg info "Fetching release metadata"

    if [ -z "$TARGET_VERSION" ]; then
        API_URL="$REPO_URL/latest"
    else
        API_URL="$REPO_URL/tags/$TARGET_VERSION"
    fi
    
    API_RESPONSE=$(curl -s --fail "$API_URL")
    if [ $? -ne 0 ]; then
        msg err "Failed to fetch release metadata from GitHub"
    fi

    RELEASE_TAG=$(echo "$API_RESPONSE" | jsonfilter -e '@.tag_name')
    msg ok "Release: ${C_BOLD}$RELEASE_TAG${C_RESET}"

    case "$PACKAGE_TYPE" in
        apk) LUCI_FILENAME=$(echo "$API_RESPONSE" | jsonfilter -e '@.assets[*].name' | grep "^luci-app-passwall2-" | grep -E "\.${PACKAGE_TYPE}$" | head -n 1) ;;
        ipk) LUCI_FILENAME=$(echo "$API_RESPONSE" | jsonfilter -e '@.assets[*].name' | grep "^luci-app-passwall2_" | grep -E "\.${PACKAGE_TYPE}$" | head -n 1) ;;
    esac

    ZIP_FILENAME=""

    if [ "$ONLY_LUCI" = false ]; then
        msg info "Resolving package set"
        SUPPORTED_ARCHS=$(pkg_print_architectures)

        for arch in $SUPPORTED_ARCHS; do
            CANDIDATE_NAME="passwall_packages_${PACKAGE_TYPE}_${arch}.zip"

            if echo "$API_RESPONSE" | jsonfilter -e '@.assets[*].name' | grep -q "^${CANDIDATE_NAME}$"; then
                ZIP_FILENAME="$CANDIDATE_NAME"
                msg ok "Binary package: ${C_BOLD}$ZIP_FILENAME${C_RESET}"
                break
            fi
        done

        if [ -z "$ZIP_FILENAME" ]; then
            msg warn "No binary package matched detected architectures"
            echo "$SUPPORTED_ARCHS"
            msg warn "Available release assets:"
            echo "$API_RESPONSE" | jsonfilter -e '@.assets[*].name' | grep ".zip"
            prompt_continue_luci_or_exit "No compatible binary package found in GitHub release."
        fi
    else
        msg info "Skipping binary package lookup"
    fi

    msg head "Download"

    if [ -n "$LUCI_FILENAME" ]; then
        msg info "Downloading LuCI package"
        curl -L -s --fail -o "$LUCI_FILENAME" "$BASE_DOWNLOAD_URL/$RELEASE_TAG/$LUCI_FILENAME"
        [ -s "$LUCI_FILENAME" ] || msg err "Failed to download LuCI package."
    else
        msg err "LuCI package not found in release assets."
    fi

    if [ "$ONLY_LUCI" = false ] && [ -n "$ZIP_FILENAME" ]; then
        msg info "Downloading binary archive"
        curl -L -s --fail -o "$ZIP_FILENAME" "$BASE_DOWNLOAD_URL/$RELEASE_TAG/$ZIP_FILENAME"

        if [ -s "$ZIP_FILENAME" ]; then
            msg ok "Binary archive downloaded"
            unzip -q -j "$ZIP_FILENAME" && rm "$ZIP_FILENAME"
            msg ok "Binary archive unpacked"
        else
            msg err "Failed to download binary ZIP. File is empty."
        fi
    fi

    if [ "$CLEAN_INSTALL" = true ]; then
        msg head "Cleanup"
        msg info "Removing existing installation"
        pkg_remove_force luci-app-passwall2 >/dev/null 2>&1

        if [ "$ONLY_LUCI" = false ]; then
            for pkg_file in *."$PACKAGE_TYPE"; do
                [ -f "$pkg_file" ] || continue
                [ "$pkg_file" = "$LUCI_FILENAME" ] && continue
                pkg_name=$(get_local_package_name "$pkg_file")
                if [ "$pkg_name" != "libc" ] && [ "$pkg_name" != "kernel" ]; then
                    [ "$pkg_name" = "simple-obfs-client" ] && pkg_remove_force simple-obfs >/dev/null 2>&1
                    pkg_remove_force "$pkg_name" >/dev/null 2>&1
                fi
            done
            if [ "$XRAY_ONLY" = true ]; then
                pkg_remove_force sing-box >/dev/null 2>&1
                rm -f /usr/bin/sing-box 2>/dev/null
            elif [ "$SINGBOX_ONLY" = true ]; then
                pkg_remove_force xray-core >/dev/null 2>&1
                rm -f /usr/bin/xray 2>/dev/null
            else
                pkg_remove_force xray-core sing-box >/dev/null 2>&1
                rm -f /usr/bin/xray /usr/bin/sing-box 2>/dev/null
            fi
        fi
        msg ok "Existing packages removed"
    fi

    msg head "Install"

    if [ "$ONLY_LUCI" = false ]; then
        msg info "Installing packages"
        for pkg_file in *."$PACKAGE_TYPE"; do
            [ -f "$pkg_file" ] || continue
            [ "$pkg_file" = "$LUCI_FILENAME" ] && continue

            if [ "$SINGBOX_ONLY" = true ]; then
                pkg_name=$(get_local_package_name "$pkg_file")
                case "$pkg_name" in
                    sing-box|geoview|v2ray-geoip|v2ray-geosite|tcping)
                        # allowed
                        ;;
                    *)
                        echo -e "${C_CYAN}[INFO]${C_RESET} Skipping $pkg_name (minimal sing-box mode)"
                        continue
                        ;;
                esac
            elif [ "$XRAY_ONLY" = true ]; then
                pkg_name=$(get_local_package_name "$pkg_file")
                case "$pkg_name" in
                    xray-core|geoview|v2ray-geoip|v2ray-geosite|tcping)
                        # allowed
                        ;;
                    *)
                        echo -e "${C_CYAN}[INFO]${C_RESET} Skipping $pkg_name (minimal xray mode)"
                        continue
                        ;;
                esac
            fi

            ERROR_LOG=$(mktemp)
            if pkg_install_local "$pkg_file" >/dev/null 2>"$ERROR_LOG"; then
                echo -e "${C_GREEN}[OK]${C_RESET} ${pkg_file}"
                rm "$pkg_file"
            else
                echo -e "${C_RED}[ERROR]${C_RESET} ${pkg_file}"
                if [ -s "$ERROR_LOG" ]; then
                    echo -e "${C_YELLOW}[WARN]${C_RESET} Error details:"
                    cat "$ERROR_LOG" | sed 's/^/    /'
                    if grep -qiE "(space|No space left|disk full|available on filesystem|needs|verify_pkg_installable)" "$ERROR_LOG"; then
                        echo -e "${C_YELLOW}[WARN]${C_RESET} Suggestion: try --clean to free space"
                    fi
                fi
            fi
            rm -f "$ERROR_LOG"
        done

        ensure_cores
    fi

    msg info "Installing LuCI package"
    ERROR_LOG=$(mktemp)
    if pkg_install_local "$LUCI_FILENAME" >/dev/null 2>"$ERROR_LOG"; then
        rm "$LUCI_FILENAME"
        rm -f "$ERROR_LOG"
        msg ok "LuCI installed"
    else
        if [ -s "$ERROR_LOG" ]; then
            echo -e "${C_YELLOW}[WARN]${C_RESET} Error details:"
            cat "$ERROR_LOG" | sed 's/^/  /'
            if grep -qiE "(space|No space left|disk full|available on filesystem|needs|verify_pkg_installable)" "$ERROR_LOG"; then
                echo -e "${C_YELLOW}[WARN]${C_RESET} Suggestion: try --clean to free space"
            fi
        fi
        rm -f "$ERROR_LOG"
        msg err "Failed to install LuCI package"
    fi
}


configure_feeds

if [ "$GITHUB_MODE" = false ] && [ "$MIRROR_MODE" = false ]; then
    install_from_feed
elif [ "$MIRROR_MODE" = true ]; then
    install_from_mirror
else
    install_from_github
fi

cd /tmp && rm -rf "$TEMP_DIR"

if [ "$IRAN_CONFIG" = true ]; then
    apply_iran_config
fi

if [ "$ROOT_WIFI" = true ]; then
    setup_root_wifi
fi

if [ "$MOD_RESET_BTN" = true ]; then
    setup_reset_button
fi

if [ "$ONLY_LUCI" = false ]; then
    if [ ! -x /usr/bin/xray ] && [ ! -x /usr/bin/sing-box ]; then
        msg warn "No proxy core is installed! Passwall2 requires at least xray-core or sing-box to operate."
        msg info "You can install a core manually via: $PACKAGE_MANAGER install xray-core (or sing-box)"
    fi
fi

msg ok "Installation completed"
rm -f "$0"

# Reboot or Exit
while true; do
    printf "${C_YELLOW}Press [r] to reboot or [e] to exit: ${C_RESET}"
    read -rsn1 input
    case "$input" in
        r|R)
            msg ok "\nRebooting system..."
            reboot
            exit 0
            ;;
        e|E)
            msg warn "\nExiting script."
            exit 0
            ;;
        *)
            msg warn "\nInvalid choice! Press 'r' or 'e'"
            sleep 1
            ;;
    esac
done
