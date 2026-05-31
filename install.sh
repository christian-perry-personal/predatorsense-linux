#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║        PredatorSense Linux — Installer for Acer PHN16S-71 / CachyOS        ║
# ║    Installs: linuwu_sense driver · DKMS · Python GUI · Desktop launcher    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

BOLD='\033[1m'; RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

banner() {
  echo -e "${CYAN}"
  echo "  ██████╗ ██████╗ ███████╗██████╗  █████╗ ████████╗ ██████╗ ██████╗ "
  echo "  ██╔══██╗██╔══██╗██╔════╝██╔══██╗██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗"
  echo "  ██████╔╝██████╔╝█████╗  ██║  ██║███████║   ██║   ██║   ██║██████╔╝"
  echo "  ██╔═══╝ ██╔══██╗██╔══╝  ██║  ██║██╔══██║   ██║   ██║   ██║██╔══██╗"
  echo "  ██║     ██║  ██║███████╗██████╔╝██║  ██║   ██║   ╚██████╔╝██║  ██║"
  echo "  ╚═╝     ╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝"
  echo -e "${NC}"
  echo -e "  ${BOLD}PredatorSense Linux — Installer${NC}"
  echo -e "  For: Acer Predator series · CachyOS / Arch Linux"
  echo ""
}

log()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
err()  { echo -e "  ${RED}✗${NC}  $1"; }
step() { echo -e "\n  ${CYAN}━━ $1 ${NC}"; }

check_root() {
  if [[ $EUID -eq 0 ]]; then
    err "Do not run this script as root. It will use sudo when needed."
    exit 1
  fi
}

check_hardware() {
  MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "Unknown")
  log "Hardware model: $MODEL"
  if echo "$MODEL" | grep -qi "predator\|nitro"; then
    log "Acer Predator/Nitro laptop detected ✓"
  else
    warn "This app is designed for Acer Predator/Nitro laptops."
    warn "Detected: $MODEL"
    warn "Installation will continue but hardware controls may not work."
    echo ""
    read -rp "  Continue anyway? [y/N] " hw_confirm
    [[ "${hw_confirm,,}" != "y" ]] && { echo "  Aborted."; exit 0; }
  fi
}

check_distro() {
  DISTRO=$(grep -oP "(?<=^ID=).*" /etc/os-release 2>/dev/null | tr -d '"' || echo "unknown")
  DISTRO_LIKE=$(grep -oP "(?<=^ID_LIKE=).*" /etc/os-release 2>/dev/null | tr -d '"' || echo "")

  if echo "$DISTRO $DISTRO_LIKE" | grep -qi "cachyos"; then
    DISTRO_NAME="CachyOS"
    PKG_MANAGER="pacman"
  elif echo "$DISTRO $DISTRO_LIKE" | grep -qi "arch\|manjaro\|endeavour\|garuda\|artix"; then
    DISTRO_NAME="Arch-based ($DISTRO)"
    PKG_MANAGER="pacman"
  elif echo "$DISTRO $DISTRO_LIKE" | grep -qi "ubuntu\|debian\|mint\|pop"; then
    DISTRO_NAME="Debian-based ($DISTRO)"
    PKG_MANAGER="apt"
    warn "Debian/Ubuntu detected. Some packages may have different names."
    warn "The installer will attempt to use apt where possible."
  elif echo "$DISTRO $DISTRO_LIKE" | grep -qi "fedora\|rhel\|centos"; then
    DISTRO_NAME="Fedora-based ($DISTRO)"
    PKG_MANAGER="dnf"
    warn "Fedora detected. Some packages may have different names."
  else
    DISTRO_NAME="Unknown ($DISTRO)"
    PKG_MANAGER="pacman"
    warn "Unknown distro. Assuming pacman-based. Install may fail."
  fi
  log "Distro: $DISTRO_NAME"
}

