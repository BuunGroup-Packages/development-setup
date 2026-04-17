#!/usr/bin/env bash
set -euo pipefail
# ── install.sh ── Development setup installer ────────────────────────────────
#
# Clone and run:
#   git clone https://github.com/BuunGroup-Packages/development-setup.git
#   cd development-setup && just install

# ── Colors & helpers ─────────────────────────────────────────────────────────

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
NC=$'\033[0m'

info()    { echo -e "${CYAN}$*${NC}"; }
success() { echo -e "${GREEN}$*${NC}"; }
warn()    { echo -e "${YELLOW}$*${NC}"; }
error()   { echo -e "${RED}$*${NC}" >&2; }
dim()     { echo -e "${DIM}$*${NC}"; }
lower()   { echo "$1" | tr '[:upper:]' '[:lower:]'; }

step() { info "[$1/7] $2"; }

# ── Paths ────────────────────────────────────────────────────────────────────

INSTALL_DIR="${HOME}/.local/share/ai-commit"
BIN_DIR="${HOME}/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

detect_shell_rc() {
  case "$(basename "$SHELL")" in
    zsh)  echo "$HOME/.zshrc" ;;
    *)    echo "$HOME/.bashrc" ;;
  esac
}

SHELL_RC=$(detect_shell_rc)

# ── Header ───────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}${CYAN}  Development Setup Installer${NC}"
echo -e "${DIM}  $(printf '─%.0s' {1..34})${NC}"
echo ""

# ── Resolve source ───────────────────────────────────────────────────────────

resolve_source() {
  if [ -d "${REPO_DIR}/ai-commit/lib" ]; then
    SOURCE_DIR="${REPO_DIR}"
    info "Installing from local checkout: ${SOURCE_DIR}"
  else
    SOURCE_DIR=$(mktemp -d /tmp/dev-setup-XXXXXX)
    info "Downloading development-setup..."
    git clone --depth 1 https://github.com/BuunGroup-Packages/development-setup.git "$SOURCE_DIR" 2>/dev/null \
      || { error "Failed to clone. Is git installed?"; exit 1; }
  fi
}

resolve_source
echo ""

# ── Step 1: System dependencies ─────────────────────────────────────────────

check_or_install() {
  local cmd="$1" install_cmd="$2" install_msg="$3"

  if command -v "$cmd" &>/dev/null; then
    success "  ${cmd} found"
  else
    warn "  ${cmd} not found"
    dim "  ${install_msg}"
    read -r -p "  Install now? [y/N] " answer
    if [[ "$(lower "$answer")" == "y" ]]; then
      eval "$install_cmd"
      success "  ${cmd} installed"
    else
      error "  ${cmd} is required. Skipping."
      return 1
    fi
  fi
}

step 1 "Checking system dependencies..."

check_or_install "jq" \
  "sudo apt-get install -y jq 2>/dev/null || sudo pacman -S --noconfirm jq 2>/dev/null || brew install jq 2>/dev/null" \
  "JSON processor (sudo apt install jq)"

check_or_install "curl" \
  "sudo apt-get install -y curl 2>/dev/null || sudo pacman -S --noconfirm curl 2>/dev/null || brew install curl 2>/dev/null" \
  "HTTP client (sudo apt install curl)"

echo ""

# ── Step 2: Ollama ───────────────────────────────────────────────────────────

setup_ollama() {
  if command -v ollama &>/dev/null; then
    success "  Ollama already installed"
  else
    warn "  Ollama not found"
    read -r -p "  Install Ollama now? [y/N] " answer
    if [[ "$(lower "$answer")" == "y" ]]; then
      info "  Downloading Ollama installer..."
      curl -fsSL https://ollama.com/install.sh | sh
      success "  Ollama installed"
    else
      error "  Ollama is required for ai-commit. Skipping."
    fi
  fi
}

