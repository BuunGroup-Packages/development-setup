#!/usr/bin/env bash
set -euo pipefail
# ── setup.sh ── One-liner bootstrap for development-setup ────────────────────
#
# curl -fsSL https://raw.githubusercontent.com/buun-group/development-setup/main/setup.sh | bash
#
# Installs just (if missing), clones the repo, and runs just install.

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
NC=$'\033[0m'

info()    { echo -e "${CYAN}$*${NC}"; }
success() { echo -e "${GREEN}$*${NC}"; }
error()   { echo -e "${RED}$*${NC}" >&2; }

REPO_URL="https://github.com/buun-group/development-setup.git"
CLONE_DIR="${HOME}/.local/share/development-setup"

echo ""
echo -e "${BOLD}${CYAN}  Buun Group — Development Setup${NC}"
echo -e "${DIM}  $(printf '─%.0s' {1..34})${NC}"
echo ""

# ── Platform check ───────────────────────────────────────────────────────────

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || -n "${WINDIR:-}" ]] && ! grep -qi microsoft /proc/version 2>/dev/null; then
  error "Native Windows is not supported. Please run inside WSL2."
  error "Install WSL: wsl --install"
  exit 1
fi

# ── Install just ─────────────────────────────────────────────────────────────

if command -v just &>/dev/null; then
  success "  just already installed"
else
  info "  Installing just..."

  if command -v brew &>/dev/null; then
    brew install just
  elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm just
  elif command -v cargo &>/dev/null; then
    cargo install just
  else
    # Official installer
    mkdir -p "${HOME}/.local/bin"
    curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh \
      | bash -s -- --to "${HOME}/.local/bin"

    # Ensure PATH
    if ! echo "$PATH" | grep -q "${HOME}/.local/bin"; then
      export PATH="${HOME}/.local/bin:${PATH}"
    fi
  fi

  if command -v just &>/dev/null; then
    success "  just installed"
  else
    error "  Failed to install just. Install manually: https://github.com/casey/just"
    exit 1
  fi
fi

# ── Clone or update repo ────────────────────────────────────────────────────

if [ -d "$CLONE_DIR/.git" ]; then
  info "  Updating development-setup..."
  git -C "$CLONE_DIR" pull --quiet 2>/dev/null || true
  success "  Updated"
else
  info "  Cloning development-setup..."
  git clone --depth 1 "$REPO_URL" "$CLONE_DIR" 2>/dev/null
  success "  Cloned to ${CLONE_DIR}"
fi

echo ""

# ── Run installer ────────────────────────────────────────────────────────────

cd "$CLONE_DIR"
just install