detect_kernel_headers() {
  KERNEL=$(uname -r)
  log "Kernel: $KERNEL"

  check_kernel_header_mismatch() {
    local running_kernel="$1"
    local headers_pkg="$2"

    local header_ver
    header_ver=$(pacman -Q "$headers_pkg" 2>/dev/null | awk "{print \$2}" | cut -d- -f1)
    local kernel_ver
    kernel_ver=$(echo "$running_kernel" | cut -d- -f1)

    if [[ -n "$header_ver" && "$header_ver" != "$kernel_ver" ]]; then
      warn "⚠ Kernel version mismatch detected!"
      warn "  Running kernel:   $running_kernel ($kernel_ver)"
      warn "  Installed headers: $headers_pkg ($header_ver)"
      warn ""
      warn "This happens on CachyOS/Arch when the kernel updates but headers"
      warn "package lags behind, or vice versa."
      warn ""
      warn "Fix options:"
      warn "  1. Update everything: sudo pacman -Syu"
      warn "  2. Reboot after update to load the new kernel"
      warn "  3. Then re-run this installer"
      echo ""
      read -rp "  Continue anyway? Headers may not match. [y/N] " mismatch_confirm
      [[ "${mismatch_confirm,,}" != "y" ]] && {
        echo "  Aborted. Please run: sudo pacman -Syu && reboot"
        exit 0
      }
    fi

    if [[ ! -d "/lib/modules/$running_kernel/build" ]]; then
      warn "Build directory missing: /lib/modules/$running_kernel/build"
      warn "Headers may not be installed for your running kernel."
      warn "Try: sudo pacman -S $headers_pkg && reboot"
    fi
  }

  if echo "$KERNEL" | grep -q "cachyos-lto"; then
    HEADERS_PKG="linux-cachyos-lto-headers"
  elif echo "$KERNEL" | grep -q "cachyos-bore"; then
    HEADERS_PKG="linux-cachyos-bore-headers"
  elif echo "$KERNEL" | grep -q "cachyos-eevdf"; then
    HEADERS_PKG="linux-cachyos-eevdf-headers"
  elif echo "$KERNEL" | grep -q "cachyos"; then
    HEADERS_PKG="linux-cachyos-headers"
  elif echo "$KERNEL" | grep -q "zen"; then
    HEADERS_PKG="linux-zen-headers"
  elif echo "$KERNEL" | grep -q "lts"; then
    HEADERS_PKG="linux-lts-headers"
  elif echo "$KERNEL" | grep -q "hardened"; then
    HEADERS_PKG="linux-hardened-headers"
  else
    HEADERS_PKG="linux-headers"
  fi

  if [[ "${PKG_MANAGER:-pacman}" == "apt" ]]; then
    HEADERS_PKG="linux-headers-$(uname -r)"
  fi
  log "Kernel headers package: $HEADERS_PKG"

  if [[ "${PKG_MANAGER:-pacman}" == "pacman" ]]; then
    check_kernel_header_mismatch "$KERNEL" "$HEADERS_PKG"
  fi
}

detect_compiler() {
  KERNEL_CONFIG="/boot/config-$(uname -r)"

  # Check standard /boot/ path first
  if [[ -f "$KERNEL_CONFIG" ]]; then
    if grep -q "CONFIG_CC_IS_CLANG=y" "$KERNEL_CONFIG"; then
      KERNEL_COMPILER="clang"
    elif grep -q "CONFIG_CC_IS_GCC=y" "$KERNEL_CONFIG"; then
      KERNEL_COMPILER="gcc"
    fi
  # Fallback to Arch/CachyOS compressed config in memory
  elif [[ -f "/proc/config.gz" ]]; then
    if zgrep -q "CONFIG_CC_IS_CLANG=y" /proc/config.gz; then
      KERNEL_COMPILER="clang"
    elif zgrep -q "CONFIG_CC_IS_GCC=y" /proc/config.gz; then
      KERNEL_COMPILER="gcc"
    fi
  else
    KERNEL_COMPILER=""
    warn "Cannot determine kernel compiler from $KERNEL_CONFIG or /proc/config.gz — will auto-detect"
  fi

  if [[ "$KERNEL_COMPILER" == "clang" ]] && clang --version &>/dev/null; then
    COMPILER="clang"
    LLVM_FLAG="LLVM=1"
    log "Compiler: Clang/LLVM (matches kernel build)"
  elif [[ "$KERNEL_COMPILER" == "gcc" ]]; then
    COMPILER="gcc"
    LLVM_FLAG=""
    log "Compiler: GCC (matches kernel build)"
  elif [[ "$KERNEL_COMPILER" == "clang" ]] && ! clang --version &>/dev/null; then
    COMPILER="gcc"
    LLVM_FLAG=""
    warn "Kernel was built with Clang but clang is not installed — using GCC (may fail)"
    warn "Install clang: sudo pacman -S clang llvm lld"
  elif clang --version &>/dev/null; then
    COMPILER="clang"
    LLVM_FLAG="LLVM=1"
    log "Compiler: Clang/LLVM"
  else
    COMPILER="gcc"
    LLVM_FLAG=""
    log "Compiler: GCC"
  fi
}

