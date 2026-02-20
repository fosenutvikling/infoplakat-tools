# Infoplakat Tools

Public tools and installation scripts for [Infoplakat](https://infoplakat.no) digital signage.

## Player - Linux Installer

Automatic installation of Infoplakat Player on Ubuntu/Debian Linux (x64 and ARM64/Raspberry Pi).

### Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/fosenutvikling/infoplakat-tools/main/player/install-linux.sh | bash
```

### What it does

1. Fetches the latest version from CDN
2. Detects your architecture (x64 or ARM64)
3. Downloads and installs to `/opt/infoplakat-player`
4. Sets up autostart on login
5. Disables screensaver and power management
6. Installs [unclutter](https://github.com/Airblader/unclutter-xfixes) (hides mouse cursor)
7. Optionally enables automatic login

### Requirements

- Ubuntu 24.04 LTS Desktop (or compatible Debian-based distro)
- `curl` or `wget`
- Internet connection

### Re-run to update

The script detects existing installations and updates to the latest version automatically.

## License

MIT
