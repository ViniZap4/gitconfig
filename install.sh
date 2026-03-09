#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Detect OS ──────────────────────────────────────────────────────
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
      else
        echo "linux"
      fi
      ;;
    *) echo "unknown" ;;
  esac
}

detect_pm() {
  if command -v brew &>/dev/null; then echo "brew"
  elif command -v apt &>/dev/null; then echo "apt"
  elif command -v pacman &>/dev/null; then echo "pacman"
  elif command -v dnf &>/dev/null; then echo "dnf"
  elif command -v zypper &>/dev/null; then echo "zypper"
  elif command -v nix-env &>/dev/null; then echo "nix"
  else echo "unknown"
  fi
}

OS=$(detect_os)
PM=$(detect_pm)
echo "→ Detected OS: $OS, Package Manager: $PM"

# ── Install dependencies ──────────────────────────────────────────
install_deps() {
  case "$PM" in
    brew)   brew install git delta git-lfs lazygit 2>/dev/null || true ;;
    apt)    sudo apt-get update -qq && sudo apt-get install -y git git-delta git-lfs 2>/dev/null || true ;;
    pacman) sudo pacman -S --noconfirm --needed git git-delta git-lfs lazygit 2>/dev/null || true ;;
    dnf)    sudo dnf install -y git git-delta git-lfs 2>/dev/null || true ;;
    zypper) sudo zypper install -y git git-delta git-lfs 2>/dev/null || true ;;
  esac

  # delta fallback: install via cargo if not available
  if ! command -v delta &>/dev/null; then
    if command -v cargo &>/dev/null; then
      echo "→ delta not found, installing via cargo..."
      cargo install git-delta 2>/dev/null || true
    else
      echo "→ delta not available via $PM. Install cargo or download from:"
      echo "  https://github.com/dandavison/delta/releases"
    fi
  fi
}

echo "→ Installing dependencies..."
install_deps

# ── Install lazygit (binary fallback for distros without packages) ─
install_lazygit() {
  if command -v lazygit &>/dev/null; then
    echo "→ lazygit already installed"
    return
  fi

  case "$PM" in
    brew|pacman)
      ;; # already handled in install_deps
    dnf)
      echo "→ Installing lazygit via COPR..."
      sudo dnf copr enable -y atim/lazygit 2>/dev/null || true
      sudo dnf install -y lazygit 2>/dev/null || true
      ;;
    *)
      echo "→ Installing lazygit from GitHub releases..."
      LAZYGIT_VERSION=$(curl -fsSL "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*' 2>/dev/null || echo "")
      if [[ -n "$LAZYGIT_VERSION" ]]; then
        ARCH="$(uname -m)"
        case "$ARCH" in
          x86_64|amd64) ARCH="x86_64" ;;
          arm64|aarch64) ARCH="arm64" ;;
        esac
        curl -fsSLo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_${ARCH}.tar.gz"
        tar -xzf /tmp/lazygit.tar.gz -C /tmp lazygit
        sudo install /tmp/lazygit /usr/local/bin/lazygit
        rm -f /tmp/lazygit /tmp/lazygit.tar.gz
        echo "✔ lazygit ${LAZYGIT_VERSION} installed"
      else
        echo "→ Could not determine lazygit version. Install manually:"
        echo "  https://github.com/jesseduffield/lazygit#installation"
      fi
      ;;
  esac
}

install_lazygit

# ── Create symlink ────────────────────────────────────────────────
TARGET="$HOME/.gitconfig"

if [[ -f "$TARGET" && ! -L "$TARGET" ]]; then
  BACKUP="${TARGET}.backup.$(date +%Y%m%d%H%M%S)"
  echo "→ Backing up existing $TARGET to $BACKUP"
  mv "$TARGET" "$BACKUP"
elif [[ -L "$TARGET" ]]; then
  rm "$TARGET"
fi

ln -s "${SCRIPT_DIR}/.gitconfig" "$TARGET"
echo "✔ Linked .gitconfig → $TARGET"

# ── Create .gitconfig.local if it doesn't exist ──────────────────
LOCAL="$HOME/.gitconfig.local"
if [[ ! -f "$LOCAL" ]]; then
  echo "→ Creating $LOCAL from template..."
  cp "${SCRIPT_DIR}/.gitconfig.local.example" "$LOCAL"
  echo "⚠ Please edit $LOCAL with your personal info (name, email)"
fi