install_base_deps() {
  step "Installing base dependencies"
  if [[ "${PKG_MANAGER:-pacman}" == "pacman" ]]; then
    sudo pacman -S --needed --noconfirm git base-devel dkms python python-gobject python-pip gtk4 libadwaita lm_sensors "$HEADERS_PKG" || {
      err "pacman install failed. Check your internet or mirrors."
      exit 1
    }
    if [[ "$COMPILER" == "clang" ]]; then
      sudo pacman -S --needed --noconfirm clang llvm lld || true
      log "Clang/LLVM installed"
    fi
  elif [[ "${PKG_MANAGER:-pacman}" == "apt" ]]; then
    sudo apt-get update -q
    sudo apt-get install -y git build-essential dkms python3 python3-gi python3-pip gir1.2-gtk-4.0 gir1.2-adw-1 lm-sensors "$HEADERS_PKG" || {
      err "apt install failed. Check your internet connection."
      exit 1
    }
  elif [[ "${PKG_MANAGER:-pacman}" == "dnf" ]]; then
    sudo dnf install -y git dkms python3 python3-gobject gtk4 libadwaita lm_sensors "kernel-devel-$(uname -r)" || {
      err "dnf install failed."
      exit 1
    }
  fi
  log "Base dependencies installed"
}

install_python_deps() {
  step "Installing Python dependencies"
  sudo pacman -S --needed --noconfirm python-gobject python-cairo 2>/dev/null || true

  if command -v nvidia-smi &>/dev/null; then
    log "nvidia-smi found — GPU monitoring enabled"
  else
    warn "nvidia-smi not in PATH — install nvidia-utils for GPU monitoring"
  fi

  log "Python dependencies ready"
}

install_linuwu_sense() {
  step "Installing linuwu_sense kernel module (via DKMS)"

  WORK_DIR="/tmp/linuwu-sense-build"
  rm -rf "$WORK_DIR"

  log "Cloning latest Linuwu-Sense source from GitHub..."
  git clone https://github.com/0x7375646F/Linuwu-Sense.git "$WORK_DIR" || {
    err "Failed to clone Linuwu-Sense. Check your internet connection or git."
    exit 1
  }

  cd "$WORK_DIR"

  MOD_VER=$(grep -oP '(?<=VERSION = ).*' Makefile 2>/dev/null | head -1 || echo "1.0.0")
  log "Module version: $MOD_VER"

  sudo rm -rf "/usr/src/linuwu-sense-$MOD_VER"
  sudo mkdir -p "/usr/src/linuwu-sense-$MOD_VER"
  sudo cp -r . "/usr/src/linuwu-sense-$MOD_VER/"

  # Streamlined dkms.conf logic. Lets dkms handle the standard kernel build paths
  sudo tee "/usr/src/linuwu-sense-$MOD_VER/dkms.conf" > /dev/null <<EOF
PACKAGE_NAME="linuwu-sense"
PACKAGE_VERSION="$MOD_VER"
MAKE[0]="make ${LLVM_FLAG}"
CLEAN="make clean"
BUILT_MODULE_NAME[0]="linuwu_sense"
BUILT_MODULE_LOCATION[0]="src/"
DEST_MODULE_LOCATION[0]="/kernel/drivers/platform/x86"
AUTOINSTALL="yes"
EOF
  log "Created dynamic dkms.conf"

  # Clean up old iterations in case this is an update
  sudo dkms remove -m linuwu-sense -v "$MOD_VER" --all 2>/dev/null || true

  sudo dkms add -m linuwu-sense -v "$MOD_VER" 2>/dev/null || true
  sudo dkms build -m linuwu-sense -v "$MOD_VER" || {
    err "DKMS build failed. Make sure kernel headers are installed for $(uname -r)"
    echo -e "  Try: ${YELLOW}sudo pacman -S $HEADERS_PKG${NC}"
    exit 1
  }
  sudo dkms install -m linuwu-sense -v "$MOD_VER" || {
    err "DKMS install failed."
    exit 1
  }
  log "linuwu_sense DKMS module installed"

  # Hardware settings configuration
  sudo tee /etc/modprobe.d/acer-wmi-blacklist.conf > /dev/null <<EOF
# Blacklisted by PredatorSense Linux installer
# linuwu_sense replaces this module for Predator/Nitro laptops
blacklist acer_wmi
EOF

  echo "options linuwu_sense predator_v4=Y" | sudo tee /etc/modprobe.d/linuwu-sense-options.conf > /dev/null
  echo "linuwu_sense" | sudo tee /etc/modules-load.d/linuwu_sense.conf > /dev/null

  log "Blacklisted legacy acer_wmi module"
  log "Set predator_v4=Y module parameter and enabled boot loading"

  sudo modprobe -r acer_wmi 2>/dev/null || true
  sudo modprobe linuwu_sense && log "linuwu_sense module loaded" || warn "Module load failed — may need reboot"

  cd - >/dev/null
  rm -rf "$WORK_DIR"
}

