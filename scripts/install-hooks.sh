#!/usr/bin/env bash
set -euo pipefail
# ── install-hooks.sh ── Git hooks installer ──────────────────────────────────
#
# Usage:
#   install-hooks.sh                     # current repo
#   install-hooks.sh /path/to/repo       # specific repo
#   install-hooks.sh --scopes "api,app"  # with predefined scopes

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

# ── Parse args ───────────────────────────────────────────────────────────────

TARGET_REPO=""
SCOPES=""

while [ $# -gt 0 ]; do
  case "$1" in
    --scopes) SCOPES="$2"; shift 2 ;;
    *)        TARGET_REPO="$1"; shift ;;
  esac
done

# ── Resolve paths ────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -d "${HOME}/.local/share/ai-commit/hooks" ]; then
  HOOKS_SOURCE="${HOME}/.local/share/ai-commit/hooks"
elif [ -d "${SCRIPT_DIR}/../ai-commit/hooks" ]; then
  HOOKS_SOURCE="${SCRIPT_DIR}/../ai-commit/hooks"
else
  error "Cannot find hooks source directory."
  exit 1
fi

# ── Resolve target repo ─────────────────────────────────────────────────────

[ -n "$TARGET_REPO" ] && cd "$TARGET_REPO"

if ! git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  error "Not inside a git repository."
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")
HOOKS_DIR="${REPO_ROOT}/.githooks"
CONF_FILE="${REPO_ROOT}/.githooks.conf"

# ── Header ───────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}${CYAN}  Git Hooks Installer${NC}"
dim "  Repository: ${REPO_NAME}"
echo ""

# ── Check existing hooks ────────────────────────────────────────────────────

check_existing_hooks() {
  if [ -d "$HOOKS_DIR" ] || [ -d "${REPO_ROOT}/.husky" ]; then
    warn "  Existing hooks detected:"
    [ -d "$HOOKS_DIR" ] && dim "    ${HOOKS_DIR}/"
    [ -d "${REPO_ROOT}/.husky" ] && dim "    .husky/"
    echo ""
    read -r -p "  Overwrite? [y/N] " answer
    if [[ "${answer,,}" != "y" ]]; then
      echo ""
      info "  Aborted. Existing hooks unchanged."
      exit 0
    fi
    echo ""
  fi
}

check_existing_hooks

# ── Install hook files ───────────────────────────────────────────────────────

install_hook_files() {
  mkdir -p "$HOOKS_DIR"
  cp "${HOOKS_SOURCE}/commit-msg" "${HOOKS_DIR}/commit-msg"
  cp "${HOOKS_SOURCE}/pre-commit" "${HOOKS_DIR}/pre-commit"
  chmod +x "${HOOKS_DIR}/commit-msg" "${HOOKS_DIR}/pre-commit"

  success "  Installed hooks to ${HOOKS_DIR}/"

  git config core.hooksPath .githooks
  success "  Set core.hooksPath = .githooks"
}

install_hook_files

# ── Auto-detect scopes ──────────────────────────────────────────────────────

detect_scopes() {
  local detected=""

  for dir_type in apps packages; do
    if [ -d "${REPO_ROOT}/${dir_type}" ]; then
      for dir in "${REPO_ROOT}/${dir_type}"/*/; do
        [ -d "$dir" ] && detected+="$(basename "$dir")|"
      done
    fi
  done

  for d in src lib infra terraform; do
    [ -d "${REPO_ROOT}/${d}" ] && detected+="${d}|"
  done

  echo "${detected%|}"
}

# ── Create config ────────────────────────────────────────────────────────────

create_config() {
  if [ -f "$CONF_FILE" ]; then
    info "  Existing .githooks.conf found — keeping it."
    return
  fi

  info "  Creating .githooks.conf..."
  echo ""

  # Resolve scopes
  if [ -z "$SCOPES" ]; then
    local detected
    detected=$(detect_scopes)

    if [ -n "$detected" ]; then
      dim "  Detected scopes from directory structure:"
      echo -e "  ${CYAN}$(echo "$detected" | tr '|' ', ')${NC}"
      echo ""
      read -r -p "  Use these scopes? [Y/n] " answer
      [[ "${answer,,}" != "n" ]] && SCOPES="$detected"
    fi

    if [ -z "$SCOPES" ]; then
      dim "  Enter allowed scopes (comma-separated, or empty for any):"
      read -r -p "  > " user_scopes
      [ -n "$user_scopes" ] && SCOPES=$(echo "$user_scopes" | tr ',' '|' | tr -d ' ')
    fi
  else
    SCOPES=$(echo "$SCOPES" | tr ',' '|' | tr -d ' ')
  fi

  cat > "$CONF_FILE" <<EOF
# Git hooks configuration — installed by development-setup
# Edit this file to customize hook behavior for your repo.

# ── commit-msg ────────────────────────────────────────────────
COMMIT_TYPES="feat|fix|perf|chore|docs|refactor|test|ci|build|style"
COMMIT_SCOPES="${SCOPES}"
COMMIT_MAX_LENGTH=100
COMMIT_REQUIRE_SCOPE=false
COMMIT_WARN_UPPERCASE=true

# ── pre-commit ────────────────────────────────────────────────
FORBIDDEN_FILES='\.env$|\.dev\.vars$|credentials\.json$|\.pem$|\.key$|\.p12$'
DEBUG_ARTIFACTS='\.sqlite$|\.sqlite-shm$|\.sqlite-wal$|\.wrangler/'
CONSOLE_LOG_EXTENSIONS='ts|tsx|js|jsx'
CONSOLE_LOG_EXCLUDE='\.test\.|node_modules|error-handler'
CONSOLE_LOG_GUARDS='development|eslint-disable|APP_ENV|DEBUG'
EOF

  success "  Created ${CONF_FILE}"
}

create_config

# ── Wire into package.json ──────────────────────────────────────────────────

setup_prepare_script() {
  [ -f "${REPO_ROOT}/package.json" ] || return

  local existing hooks_cmd='git config core.hooksPath .githooks'
  existing=$(jq -r '.scripts.prepare // empty' "${REPO_ROOT}/package.json" 2>/dev/null || true)

  if [ -z "$existing" ]; then
    echo ""
    read -r -p "  Add 'prepare' script to package.json? (auto-enables hooks on npm install) [y/N] " answer
    if [[ "${answer,,}" == "y" ]]; then
      local tmpfile
      tmpfile=$(mktemp)
      jq ".scripts.prepare = \"${hooks_cmd}\"" "${REPO_ROOT}/package.json" > "$tmpfile"
      mv "$tmpfile" "${REPO_ROOT}/package.json"
      success "  Added prepare script to package.json"
    fi
  elif echo "$existing" | grep -q "hooksPath"; then
    success "  package.json prepare script already sets hooksPath"
  else
    warn "  package.json has a prepare script but doesn't set hooksPath"
    dim "  Current: ${existing}"
    dim "  You may want to add: ${hooks_cmd}"
  fi
}

setup_prepare_script

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}${BOLD}  Hooks installed!${NC}"
echo ""
dim "  Files:"
dim "    .githooks/commit-msg    Conventional Commits validation"
dim "    .githooks/pre-commit    Sensitive file & debug artifact checks"
dim "    .githooks.conf          Hook configuration (edit to customize)"
echo ""
dim "  Commit these files so the team shares the same hooks."
echo ""
