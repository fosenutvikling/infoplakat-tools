#!/bin/bash
#
# Infoplakat Player - Linux Uninstaller
#
# Removes Infoplakat Player and all associated configuration.
# Useful for clean reinstalls or when decommissioning a device.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/fosenutvikling/infoplakat-tools/main/player/uninstall-linux.sh | bash
#
# What this script removes:
#   1. Application files (/opt/infoplakat-player)
#   2. Autostart entries (infoplakat-player, disable-dpms, unclutter)
#   3. Power management changes (restores GNOME defaults)
#   4. Automatic login (optionally)
#
# What this script does NOT remove:
#   - unclutter package (may be used by other apps)
#

set -uo pipefail

# --- Configuration ---
INSTALL_DIR="/opt/infoplakat-player"
DESKTOP_FILE="infoplakat-player.desktop"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Interactive read that works when piped (curl | bash)
ask() {
    local prompt="$1"
    local varname="$2"
    local default="${3:-}"
    if [[ -t 0 ]]; then
        read -rp "$prompt" "$varname"
    elif [[ -e /dev/tty ]]; then
        read -rp "$prompt" "$varname" < /dev/tty
    else
        printf '%s' "$prompt"
        printf -v "$varname" '%s' "$default"
        echo "$default"
    fi
}

# --- Remove application files ---
remove_app() {
    if [[ -d "$INSTALL_DIR" ]]; then
        info "Removing application files..."
        sudo rm -rf "$INSTALL_DIR"
        ok "Removed ${INSTALL_DIR}"
    else
        warn "Application directory not found (${INSTALL_DIR})"
    fi
}

# --- Remove autostart entries ---
remove_autostart() {
    local autostart_dir="${HOME}/.config/autostart"
    local removed=0

    info "Removing autostart entries..."

    for file in "$DESKTOP_FILE" "disable-dpms.desktop" "unclutter.desktop"; do
        if [[ -f "${autostart_dir}/${file}" ]]; then
            rm -f "${autostart_dir}/${file}"
            ok "Removed ${autostart_dir}/${file}"
            ((removed++))
        fi
    done

    if [[ $removed -eq 0 ]]; then
        warn "No autostart entries found"
    fi
}

# --- Restore power management defaults ---
restore_power() {
    info "Restoring display and power settings..."

    if command -v gsettings &> /dev/null; then
        # Restore GNOME defaults
        gsettings reset org.gnome.desktop.screensaver lock-enabled 2>/dev/null || true
        gsettings reset org.gnome.desktop.screensaver idle-activation-enabled 2>/dev/null || true
        gsettings reset org.gnome.desktop.session idle-delay 2>/dev/null || true
        gsettings reset org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 2>/dev/null || true
        gsettings reset org.gnome.settings-daemon.plugins.power idle-dim 2>/dev/null || true
        ok "GNOME power settings restored to defaults"
    else
        warn "gsettings not found, skipping power setting restore"
    fi

    # Re-enable DPMS
    if command -v xset &> /dev/null; then
        xset +dpms 2>/dev/null || true
        xset s on 2>/dev/null || true
        ok "DPMS re-enabled"
    fi
}

# --- Disable automatic login ---
remove_autologin() {
    local gdm_conf="/etc/gdm3/custom.conf"

    if [[ -f "$gdm_conf" ]] && grep -q "AutomaticLoginEnable=true" "$gdm_conf" 2>/dev/null; then
        ask "Disable automatic login? (Y/n) " disable_autologin "y"
        if [[ ! "$disable_autologin" =~ ^[nN]$ ]]; then
            sudo sed -i '/AutomaticLoginEnable=true/d' "$gdm_conf"
            sudo sed -i "/AutomaticLogin=$(whoami)/d" "$gdm_conf"
            ok "Automatic login disabled"
        else
            warn "Automatic login left enabled"
        fi
    fi
}

# --- Summary ---
print_summary() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Infoplakat Player has been uninstalled.${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Removed:"
    echo "    - Application files (${INSTALL_DIR})"
    echo "    - Autostart entries"
    echo "    - Power management overrides"
    echo ""
    echo "  Not removed:"
    echo "    - unclutter package (remove with: sudo apt remove unclutter)"
    echo ""
    echo "  To reinstall:"
    echo -e "    ${BLUE}curl -fsSL https://raw.githubusercontent.com/fosenutvikling/infoplakat-tools/main/player/install-linux.sh | bash${NC}"
    echo ""
}

# --- Main ---
main() {
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  Infoplakat Player - Linux Uninstaller        ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ ! -d "$INSTALL_DIR" ]] && [[ ! -f "${HOME}/.config/autostart/${DESKTOP_FILE}" ]]; then
        warn "Infoplakat Player does not appear to be installed."
        ask "Continue anyway? (y/N) " continue_anyway "n"
        if [[ ! "$continue_anyway" =~ ^[yYjJ]$ ]]; then
            info "Aborted."
            exit 0
        fi
    fi

    remove_app
    remove_autostart
    restore_power
    remove_autologin
    print_summary
}

main "$@"
