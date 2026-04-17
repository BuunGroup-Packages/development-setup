#!/usr/bin/env bash
set -euo pipefail

# Builds Ollama Modelfiles from the shared system prompt + profile config.
# Usage:
#   ./build.sh                  # build all profiles
#   ./build.sh default small    # build specific profiles
#   ./build.sh --list           # list available profiles

MODELS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_PROMPT="${MODELS_DIR}/system-prompt.txt"
PROFILES_CONF="${MODELS_DIR}/profiles.conf"
OUTPUT_DIR="${MODELS_DIR}/generated"

if [ ! -f "$SYSTEM_PROMPT" ]; then
  echo "Error: system-prompt.txt not found" >&2
  exit 1
fi

if [ ! -f "$PROFILES_CONF" ]; then
  echo "Error: profiles.conf not found" >&2
  exit 1
fi

PROMPT_CONTENT=$(cat "$SYSTEM_PROMPT")

list_profiles() {
  echo "Available profiles:"
  echo ""
  while IFS='|' read -r profile base_model temp predict ctx min_f desc; do
    [[ "$profile" =~ ^#.*$ || -z "$profile" ]] && continue
    printf "  %-10s  %-20s  %s\n" "$profile" "$base_model" "$desc"
  done < "$PROFILES_CONF"
}

build_modelfile() {
  local profile="$1"
  local base_model="$2"
  local temp="$3"
  local predict="$4"
  local ctx="$5"

  mkdir -p "$OUTPUT_DIR"
  local outfile="${OUTPUT_DIR}/${profile}.modelfile"

  cat > "$outfile" <<EOF
FROM ${base_model}

PARAMETER temperature ${temp}
PARAMETER num_predict ${predict}
PARAMETER num_ctx ${ctx}
PARAMETER stop "<end_of_turn>"

SYSTEM """${PROMPT_CONTENT}"""
EOF

  echo "$outfile"
}

# --- Handle args ---
if [ "${1:-}" = "--list" ]; then
  list_profiles
  exit 0
fi

REQUESTED=("$@")

mkdir -p "$OUTPUT_DIR"

while IFS='|' read -r profile base_model temp predict ctx min_f desc; do
  [[ "$profile" =~ ^#.*$ || -z "$profile" ]] && continue

  # If specific profiles requested, skip others
  if [ ${#REQUESTED[@]} -gt 0 ]; then
    found=false
    for req in "${REQUESTED[@]}"; do
      [ "$req" = "$profile" ] && found=true
    done
    [ "$found" = false ] && continue
  fi

  outfile=$(build_modelfile "$profile" "$base_model" "$temp" "$predict" "$ctx")
  echo "Built: ${outfile}  (${desc})"
done < "$PROFILES_CONF"
