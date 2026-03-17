#!/usr/bin/env bash
set -Eeuo pipefail

PROGRAM_FILE="main.py"
WORKDIR="$(cd "$(dirname "$0")" && pwd)"
TMPDIR_INSTALL="$HOME/.cache/stego_installer_build"

if [[ -t 1 ]]; then
  green=$'\e[0;32m'
  yellow=$'\e[1;33m'
  red=$'\e[0;31m'
  blue=$'\e[0;34m'
  nc=$'\e[0m'
else
  green=''
  yellow=''
  red=''
  blue=''
  nc=''
fi

info()  { printf "%b[INFO]%b %s\n" "$blue" "$nc" "$*"; }
ok()    { printf "%b[OK]%b %s\n" "$green" "$nc" "$*"; }
warn()  { printf "%b[WARN]%b %s\n" "$yellow" "$nc" "$*"; }
fail()  { printf "%b[ERR]%b %s\n" "$red" "$nc" "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

if [[ $EUID -eq 0 ]]; then
  fail "Don't run this script by sudo/root."
  echo "Run this way: ./install.sh"
  exit 1
fi

mkdir -p "$TMPDIR_INSTALL"
export PATH="$HOME/.local/bin:$PATH"

detect_distro() {
  if [[ ! -f /etc/os-release ]]; then
    fail "Cannot detect distro."
    exit 1
  fi

  . /etc/os-release

  case "${ID:-unknown}" in
    ubuntu|debian|linuxmint|pop)
      DISTRO_FAMILY="debian"
      ;;
    arch|manjaro|endeavouros)
      DISTRO_FAMILY="arch"
      ;;
    fedora)
      DISTRO_FAMILY="fedora"
      ;;
    opensuse-tumbleweed|opensuse-leap|suse)
      DISTRO_FAMILY="opensuse"
      ;;
    *)
      if [[ "${ID_LIKE:-}" == *debian* ]]; then
        DISTRO_FAMILY="debian"
      elif [[ "${ID_LIKE:-}" == *arch* ]]; then
        DISTRO_FAMILY="arch"
      elif [[ "${ID_LIKE:-}" == *fedora* || "${ID_LIKE:-}" == *rhel* ]]; then
        DISTRO_FAMILY="fedora"
      elif [[ "${ID_LIKE:-}" == *suse* ]]; then
        DISTRO_FAMILY="opensuse"
      else
        DISTRO_FAMILY="unknown"
      fi
      ;;
  esac

  info "Detected distro: ${ID:-unknown} ($DISTRO_FAMILY)"

  if [[ "$DISTRO_FAMILY" == "unknown" ]]; then
    fail "Unsupported distro."
    exit 1
  fi
}

pkg_install() {
  case "$DISTRO_FAMILY" in
    debian)
      sudo apt update
      sudo apt install -y "$@"
      ;;
    arch)
      sudo pacman -Sy --noconfirm "$@"
      ;;
    fedora)
      sudo dnf install -y "$@"
      ;;
    opensuse)
      sudo zypper install -y "$@"
      ;;
    *)
      fail "Unsupported distro"
      exit 1
      ;;
  esac
}

ensure_yay() {
  [[ "$DISTRO_FAMILY" != "arch" ]] && return 0

  if have yay; then
    ok "yay found"
    return 0
  fi

  warn "yay not found, installing..."
  rm -rf "$TMPDIR_INSTALL/yay-build"
  git clone https://aur.archlinux.org/yay.git "$TMPDIR_INSTALL/yay-build"
  cd "$TMPDIR_INSTALL/yay-build"
  makepkg -si --noconfirm
  cd "$WORKDIR"
}

aur_install() {
  ensure_yay
  yay -S --noconfirm "$1"
}