install_battery_module() {
  step "Installing acer-wmi-battery DKMS module (80% charge limit)"

  if command -v paru &>/dev/null; then
    paru -S --needed --noconfirm acer-wmi-battery-dkms 2>/dev/null && {
      log "acer-wmi-battery installed via paru"
      return
    }
  elif command -v yay &>/dev/null; then
    yay -S --needed --noconfirm acer-wmi-battery-dkms 2>/dev/null && {
      log "acer-wmi-battery installed via yay"
      return
    }
  fi

  warn "AUR helper not found — battery module requires manual AUR install"
  warn "Install: paru -S acer-wmi-battery-dkms"
}

install_envycontrol() {
  step "Installing EnvyControl (GPU mode switcher)"

  if command -v envycontrol &>/dev/null; then
    log "EnvyControl already installed"
    return
  fi

  if command -v paru &>/dev/null; then
    paru -S --needed --noconfirm envycontrol 2>/dev/null && log "EnvyControl installed" && return
  elif command -v yay &>/dev/null; then
    yay -S --needed --noconfirm envycontrol 2>/dev/null && log "EnvyControl installed" && return
  fi

  pip install envycontrol --break-system-packages 2>/dev/null && log "EnvyControl installed via pip" || \
    warn "EnvyControl install failed — GPU mode switching unavailable"
}

install_sensors() {
  step "Configuring lm-sensors"
  sudo sensors-detect --auto 2>/dev/null || true
  log "lm-sensors configured"
}

install_app() {
  step "Installing PredatorSense Linux GUI"

  INSTALL_DIR="$HOME/.local/share/predatorsense-linux"
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$INSTALL_DIR" "$BIN_DIR"

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cp "$SCRIPT_DIR/src/predatorsense.py" "$INSTALL_DIR/"

  DE="${XDG_CURRENT_DESKTOP:-unknown}"
  log "Desktop environment: $DE"

  if echo "$DE" | grep -qi "gnome"; then
    sudo pacman -S --needed --noconfirm libadwaita 2>/dev/null || true
  elif echo "$DE" | grep -qi "kde\|plasma"; then
    warn "KDE Plasma detected — libadwaita is optional, app will use GTK4 fallback"
    sudo pacman -S --needed --noconfirm python-evdev 2>/dev/null || true
  fi

  cat > "$BIN_DIR/predatorsense" <<'LAUNCHEOF'
#!/usr/bin/env bash
exec python3 "$HOME/.local/share/predatorsense-linux/predatorsense.py" "$@"
LAUNCHEOF
  chmod +x "$BIN_DIR/predatorsense"

  mkdir -p "$HOME/.local/share/applications"
  cat > "$HOME/.local/share/applications/predatorsense.desktop" <<DESKTOPEOF
[Desktop Entry]
Version=1.0
Type=Application
Name=PredatorSense Linux
Comment=Fan, RGB, and power control for Acer Predator PHN16S-71
Exec=$BIN_DIR/predatorsense
Icon=input-gaming
Categories=System;Settings;HardwareSettings;
Keywords=acer;predator;fan;rgb;gaming;
StartupNotify=true
DESKTOPEOF

  for RC in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config/fish/config.fish"; do
    if [[ -f "$RC" ]] && ! grep -q '\.local/bin' "$RC"; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
    fi
  done

  mkdir -p "$HOME/.config/autostart"
  cat > "$HOME/.config/autostart/predatorsense.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=PredatorSense Linux
Exec=$BIN_DIR/predatorsense
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Comment=PredatorSense Linux — runs in background for Predator key support
StartupNotify=false
EOF
  log "Autostart entry created"

  mkdir -p "$HOME/.config/systemd/user"
  cat > "$HOME/.config/systemd/user/predatorsense.service" <<EOF
[Unit]
Description=PredatorSense Linux background daemon
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=$BIN_DIR/predatorsense
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable predatorsense.service
  log "Systemd user service installed and enabled"

  log "App installed to $INSTALL_DIR"
  log "Launcher: $BIN_DIR/predatorsense"
  log "Desktop entry created"
}

setup_udev() {
  step "Setting up udev rules (allow user access to sysfs controls)"
  sudo tee /etc/udev/rules.d/99-predatorsense.rules > /dev/null <<'EOF'
# PredatorSense Linux — Allow group 'users' to write fan/RGB/battery controls
SUBSYSTEM=="module", KERNEL=="linuwu_sense", RUN+="/bin/chmod -R a+rw /sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/"
ACTION=="add", SUBSYSTEM=="platform", KERNEL=="acer-wmi", RUN+="/bin/chmod -R a+rw /sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/"
EOF
  sudo udevadm control --reload-rules
  sudo udevadm trigger
  log "udev rules installed"
}