ensure_ollama_running() {
  if curl -s --max-time 2 http://localhost:11434/api/tags &>/dev/null; then
    success "  Ollama is running"
    return
  fi

  warn "  Ollama is not running. Starting..."
  if command -v systemctl &>/dev/null && systemctl is-enabled ollama &>/dev/null 2>&1; then
    sudo systemctl start ollama
  else
    nohup ollama serve &>/dev/null &
    sleep 2
  fi

  if curl -s --max-time 5 http://localhost:11434/api/tags &>/dev/null; then
    success "  Ollama started"
  else
    warn "  Could not start Ollama. Run 'ollama serve' manually."
  fi
}

step 2 "Setting up Ollama..."
setup_ollama
ensure_ollama_running
echo ""

# ── Step 3: Install files ───────────────────────────────────────────────────

install_files() {
  mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/models" "$INSTALL_DIR/hooks" "$BIN_DIR"

  cp "${SOURCE_DIR}/ai-commit/lib/"*.sh                   "$INSTALL_DIR/lib/"
  cp "${SOURCE_DIR}/ai-commit/models/system-prompt.txt"   "$INSTALL_DIR/models/"
  cp "${SOURCE_DIR}/ai-commit/models/profiles.conf"       "$INSTALL_DIR/models/"
  cp "${SOURCE_DIR}/ai-commit/models/build.sh"            "$INSTALL_DIR/models/"
  cp "${SOURCE_DIR}/ai-commit/hooks/commit-msg"           "$INSTALL_DIR/hooks/"
  cp "${SOURCE_DIR}/ai-commit/hooks/pre-commit"           "$INSTALL_DIR/hooks/"
  cp "${SOURCE_DIR}/ai-commit/hooks/hooks.conf.example"   "$INSTALL_DIR/hooks/"
  cp "${SOURCE_DIR}/ai-commit/ai-commit"                  "$BIN_DIR/ai-commit"

  chmod +x "$INSTALL_DIR/hooks/commit-msg" "$INSTALL_DIR/hooks/pre-commit"
  chmod +x "$INSTALL_DIR/models/build.sh"
  chmod +x "$BIN_DIR/ai-commit"

  success "  Installed to ${INSTALL_DIR}"
  success "  Binary at ${BIN_DIR}/ai-commit"
}

ensure_path() {
  if echo "$PATH" | grep -q "${BIN_DIR}"; then
    return
  fi

  warn "  ${BIN_DIR} is not in your PATH"
  read -r -p "  Add to PATH in ${SHELL_RC}? [y/N] " answer
  if [[ "$(lower "$answer")" == "y" ]]; then
    echo '' >> "$SHELL_RC"
    echo '# Added by development-setup installer' >> "$SHELL_RC"
    echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> "$SHELL_RC"
    success "  PATH updated in ${SHELL_RC}"
  fi
}

step 3 "Installing ai-commit..."
install_files
ensure_path
echo ""

# ── Step 4: Select model profile ────────────────────────────────────────────