ensure_base_build_tools() {
  info "Installing base dependencies..."

  case "$DISTRO_FAMILY" in
    arch)
      pkg_install python python-pip git curl file binutils util-linux ruby base-devel cmake pkgconf
      ;;
    debian)
      pkg_install python3 python3-pip python3-venv pipx git curl file binutils util-linux ruby ruby-dev build-essential cmake pkg-config
      ;;
    fedora)
      pkg_install python3 python3-pip git curl file binutils util-linux ruby ruby-devel gcc gcc-c++ make cmake pkgconf-pkg-config libmcrypt-devel zlib-devel
      ;;
    opensuse)
      pkg_install python3 python3-pip git curl file binutils util-linux ruby ruby-devel gcc gcc-c++ make cmake pkg-config
      ;;
  esac
}

install_exiftool() {
  have exiftool && return 0
  case "$DISTRO_FAMILY" in
    debian)
      pkg_install exiftool || pkg_install libimage-exiftool-perl
      ;;
    arch)
      pkg_install perl-image-exiftool
      ;;
    fedora)
      pkg_install perl-Image-ExifTool
      ;;
    opensuse)
      pkg_install exiftool
      ;;
  esac
}

install_exiv2() { have exiv2 || pkg_install exiv2; }
install_file_tool() { have file || pkg_install file; }
install_strings() { have strings || pkg_install binutils; }
install_hexdump() { have hexdump || pkg_install util-linux; }
install_steghide() { have steghide || pkg_install steghide; }

install_stegseek_deb() {
  info "Installing stegseek from .deb release..."
  mkdir -p "$TMPDIR_INSTALL"
  local deb_file="$TMPDIR_INSTALL/stegseek_0.6-1.deb"
  curl -L -o "$deb_file" "https://github.com/RickdeJager/stegseek/releases/download/v0.6/stegseek_0.6-1.deb"
  sudo apt install -y "$deb_file"
}

clone_and_build_stegseek() {
  info "Installing stegseek from GitHub source..."

  if [[ "$DISTRO_FAMILY" == "fedora" ]]; then
    pkg_install libmcrypt-devel zlib-devel
  fi

  mkdir -p "$TMPDIR_INSTALL"
  rm -rf "$TMPDIR_INSTALL/stegseek"
  git clone https://github.com/RickdeJager/stegseek.git "$TMPDIR_INSTALL/stegseek"
  cd "$TMPDIR_INSTALL/stegseek"
  mkdir -p build
  cd build
  cmake ..
  make -j"$(nproc)"
  sudo make install
  cd "$WORKDIR"
}

install_stegseek() {
  have stegseek && return 0

  if [[ "$DISTRO_FAMILY" == "debian" ]]; then
    install_stegseek_deb || true
    have stegseek && return 0
  fi

  if [[ "$DISTRO_FAMILY" == "arch" ]]; then
    pkg_install stegseek 2>/dev/null || true
    have stegseek && return 0
    aur_install stegseek 2>/dev/null || true
    have stegseek && return 0
  fi

  clone_and_build_stegseek
}

install_zsteg() {
  have zsteg && return 0

  if [[ "$DISTRO_FAMILY" == "arch" ]]; then
    aur_install zsteg 2>/dev/null || true
    have zsteg && return 0
  fi

  gem install --user-install zsteg

  local ruby_user_bin
  ruby_user_bin="$(ruby -e 'puts Gem.user_dir')/bin"
  export PATH="$ruby_user_bin:$PATH"
}

install_stegoveritas() {
  have stegoveritas && return 0

  if [[ "$DISTRO_FAMILY" == "arch" ]]; then
    aur_install python-stegoveritas 2>/dev/null || true
    have stegoveritas && return 0
  fi

  if [[ "$DISTRO_FAMILY" == "debian" ]]; then
    if have pipx; then
      pipx install stegoveritas || true
      export PATH="$HOME/.local/bin:$PATH"
      have stegoveritas_install_deps && stegoveritas_install_deps || true
      return 0
    fi

    python3 -m venv "$HOME/.venvs/stegoveritas"
    "$HOME/.venvs/stegoveritas/bin/pip" install --upgrade pip
    "$HOME/.venvs/stegoveritas/bin/pip" install stegoveritas
    mkdir -p "$HOME/.local/bin"
    ln -sf "$HOME/.venvs/stegoveritas/bin/stegoveritas" "$HOME/.local/bin/stegoveritas"
    ln -sf "$HOME/.venvs/stegoveritas/bin/stegoveritas_install_deps" "$HOME/.local/bin/stegoveritas_install_deps"
    export PATH="$HOME/.local/bin:$PATH"
    have stegoveritas_install_deps && stegoveritas_install_deps || true
    return 0
  fi

  python3 -m pip install --user --upgrade stegoveritas
  export PATH="$HOME/.local/bin:$PATH"

  if have stegoveritas_install_deps; then
    stegoveritas_install_deps || true
  fi
}