setup_sudo_rules() {
  step "Setting up passwordless sudo for specific hardware controls"
  CURRENT_USER=$(whoami)
  {
    printf "# PredatorSense Linux — targeted sudo rules\n"
    printf "%s ALL=(ALL) NOPASSWD: /usr/bin/tee /sys/module/linuwu_sense/*\n" "$CURRENT_USER"
    printf "%s ALL=(ALL) NOPASSWD: /usr/bin/tee /sys/firmware/acpi/platform_profile\n" "$CURRENT_USER"
    printf "%s ALL=(ALL) NOPASSWD: /usr/bin/tee /sys/bus/platform/drivers/acer-wmi/*\n" "$CURRENT_USER"
    printf "%s ALL=(ALL) NOPASSWD: /usr/bin/tee /sys/class/powercap/*\n" "$CURRENT_USER"
    printf "%s ALL=(ALL) NOPASSWD: /usr/bin/cat /sys/class/powercap/*\n" "$CURRENT_USER"
    printf "%s ALL=(ALL) NOPASSWD: /usr/bin/nvidia-smi\n" "$CURRENT_USER"
    printf "%s ALL=(ALL) NOPASSWD: /usr/bin/modprobe linuwu_sense\n" "$CURRENT_USER"
    printf "%s ALL=(ALL) NOPASSWD: /usr/bin/modprobe -r linuwu_sense\n" "$CURRENT_USER"
    printf "%s ALL=(ALL) NOPASSWD: /usr/bin/envycontrol\n" "$CURRENT_USER"
    printf "%s ALL=(ALL) NOPASSWD: /usr/bin/systemctl daemon-reload\n" "$CURRENT_USER"
    printf "%s ALL=(ALL) NOPASSWD: /usr/bin/systemctl enable predatorsense-power.service\n" "$CURRENT_USER"
    printf "%s ALL=(ALL) NOPASSWD: /usr/bin/systemctl reboot\n" "$CURRENT_USER"
  } | sudo tee /etc/sudoers.d/predatorsense > /dev/null
  sudo chmod 440 /etc/sudoers.d/predatorsense
  log "Sudo rules configured for user: $CURRENT_USER"
}

setup_input_group() {
  step "Adding user to input group (required for Predator key)"
  if groups "$USER" | grep -q "input"; then
    log "User already in input group"
  else
    sudo usermod -aG input "$USER"
    log "Added $USER to input group — reboot required for key to work"
    warn "The Predator Logo Key will work after reboot"
  fi
}

post_install_summary() {
  echo ""
  echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║         Installation Complete! 🎮                 ║${NC}"
  echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${GREEN}Installed components:${NC}"
  echo "    • linuwu_sense kernel module (DKMS, auto-rebuilds on kernel update)"
  echo "    • acer_wmi blacklisted (avoids conflicts)"
  echo "    • PredatorSense Linux GUI"
  echo "    • Desktop launcher (search 'PredatorSense' in your app menu)"
  echo "    • EnvyControl (GPU mode switching)"
  echo "    • lm-sensors (CPU/temperature monitoring)"
  echo "    • udev rules + sudo rules (passwordless hardware control)"
  echo ""
  echo -e "  ${YELLOW}Launch the app:${NC}"
  echo "    predatorsense"
  echo "    (or search 'PredatorSense' in GNOME app grid)"
  echo ""
  echo -e "  ${YELLOW}⚠ A reboot is recommended to ensure the driver${NC}"
  echo -e "  ${YELLOW}  loads cleanly and udev rules take effect.${NC}"
  echo ""
  read -rp "  Reboot now? [y/N] " answer
  if [[ "${answer,,}" == "y" ]]; then
    sudo reboot
  fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
banner
check_root
check_distro
check_hardware
detect_kernel_headers
detect_compiler

echo -e "  ${BOLD}This will install:${NC}"
echo "    • linuwu_sense kernel module (DKMS)"
echo "    • acer-wmi-battery module"
echo "    • EnvyControl GPU switcher"
echo "    • Python GTK4 GUI app"
echo "    • lm-sensors, nvidia-utils"
echo ""
read -rp "  Proceed? [Y/n] " confirm
[[ "${confirm,,}" == "n" ]] && { echo "  Aborted."; exit 0; }

install_base_deps
install_python_deps
install_linuwu_sense
install_battery_module
install_envycontrol
install_sensors
install_app
setup_udev
setup_sudo_rules
setup_input_group
post_install_summary
