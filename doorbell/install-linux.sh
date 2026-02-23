#!/bin/bash
#
# Infoplakat Doorbell - Linux Installer
#
# Automatic installation of Infoplakat Doorbell on Ubuntu/Debian Linux.
# Fetches the latest version from CDN and sets up autostart.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/fosenutvikling/infoplakat-tools/main/doorbell/install-linux.sh | bash
#
# What this script does:
#   1. Fetches the latest version number from CDN
#   2. Downloads the correct package for your architecture (x64/arm64)
#   3. Installs to /opt/infoplakat-doorbell
#   4. Fixes chrome-sandbox permissions and /dev/shm
#   5. Sets up autostart on login
#   6. Installs audio dependencies if missing
#

set -euo pipefail

# --- Configuration ---
CDN_URL="https://cdn.infoplakat.no/doorbell"
INSTALL_DIR="/opt/infoplakat-doorbell"
APP_NAME="Infoplakat Doorbell"
BINARY_NAME="infoplakat-doorbell"
DESKTOP_FILE="infoplakat-doorbell.desktop"

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
    if [[ -f "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
        local current=""
        if [[ -f "${INSTALL_DIR}/resources/app.asar" ]]; then
            current=$(strings "${INSTALL_DIR}/resources/app.asar" 2>/dev/null | grep -oP '"version"\s*:\s*"\K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        fi

        if [[ "$current" == "$VERSION" ]]; then
            ok "Infoplakat Doorbell v${VERSION} is already installed."
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
            FILENAME="infoplakat-doorbell-${VERSION}-x64.tar.gz"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            FILENAME="infoplakat-doorbell-${VERSION}-arm64.tar.gz"
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

    # Set permissions for main binary
    sudo chmod +x "${INSTALL_DIR}/${BINARY_NAME}"

    # Fix chrome-sandbox: must be owned by root with SUID bit set
    # Without this, Electron fails with:
    #   "The SUID sandbox helper binary was found, but is not configured correctly"
    if [[ -f "${INSTALL_DIR}/chrome-sandbox" ]]; then
        sudo chown root:root "${INSTALL_DIR}/chrome-sandbox"
        sudo chmod 4755 "${INSTALL_DIR}/chrome-sandbox"
        ok "chrome-sandbox permissions fixed (root:root, mode 4755)"
    fi

    # Clean up downloaded file
    rm -f "$DOWNLOAD_PATH"
    rmdir "$(dirname "$DOWNLOAD_PATH")" 2>/dev/null || true

    ok "Installed to ${INSTALL_DIR}"
}

# --- Fix /dev/shm permissions ---
fix_dev_shm() {
    if [[ -d /dev/shm ]]; then
        local perms
        perms=$(stat -c '%a' /dev/shm 2>/dev/null || echo "unknown")
        if [[ "$perms" != "1777" ]]; then
            info "Fixing /dev/shm permissions (currently: ${perms}, required: 1777)..."
            sudo chmod 1777 /dev/shm
            ok "/dev/shm permissions fixed"
        else
            ok "/dev/shm permissions are correct"
        fi
    else
        warn "/dev/shm does not exist. Electron may fail to start."
        warn "Try: sudo mkdir -p /dev/shm && sudo chmod 1777 /dev/shm"
    fi
}

# --- Install audio dependencies ---
install_audio_deps() {
    info "Checking audio dependencies..."

    local missing=()

    # Check for PulseAudio or PipeWire (needed for notification sounds)
    if ! command -v pulseaudio &> /dev/null && ! command -v pipewire &> /dev/null; then
        missing+=("pulseaudio")
    fi

    # Check for ALSA libraries
    if ! ldconfig -p 2>/dev/null | grep -q "libasound.so.2"; then
        missing+=("libasound2")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        info "Installing missing audio packages: ${missing[*]}"
        sudo apt-get update -qq
        sudo apt-get install -y -qq "${missing[@]}" > /dev/null 2>&1 || {
            warn "Could not install audio dependencies: ${missing[*]}"
            warn "Notification sounds may not work. Install manually with:"
            warn "  sudo apt install ${missing[*]}"
            return
        }
        ok "Audio dependencies installed"
    else
        ok "Audio dependencies are present"
    fi
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
Comment=Doorbell notification receiver for Infoplakat Kiosk
Exec=${INSTALL_DIR}/${BINARY_NAME} --no-sandbox --disable-gpu
Icon=${INSTALL_DIR}/resources/app.asar.unpacked/assets/icon.png
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
StartupNotify=false
EOF

    ok "Autostart configured: ${autostart_dir}/${DESKTOP_FILE}"
}

# --- Summary ---
print_summary() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Infoplakat Doorbell v${VERSION} installed successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Installed to:  ${INSTALL_DIR}"
    echo "  Autostart:     ${HOME}/.config/autostart/${DESKTOP_FILE}"
    echo ""
    echo "  Start the app now:"
    echo -e "    ${BLUE}${INSTALL_DIR}/${BINARY_NAME} --no-sandbox --disable-gpu${NC}"
    echo ""
    echo "  The app will start automatically on next login."
    echo "  Updates are checked automatically every hour."
    echo ""
    echo "  First time? Open the app and sign in with your"
    echo "  Infoplakat account to start receiving notifications."
    echo ""
}

# --- Main ---
main() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Infoplakat Doorbell - Linux Installer            ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""

    check_prerequisites
    get_latest_version
    detect_arch
    check_existing
    download
    install_app
    fix_dev_shm
    install_audio_deps
    setup_autostart
    print_summary
}

main "$@"
