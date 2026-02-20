#!/bin/bash
#
# Infoplakat Player - Linux Installer
#
# Automatic installation of Infoplakat Player on Ubuntu/Debian Linux.
# Fetches the latest version from CDN and sets up autostart.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/fosenutvikling/infoplakat-tools/main/player/install-linux.sh | bash
#
# What this script does:
#   1. Fetches the latest version number from CDN
#   2. Downloads the correct package for your architecture (x64/arm64)
#   3. Installs to /opt/infoplakat-player
#   4. Sets up autostart on login
#   5. Disables screensaver and power management
#   6. Installs unclutter (hides mouse cursor)
#

set -euo pipefail

# --- Configuration ---
CDN_URL="https://cdn.infoplakat.no/player"
INSTALL_DIR="/opt/infoplakat-player"
APP_NAME="Infoplakat Player"
DESKTOP_FILE="infoplakat-player.desktop"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Interactive read that works when piped (curl | bash)
# Falls back to default value if /dev/tty is not available
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

# --- Check prerequisites ---
check_prerequisites() {
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        error "This script is for Linux only."
    fi

    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        error "wget or curl is required. Install with: sudo apt install wget"
    fi

    if [[ $EUID -eq 0 ]]; then
        warn "Running as root. The app should be installed as a regular user for autostart to work."
        warn "The script uses 'sudo' only where needed."
    fi
}

# --- Fetch latest version from CDN ---
get_latest_version() {
    info "Fetching latest version number..."

    local yml
    if command -v curl &> /dev/null; then
        yml=$(curl -fsSL "${CDN_URL}/latest.yml" 2>/dev/null) || error "Could not fetch version info from CDN."
    else
        yml=$(wget -qO- "${CDN_URL}/latest.yml" 2>/dev/null) || error "Could not fetch version info from CDN."
    fi

    # Parse version from YAML (simple parsing, no dependencies)
    VERSION=$(echo "$yml" | grep -oP '^version:\s*\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    if [[ -z "$VERSION" ]]; then
        error "Could not find version number in latest.yml"
    fi

    ok "Latest version: v${VERSION}"
}

# --- Check if already installed with same version ---
check_existing() {
    if [[ -f "${INSTALL_DIR}/infoplakat-player" ]]; then
        local current=""
        # Try to read version from resources
        if [[ -f "${INSTALL_DIR}/resources/app.asar" ]]; then
            current=$(strings "${INSTALL_DIR}/resources/app.asar" 2>/dev/null | grep -oP '"version"\s*:\s*"\K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        fi

        if [[ "$current" == "$VERSION" ]]; then
            ok "Infoplakat Player v${VERSION} is already installed."
            ask "Do you want to reinstall? (y/N) " reinstall "n"
            if [[ ! "$reinstall" =~ ^[yYjJ]$ ]]; then
                info "Aborted. No changes made."
                exit 0
            fi
        else
            if [[ -n "$current" ]]; then
                info "Updating from v${current} to v${VERSION}..."
            else
                info "Existing installation found. Updating to v${VERSION}..."
            fi
        fi
    fi
}

# --- Detect architecture ---
detect_arch() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64|amd64)
            ARCH="x64"
            FILENAME="infoplakat-player-${VERSION}.tar.gz"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            FILENAME="infoplakat-player-${VERSION}-arm64.tar.gz"
            ;;
        *)
            error "Architecture '${arch}' is not supported. Only x64 and arm64."
            ;;
    esac

    ok "Architecture: ${ARCH} (${arch})"
}

# --- Download ---
download() {
    local url="${CDN_URL}/${FILENAME}"
    local tmpdir
    tmpdir=$(mktemp -d)
    DOWNLOAD_PATH="${tmpdir}/${FILENAME}"

    info "Downloading ${FILENAME}..."
    info "URL: ${url}"

    if command -v curl &> /dev/null; then
        curl -fL --progress-bar -o "$DOWNLOAD_PATH" "$url" || error "Download failed. Check your internet connection."
    else
        wget --show-progress -q -O "$DOWNLOAD_PATH" "$url" || error "Download failed. Check your internet connection."
    fi

    ok "Downloaded to ${DOWNLOAD_PATH}"
}

# --- Install ---
install_app() {
    info "Installing to ${INSTALL_DIR}..."

    # Create directory
    sudo mkdir -p "$INSTALL_DIR"

    # Extract tar.gz from electron-builder
    sudo tar -xzf "$DOWNLOAD_PATH" -C "$INSTALL_DIR" --strip-components=1

    # Set permissions
    sudo chmod +x "${INSTALL_DIR}/infoplakat-player"
    sudo chmod 4755 "${INSTALL_DIR}/chrome-sandbox" 2>/dev/null || true

    # Clean up downloaded file
    rm -f "$DOWNLOAD_PATH"
    rmdir "$(dirname "$DOWNLOAD_PATH")" 2>/dev/null || true

    ok "Installed to ${INSTALL_DIR}"
}

