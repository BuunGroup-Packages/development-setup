#!/usr/bin/env bash
set -euo pipefail
# ── uninstall.sh ── Development setup uninstaller ────────────────────────────

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

INSTALL_DIR="${HOME}/.local/share/ai-commit"
BIN="${HOME}/.local/bin/ai-commit"

echo ""
echo -e "${BOLD}${CYAN}  Development Setup Uninstaller${NC}"
echo ""

# ── Remove files ─────────────────────────────────────────────────────────────

[ -d "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR" && echo -e "${GREEN}  Removed ${INSTALL_DIR}${NC}"
[ -f "$BIN" ]         && rm -f "$BIN"          && echo -e "${GREEN}  Removed ${BIN}${NC}"

# ── Remove Ollama model ─────────────────────────────────────────────────────

echo ""
read -r -p "  Also delete Ollama 'buun-commit' model(s)? [y/N] " answer
if [[ "${answer,,}" == "y" ]]; then
  for model in $(ollama list 2>/dev/null | grep -o 'buun-commit[^ ]*' || true); do
    ollama rm "$model" 2>/dev/null && echo -e "${GREEN}  Removed model: ${model}${NC}"
  done
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}${BOLD}  ✓ Uninstalled.${NC}"
echo ""