select_profile() {
  local profiles_conf="${INSTALL_DIR}/models/profiles.conf"
  declare -a names=() descs=() bases=()

  while IFS='|' read -r profile base_model temp predict ctx desc; do
    [[ "$profile" =~ ^#.*$ || -z "$profile" ]] && continue
    names+=("$profile")
    descs+=("$desc")
    bases+=("$base_model")
  done < "$profiles_conf"

  for i in "${!names[@]}"; do
    if [ "${names[$i]}" = "default" ]; then
      echo -e "    ${CYAN}$((i+1))${NC}) ${BOLD}${names[$i]}${NC}  ${DIM}${descs[$i]}${NC}"
    else
      echo -e "    ${CYAN}$((i+1))${NC}) ${names[$i]}  ${DIM}${descs[$i]}${NC}"
    fi
  done

  echo ""
  read -r -p "  Choose profile [1]: " choice
  choice="${choice:-1}"

  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#names[@]}" ]; then
    SELECTED_PROFILE="${names[$((choice-1))]}"
    SELECTED_BASE="${bases[$((choice-1))]}"
  else
    warn "  Invalid choice, using default"
    SELECTED_PROFILE="default"
    SELECTED_BASE="${bases[0]}"
  fi

  success "  Selected: ${SELECTED_PROFILE}"
}

step 4 "Select model profile..."
echo ""
select_profile
echo ""

# ── Step 5: Build and create model ──────────────────────────────────────────

build_model() {
  bash "${INSTALL_DIR}/models/build.sh" "$SELECTED_PROFILE"

  local model_name
  if [ "$SELECTED_PROFILE" = "default" ]; then
    model_name="buun-commit"
  else
    model_name="buun-commit-${SELECTED_PROFILE}"
  fi

  local modelfile="${INSTALL_DIR}/models/generated/${SELECTED_PROFILE}.modelfile"

  if ollama show "$model_name" &>/dev/null 2>&1; then
    success "  Model '${model_name}' already exists"
    read -r -p "  Rebuild with latest config? [y/N] " answer
    if [[ "$(lower "$answer")" == "y" ]]; then
      ollama create "$model_name" -f "$modelfile" 2>/dev/null
      success "  Model rebuilt"
    fi
  else
    info "  Pulling ${SELECTED_BASE} and creating ${model_name}..."
    dim "  (this may take a few minutes on first run)"
    if ollama create "$model_name" -f "$modelfile"; then
      success "  Model '${model_name}' created"
    else
      error "  Failed to create model. Try manually:"
      error "  ollama create ${model_name} -f ${modelfile}"
    fi
  fi

  echo "$SELECTED_PROFILE" > "${INSTALL_DIR}/.profile"
}

step 5 "Building model..."
build_model
echo ""

# ── Step 6: Shell alias ─────────────────────────────────────────────────────

setup_alias() {
  if grep -q 'alias gc=' "$SHELL_RC" 2>/dev/null; then
    success "  Alias 'gc' already exists in ${SHELL_RC}"
  else
    read -r -p "  Add 'gc' alias for ai-commit to ${SHELL_RC}? [Y/n] " answer
    if [[ "$(lower "$answer")" != "n" ]]; then
      echo '' >> "$SHELL_RC"
      echo '# ai-commit alias — added by development-setup' >> "$SHELL_RC"
      echo 'alias gc="ai-commit"' >> "$SHELL_RC"
      success "  Added alias gc=\"ai-commit\" to ${SHELL_RC}"
    else
      dim "  Skipped. You can add it later: alias gc=\"ai-commit\""
    fi
  fi
}

step 6 "Shell alias..."
setup_alias
echo ""

# ── Step 7: Git hooks ───────────────────────────────────────────────────────

setup_hooks() {
  local current_repo
  current_repo=$(git rev-parse --show-toplevel 2>/dev/null || true)

  if [ -n "$current_repo" ]; then
    dim "  Current repo: $(basename "$current_repo")"
    read -r -p "  Install git hooks into this repo? [Y/n] " answer
    if [[ "$(lower "$answer")" != "n" ]]; then
      bash "${SCRIPT_DIR}/install-hooks.sh" "$current_repo"
    else
      dim "  Skipped. Install later with: just hooks"
    fi
  else
    read -r -p "  Install git hooks into a repo? Enter path (or leave empty to skip): " repo_path
    if [ -n "$repo_path" ]; then
      bash "${SCRIPT_DIR}/install-hooks.sh" "$repo_path"
    else
      dim "  Skipped. Install later with: just hooks /path/to/repo"
    fi
  fi
}

step 7 "Git hooks..."
echo ""
setup_hooks

# ── Cleanup ──────────────────────────────────────────────────────────────────

[[ "$SOURCE_DIR" == /tmp/dev-setup-* ]] && rm -rf "$SOURCE_DIR"

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}${BOLD}  Installation complete!${NC}"
echo ""
echo -e "  ${BOLD}Usage:${NC}"
echo -e "    ${CYAN}cd your-repo${NC}"
echo -e "    ${CYAN}git add -p${NC}"
echo -e "    ${CYAN}gc${NC}  ${DIM}(or ai-commit)${NC}"
echo ""
echo -e "  ${BOLD}Switch profile:${NC}"
echo -e "    ${DIM}OLLAMA_COMMIT_PROFILE=small gc${NC}"
echo -e "    ${DIM}OLLAMA_COMMIT_PROFILE=large gc${NC}"
echo ""
