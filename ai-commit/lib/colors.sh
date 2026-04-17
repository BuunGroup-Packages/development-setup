#!/usr/bin/env bash
# ── colors.sh ── Terminal colors and logging helpers ─────────────────────────

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

divider() {
  echo -e "${GREEN}$(printf '─%.0s' {1..60})${NC}"
}

header() {
  local title="$1"
  echo ""
  echo -e "${BOLD}${CYAN}  ${title}${NC}"
  echo -e "${DIM}  $(printf '─%.0s' {1..40})${NC}"
  echo ""
}

menu_option() {
  local key="$1"
  local label="$2"
  echo -ne "  ${CYAN}${key}${NC} ${label}"
}
