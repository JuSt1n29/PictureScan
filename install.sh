#!/usr/bin/env bash
set -Eeuo pipefail

PROGRAM_FILE="main.py"
WORKDIR="$(cd "$(dirname "$0")" && pwd)"
TMPDIR_INSTALL="/tmp/stego_installer_build"

green='\033[0;32m'
yellow='\033[1;33m'
red='\033[0;31m'
blue='\033[0;34m'
nc='\033[0m'

info()  { echo -e "${blue}[INFO]${nc} $*"; }
ok()    { echo -e "${green}[OK]${nc} $*"; }
warn()  { echo -e "${yellow}[WARN]${nc} $*"; }
fail()  { echo -e "${red}[ERR]${nc} $*"; }

have() { command -v "$1" >/dev/null 2>&1; }

if [[ $EUID -eq 0 ]]; then
  fail "Не запускай этот скрипт через sudo/root."
  echo "Запусти так: ./install.sh"
  exit 1
fi

export PATH="$HOME/.local/bin:$PATH"

detect_distro() {
  . /etc/os-release
  case "${ID:-unknown}" in
    ubuntu|debian|linuxmint|pop) DISTRO_FAMILY="debian" ;;
    arch|manjaro|endeavouros) DISTRO_FAMILY="arch" ;;
    fedora) DISTRO_FAMILY="fedora" ;;
    opensuse-tumbleweed|opensuse-leap|suse) DISTRO_FAMILY="opensuse" ;;
    *) DISTRO_FAMILY="unknown" ;;
  esac
  info "Detected distro: ${ID:-unknown} ($DISTRO_FAMILY)"
}

pkg_install() {
  case "$DISTRO_FAMILY" in
    debian) sudo apt update && sudo apt install -y "$@" ;;
    arch) sudo pacman -Sy --noconfirm "$@" ;;
    fedora) sudo dnf install -y "$@" ;;
    opensuse) sudo zypper install -y "$@" ;;
    *) fail "Unsupported distro"; exit 1 ;;
  esac
}

ensure_yay() {
  [[ "$DISTRO_FAMILY" != "arch" ]] && return 0
  command -v yay >/dev/null 2>&1 && return 0
  git clone https://aur.archlinux.org/yay.git /tmp/yay-build
  cd /tmp/yay-build
  makepkg -si --noconfirm
  cd "$WORKDIR"
}

aur_install() {
  ensure_yay
  yay -S --noconfirm "$1"
}

ensure_base_build_tools() {
  case "$DISTRO_FAMILY" in
    arch) pkg_install python python-pip git curl file binutils util-linux ruby base-devel cmake pkgconf ;;
    debian) pkg_install python3 python3-pip git curl file binutils util-linux ruby ruby-dev build-essential cmake pkg-config ;;
    fedora) pkg_install python3 python3-pip git curl file binutils util-linux ruby ruby-devel gcc gcc-c++ make cmake pkgconf-pkg-config ;;
    opensuse) pkg_install python3 python3-pip git curl file binutils util-linux ruby ruby-devel gcc gcc-c++ make cmake pkg-config ;;
  esac
}

install_stegoveritas() {
  have stegoveritas && return 0
  if [[ "$DISTRO_FAMILY" == "arch" ]]; then
    aur_install python-stegoveritas 2>/dev/null || true
    have stegoveritas && return 0
  fi
  python3 -m pip install --user --upgrade stegoveritas
  export PATH="$HOME/.local/bin:$PATH"
  command -v stegoveritas_install_deps >/dev/null 2>&1 && stegoveritas_install_deps || true
}

install_pngcheck() {
  have pngcheck && return 0
  if [[ "$DISTRO_FAMILY" == "arch" ]]; then
    aur_install pngcheck
  else
    pkg_install pngcheck
  fi
}

install_jpeginfo() {
  have jpeginfo && return 0
  if [[ "$DISTRO_FAMILY" == "arch" ]]; then
    aur_install jpeginfo
  else
    pkg_install jpeginfo
  fi
}

install_zbar() {
  if have zbarimg || have zbarcam; then
    return 0
  fi
  case "$DISTRO_FAMILY" in
    debian) pkg_install zbar-tools ;;
    arch|fedora|opensuse) pkg_install zbar ;;
  esac
}

detect_distro
ensure_base_build_tools

have exiftool || pkg_install perl-image-exiftool || true
have exiv2 || pkg_install exiv2 || true
have file || pkg_install file || true
have strings || pkg_install binutils || true
have hexdump || pkg_install util-linux || true
have steghide || pkg_install steghide || true
have stegseek || pkg_install stegseek || true
have zsteg || gem install zsteg || true
install_stegoveritas || true
have binwalk || pkg_install binwalk || true
have foremost || pkg_install foremost || true
install_pngcheck || true
install_jpeginfo || true
install_zbar || true

echo
for pair in \
  "exiftool exiftool" \
  "exiv2 exiv2" \
  "file file" \
  "strings strings" \
  "hexdump hexdump" \
  "steghide steghide" \
  "stegseek stegseek" \
  "zsteg zsteg" \
  "stegoveritas stegoveritas" \
  "binwalk binwalk" \
  "foremost foremost" \
  "pngcheck pngcheck" \
  "jpeginfo jpeginfo" \
  "zbar zbarimg"
do
  set -- $pair
  if command -v "$2" >/dev/null 2>&1; then
    echo "[OK] $1 -> $2"
  else
    echo "[ERR] $1 NOT FOUND"
  fi
done

if [[ -f "$WORKDIR/$PROGRAM_FILE" ]]; then
  python3 "$WORKDIR/$PROGRAM_FILE"
else
  echo "[WARN] $PROGRAM_FILE not found in: $WORKDIR"
fi