# --- Set up autostart ---
setup_autostart() {
    info "Setting up autostart..."

    local autostart_dir="${HOME}/.config/autostart"
    mkdir -p "$autostart_dir"

    cat > "${autostart_dir}/${DESKTOP_FILE}" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=Digital signage player for Infoplakat
Exec=${INSTALL_DIR}/infoplakat-player --no-sandbox
Icon=${INSTALL_DIR}/resources/app.asar.unpacked/src/assets/icon.png
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
StartupNotify=false
EOF

    ok "Autostart configured: ${autostart_dir}/${DESKTOP_FILE}"
}

# --- Disable screensaver and power management ---
configure_power() {
    info "Configuring display and power settings..."

    # GNOME/Ubuntu Desktop
    if command -v gsettings &> /dev/null; then
        # Disable screen lock
        gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
        gsettings set org.gnome.desktop.screensaver idle-activation-enabled false 2>/dev/null || true

        # Screen should never blank
        gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true

        # Disable power saving
        gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
        gsettings set org.gnome.settings-daemon.plugins.power idle-dim false 2>/dev/null || true

        ok "GNOME power settings configured"
    else
        warn "gsettings not found. Disable screensaver manually in Settings."
    fi

    # Disable DPMS (Display Power Management) via xset
    if command -v xset &> /dev/null; then
        xset s off 2>/dev/null || true       # Disable screensaver
        xset -dpms 2>/dev/null || true       # Disable DPMS
        xset s noblank 2>/dev/null || true   # Don't blank screen

        # Make DPMS changes persistent via autostart
        local autostart_dir="${HOME}/.config/autostart"
        cat > "${autostart_dir}/disable-dpms.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Disable DPMS
Exec=bash -c "xset s off; xset -dpms; xset s noblank"
Terminal=false
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
        ok "DPMS disabled"
    fi
}

# --- Install unclutter (hides mouse cursor) ---
install_unclutter() {
    if command -v unclutter &> /dev/null; then
        ok "unclutter is already installed"
    else
        info "Installing unclutter (hides mouse cursor when idle)..."
        sudo apt-get update -qq
        sudo apt-get install -y -qq unclutter > /dev/null 2>&1 || {
            warn "Could not install unclutter. Install manually with: sudo apt install unclutter"
            return
        }
        ok "unclutter installed"
    fi

    # Autostart for unclutter
    local autostart_dir="${HOME}/.config/autostart"
    mkdir -p "$autostart_dir"

    cat > "${autostart_dir}/unclutter.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Unclutter
Comment=Hide mouse cursor when idle
Exec=unclutter -idle 3
Terminal=false
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

    ok "Mouse cursor hides after 3 seconds of inactivity"
}

# --- Enable automatic login ---
setup_autologin() {
    info "Checking automatic login..."

    local gdm_conf="/etc/gdm3/custom.conf"
    if [[ -f "$gdm_conf" ]]; then
        if grep -q "AutomaticLoginEnable=true" "$gdm_conf" 2>/dev/null; then
            ok "Automatic login is already enabled"
        else
            ask "Enable automatic login for user '$(whoami)'? (Y/n) " enable_autologin "y"
            if [[ ! "$enable_autologin" =~ ^[nN]$ ]]; then
                sudo sed -i '/\[daemon\]/a AutomaticLoginEnable=true\nAutomaticLogin='"$(whoami)" "$gdm_conf"
                ok "Automatic login enabled for '$(whoami)'"
            else
                warn "Remember to enable automatic login manually in Settings > Users"
            fi
        fi
    else
        warn "GDM config file not found. Enable automatic login manually."
    fi
}

# --- Summary ---
print_summary() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Infoplakat Player v${VERSION} installed successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Installed to:  ${INSTALL_DIR}"
    echo "  Autostart:     ${HOME}/.config/autostart/${DESKTOP_FILE}"
    echo ""
    echo "  Start the app now:"
    echo -e "    ${BLUE}${INSTALL_DIR}/infoplakat-player --no-sandbox${NC}"
    echo ""
    echo "  Keyboard shortcuts:"
    echo "    F11              Toggle fullscreen"
    echo "    Escape           Exit fullscreen"
    echo "    Ctrl+Shift+C     Show control panel"
    echo "    Arrow keys       Next/previous slide"
    echo "    Space            Pause/resume"
    echo ""
    echo "  The app will start automatically on next login."
    echo "  Updates are checked automatically every hour."
    echo ""
}

# --- Main ---
main() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Infoplakat Player - Linux Installer          ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
    echo ""

    check_prerequisites
    get_latest_version
    detect_arch
    check_existing
    download
    install_app
    setup_autostart
    configure_power
    install_unclutter
    setup_autologin
    print_summary
}

main "$@"