install_binwalk() { have binwalk || pkg_install binwalk; }
install_foremost() { have foremost || pkg_install foremost; }

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
  if have zbarimg || have zbarcam || have zbar; then
    return 0
  fi

  case "$DISTRO_FAMILY" in
    debian) pkg_install zbar-tools ;;
    arch|fedora|opensuse) pkg_install zbar ;;
  esac
}

verify_all_tools() {
  echo

  export PATH="$HOME/.local/bin:$PATH"
  local ruby_user_bin
  ruby_user_bin="$(ruby -e 'puts Gem.user_dir')/bin"
  export PATH="$ruby_user_bin:$PATH"

  local missing=0

  local tool_names=(
    "exiftool"
    "exiv2"
    "file"
    "strings"
    "hexdump"
    "steghide"
    "stegseek"
    "zsteg"
    "stegoveritas"
    "binwalk"
    "foremost"
    "pngcheck"
    "jpeginfo"
    "zbar"
  )

  local tool_bins=(
    "exiftool"
    "exiv2"
    "file"
    "strings"
    "hexdump"
    "steghide"
    "stegseek"
    "zsteg"
    "stegoveritas"
    "binwalk"
    "foremost"
    "pngcheck"
    "jpeginfo"
    "zbarimg|zbarcam|zbar"
  )

  info "Checking installed tools..."

  for i in "${!tool_names[@]}"; do
    local name="${tool_names[$i]}"
    local bins="${tool_bins[$i]}"
    local found_bin=""
    IFS='|' read -r -a variants <<< "$bins"

    for bin in "${variants[@]}"; do
      if have "$bin"; then
        found_bin="$bin"
        break
      fi
    done

    if [[ -n "$found_bin" ]]; then
      ok "$name -> $found_bin"
    else
      fail "$name NOT FOUND"
      missing=1
    fi
  done

  echo
  if [[ "$missing" -eq 0 ]]; then
    ok "All required tools are installed."
    return 0
  else
    warn "Some required tools are still missing."
    return 1
  fi
}

find_program_file() {
  local candidates=(
    "$WORKDIR/$PROGRAM_FILE"
    "$WORKDIR/src/$PROGRAM_FILE"
    "$WORKDIR/app/$PROGRAM_FILE"
  )

  for f in "${candidates[@]}"; do
    if [[ -f "$f" ]]; then
      echo "$f"
      return 0
    fi
  done

  return 1
}

run_program() {
  local target=""
  if target="$(find_program_file)"; then
    echo
    info "Launching $target ..."
    python3 "$target"
  else
    warn "$PROGRAM_FILE not found in: $WORKDIR"
  fi
}

main() {
  detect_distro
  ensure_base_build_tools

  install_exiftool || warn "Failed: exiftool"
  install_exiv2 || warn "Failed: exiv2"
  install_file_tool || warn "Failed: file"
  install_strings || warn "Failed: strings"
  install_hexdump || warn "Failed: hexdump"
  install_steghide || warn "Failed: steghide"
  install_stegseek || warn "Failed: stegseek"
  install_zsteg || warn "Failed: zsteg"
  install_stegoveritas || warn "Failed: stegoveritas"
  install_binwalk || warn "Failed: binwalk"
  install_foremost || warn "Failed: foremost"
  install_pngcheck || warn "Failed: pngcheck"
  install_jpeginfo || warn "Failed: jpeginfo"
  install_zbar || warn "Failed: zbar"

  verify_all_tools || true
  run_program
}

main "$@"
