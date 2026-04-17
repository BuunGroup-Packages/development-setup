#!/usr/bin/env bash
# ── ollama.sh ── Ollama API interaction ──────────────────────────────────────

# ── Preflight ────────────────────────────────────────────────────────────────

require_ollama() {
  if ! command -v ollama &>/dev/null; then
    error "ollama is not installed."
    error "Install: curl -fsSL https://ollama.com/install.sh | sh"
    exit 1
  fi
}

require_jq() {
  if ! command -v jq &>/dev/null; then
    error "jq is not installed."
    error "Install: sudo apt install jq"
    exit 1
  fi
}

# ── Model management ────────────────────────────────────────────────────────

ensure_model() {
  local model="$1"
  local modelfile="$2"

  if ! ollama show "$model" &>/dev/null; then
    info "Model '${model}' not found. Creating from Modelfile..."
    local create_output
    create_output=$(ollama create "$model" -f "$modelfile" 2>&1)

    if [ $? -eq 0 ]; then
      success "Model '${model}' created."
    else
      # Check if failure is due to outdated Ollama
      if echo "$create_output" | grep -qi "unsupported\|unknown\|invalid\|not found\|404"; then
        warn "Model creation failed — your Ollama may be outdated."
        local current_ver
        current_ver=$(ollama --version 2>&1 | grep -oP '[\d.]+' || echo "unknown")
        dim "  Current version: v${current_ver}"

        read -r -p "  Update Ollama and retry? [Y/n] " answer
        if [[ "$(lower "$answer")" != "n" ]]; then
          info "  Updating Ollama..."
          curl -fsSL https://ollama.com/install.sh | sh
          local new_ver
          new_ver=$(ollama --version 2>&1 | grep -oP '[\d.]+' || echo "unknown")
          success "  Ollama updated to v${new_ver}"

          info "  Retrying model creation..."
          if ollama create "$model" -f "$modelfile" &>/dev/null; then
            success "Model '${model}' created."
          else
            error "Still failed. Check the Modelfile or base model."
            exit 1
          fi
        else
          exit 1
        fi
      else
        error "Failed to create model '${model}'."
        dim "  ${create_output}"
        exit 1
      fi
    fi
  fi
}

# ── System stats ─────────────────────────────────────────────────────────────

# Globals for tracking peak usage, timing, and tokens
STATS_START_TIME=""
STATS_GENERATION_SECS=0
STATS_PEAK_GPU=0
STATS_PEAK_CPU=0
STATS_PEAK_VRAM=0
STATS_GPU_TOTAL=0
STATS_RAM_TOTAL=0
STATS_PROMPT_TOKENS=0
STATS_OUTPUT_TOKENS=0
STATS_TOKENS_PER_SEC=0

get_system_stats() {
  local stats=""

  # GPU stats (nvidia)
  if command -v nvidia-smi &>/dev/null; then
    local gpu_info
    gpu_info=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null || true)
    if [ -n "$gpu_info" ]; then
      local gpu_pct gpu_used gpu_total
      gpu_pct=$(echo "$gpu_info" | cut -d',' -f1 | tr -d ' ')
      gpu_used=$(echo "$gpu_info" | cut -d',' -f2 | tr -d ' ')
      gpu_total=$(echo "$gpu_info" | cut -d',' -f3 | tr -d ' ')
      stats+="GPU ${gpu_pct}%  VRAM ${gpu_used}/${gpu_total}MiB"

      # Track peaks
      STATS_GPU_TOTAL="$gpu_total"
      [ "${gpu_pct:-0}" -gt "${STATS_PEAK_GPU:-0}" ] 2>/dev/null && STATS_PEAK_GPU="$gpu_pct"
      [ "${gpu_used:-0}" -gt "${STATS_PEAK_VRAM:-0}" ] 2>/dev/null && STATS_PEAK_VRAM="$gpu_used"
    fi
  fi

  # CPU usage (ollama process)
  local ollama_cpu
  ollama_cpu=$(ps -C ollama -o %cpu --no-headers 2>/dev/null | awk '{sum+=$1} END {printf "%.0f", sum}' || true)
  if [ -n "$ollama_cpu" ] && [ "$ollama_cpu" != "0" ]; then
    [ -n "$stats" ] && stats+="  "
    stats+="CPU ${ollama_cpu}%"
    [ "${ollama_cpu:-0}" -gt "${STATS_PEAK_CPU:-0}" ] 2>/dev/null && STATS_PEAK_CPU="$ollama_cpu"
  fi

  # System memory
  local mem_used mem_total
  mem_used=$(free -m 2>/dev/null | awk '/^Mem:/ {print $3}' || true)
  mem_total=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}' || true)
  if [ -n "$mem_used" ] && [ -n "$mem_total" ]; then
    [ -n "$stats" ] && stats+="  "
    stats+="RAM ${mem_used}/${mem_total}MiB"
    STATS_RAM_TOTAL="$mem_total"
  fi

  echo "$stats"
}

show_session_stats() {
  local total_secs
  if [ -n "$STATS_START_TIME" ]; then
    total_secs=$(( $(date +%s) - STATS_START_TIME ))
  else
    total_secs=0
  fi

  local total_tokens=$(( STATS_PROMPT_TOKENS + STATS_OUTPUT_TOKENS ))
  local current_stats
  current_stats=$(get_system_stats)

  # Build plain lines for width calculation, colored lines for display
  local plain_lines=()
  local color_lines=()

  # Timing
  local time_plain="Time    ${total_secs}s total"
  local time_color="${DIM}Time${NC}    ${GREEN}${total_secs}s${NC} total"
  if [ "$STATS_GENERATION_SECS" -gt 0 ]; then
    time_plain+="  ${STATS_GENERATION_SECS}s generation"
    time_color+="  ${CYAN}${STATS_GENERATION_SECS}s${NC} generation"
  fi
  plain_lines+=("$time_plain")
  color_lines+=("$time_color")

  # Tokens
  if [ "$total_tokens" -gt 0 ]; then
    local tok_plain="Tokens  ${STATS_PROMPT_TOKENS} in  ${STATS_OUTPUT_TOKENS} out"
    local tok_color="${DIM}Tokens${NC}  ${YELLOW}${STATS_PROMPT_TOKENS}${NC} in  ${YELLOW}${STATS_OUTPUT_TOKENS}${NC} out"
    if [ "$STATS_TOKENS_PER_SEC" -gt 0 ]; then
      tok_plain+="  ${STATS_TOKENS_PER_SEC} tok/s"
      tok_color+="  ${GREEN}${STATS_TOKENS_PER_SEC}${NC} tok/s"
    fi
    plain_lines+=("$tok_plain")
    color_lines+=("$tok_color")
  fi

  # Hardware peaks
  if [ "$STATS_PEAK_GPU" -gt 0 ] || [ "$STATS_PEAK_CPU" -gt 0 ]; then
    local hw_plain="Peak   "
    local hw_color="${DIM}Peak${NC}   "
    if [ "$STATS_PEAK_GPU" -gt 0 ]; then
      hw_plain+=" GPU ${STATS_PEAK_GPU}%"
      hw_color+=" GPU ${CYAN}${STATS_PEAK_GPU}%${NC}"
    fi
    if [ "$STATS_PEAK_VRAM" -gt 0 ]; then
      hw_plain+="  VRAM ${STATS_PEAK_VRAM}/${STATS_GPU_TOTAL}M"
      hw_color+="  VRAM ${CYAN}${STATS_PEAK_VRAM}${NC}/${DIM}${STATS_GPU_TOTAL}M${NC}"
    fi
    if [ "$STATS_PEAK_CPU" -gt 0 ]; then
      hw_plain+="  CPU ${STATS_PEAK_CPU}%"
      hw_color+="  CPU ${CYAN}${STATS_PEAK_CPU}%${NC}"
    fi
    plain_lines+=("$hw_plain")
    color_lines+=("$hw_color")
  fi

  # Current system state
  if [ -n "$current_stats" ]; then
    plain_lines+=("Live    ${current_stats}")
    # Colorize the live stats
    local live_colored
    live_colored=$(echo "$current_stats" \
      | sed "s/GPU \([0-9]*%\)/GPU ${CYAN}\1${NC}/g" \
      | sed "s/VRAM \([0-9]*\)/VRAM ${CYAN}\1${NC}/g" \
      | sed "s/CPU \([0-9]*%\)/CPU ${CYAN}\1${NC}/g" \
      | sed "s/RAM \([0-9]*\)/RAM ${CYAN}\1${NC}/g")
    color_lines+=("${DIM}Live${NC}    ${live_colored}")
  fi

  # Find widest line (using plain text without ANSI codes)
  local max_width=0
  for line in "${plain_lines[@]}"; do
    local len=${#line}
    [ "$len" -gt "$max_width" ] && max_width="$len"
  done

  local box_width=$((max_width + 4))

  # Draw box
  echo ""
  printf "${DIM}  ┌" > /dev/tty
  printf '─%.0s' $(seq 1 "$box_width") > /dev/tty
  printf "┐${NC}\n" > /dev/tty

  for i in "${!plain_lines[@]}"; do
    local pad=$((max_width - ${#plain_lines[$i]}))
    printf "  ${DIM}│${NC}  %b%*s  ${DIM}│${NC}\n" "${color_lines[$i]}" "$pad" "" > /dev/tty
  done

  printf "${DIM}  └" > /dev/tty
  printf '─%.0s' $(seq 1 "$box_width") > /dev/tty
  printf "┘${NC}\n" > /dev/tty
}

# ── Spinner ──────────────────────────────────────────────────────────────────

spinner() {
  local pid="$1"
  local label="${2:-Waiting...}"
  local i=0
  local stats_interval=10
  local stats=""
  local elapsed=0

  # Braille wave animation
  local wave=(
    '⣾⣽⣻⢿⡿⣟⣯⣷'
    '⣽⣻⢿⡿⣟⣯⣷⣾'
    '⣻⢿⡿⣟⣯⣷⣾⣽'
    '⢿⡿⣟⣯⣷⣾⣽⣻'
    '⡿⣟⣯⣷⣾⣽⣻⢿'
    '⣟⣯⣷⣾⣽⣻⢿⡿'
    '⣯⣷⣾⣽⣻⢿⡿⣟'
    '⣷⣾⣽⣻⢿⡿⣟⣯'
  )
  local wave_len=${#wave[@]}

  # Progress bar characters
  local bar_fill='━'
  local bar_empty='╌'
  local bar_width=20

  # Hide cursor
  printf "\033[?25l" > /dev/tty

  while kill -0 "$pid" 2>/dev/null; do
    # Refresh stats periodically
    if [ $((i % stats_interval)) -eq 0 ]; then
      stats=$(get_system_stats)
      elapsed=$((i / 10))
    fi

    # Animated progress bar (bouncing)
    local pos=$(( (i / 2) % (bar_width * 2) ))
    [ "$pos" -ge "$bar_width" ] && pos=$(( bar_width * 2 - pos ))
    local bar=""
    for ((b=0; b<bar_width; b++)); do
      if [ $b -ge $((pos)) ] && [ $b -lt $((pos + 3)) ]; then
        bar+="${bar_fill}"
      else
        bar+="${bar_empty}"
      fi
    done

    # Line 1: wave animation + label + timer
    # Line 2: bouncing progress bar
    # Line 3: system stats
    printf "\033[G\033[K  ${CYAN}%s${NC} ${BOLD}%s${NC}  ${DIM}%ds${NC}" \
      "${wave[$((i % wave_len))]}" "$label" "$elapsed" > /dev/tty
    printf "\n\033[K  ${CYAN}%s${NC}" "$bar" > /dev/tty
    printf "\n\033[K  ${DIM}%s${NC}" "$stats" > /dev/tty
    printf "\033[2A" > /dev/tty

    i=$((i + 1))
    sleep 0.1
  done

  # Final elapsed
  elapsed=$((i / 10))

  # Clear all 3 lines and show done
  printf "\033[G\033[K  ${GREEN}✓${NC} ${BOLD}Done${NC} ${DIM}(${elapsed}s)${NC}\n" > /dev/tty
  printf "\033[K\n\033[K\033[2A\n" > /dev/tty

  # Show cursor
  printf "\033[?25h" > /dev/tty
}

# ── API call ─────────────────────────────────────────────────────────────────

call_ollama() {
  local model="$1"
  local prompt="$2"

  # Build JSON payload via temp files (handles large diffs safely)
  local prompt_file payload_file response_file
  prompt_file=$(mktemp /tmp/ai-commit-prompt-XXXXXX.txt)
  payload_file=$(mktemp /tmp/ai-commit-payload-XXXXXX.json)
  response_file=$(mktemp /tmp/ai-commit-response-XXXXXX.json)

  printf '%s' "$prompt" > "$prompt_file"
  jq -n \
    --arg model "$model" \
    --rawfile prompt "$prompt_file" \
    '{model: $model, prompt: $prompt, stream: false}' \
    > "$payload_file" 2>/dev/null
  rm -f "$prompt_file"

  if [ ! -s "$payload_file" ]; then
    error "Failed to build JSON payload."
    rm -f "$payload_file" "$response_file"
    exit 1
  fi

  # Run curl in background with spinner
  curl -s --max-time 180 "${OLLAMA_HOST}/api/generate" \
    -H "Content-Type: application/json" \
    -d @"$payload_file" \
    -o "$response_file" 2>/dev/null &
  local curl_pid=$!

  echo ""
  spinner "$curl_pid" "Waiting for ${model}..."

  # Wait specifically for curl, not the spinner
  set +e
  wait "$curl_pid"
  local curl_exit=$?
  set -e
  rm -f "$payload_file"

  if [ "$curl_exit" -ne 0 ]; then
    error "Ollama request failed (exit ${curl_exit}). Is it running? (ollama serve)"
    rm -f "$response_file"
    exit 1
  fi

  # Extract response
  if [ ! -s "$response_file" ]; then
    error "Empty response file from Ollama."
    rm -f "$response_file"
    exit 1
  fi

  local response_text
  response_text=$(jq -r '.response // empty' "$response_file" 2>/dev/null)

  # Write token stats to a sidecar file (survives subshell)
  local stats_file="/tmp/ai-commit-tokenstats"
  jq -r '[
    .prompt_eval_count // 0,
    .eval_count // 0,
    .eval_duration // 0
  ] | join("|")' "$response_file" 2>/dev/null > "$stats_file" || true

  if [ -z "$response_text" ]; then
    error "Empty response from Ollama."
    error "  Raw response (first 500 chars):"
    head -c 500 "$response_file" >&2
    echo "" >&2
    rm -f "$response_file"
    exit 1
  fi

  rm -f "$response_file"

  echo "$response_text"
}

# Read token stats written by call_ollama (called from parent shell)
load_token_stats() {
  local stats_file="/tmp/ai-commit-tokenstats"
  if [ -f "$stats_file" ]; then
    IFS='|' read -r STATS_PROMPT_TOKENS STATS_OUTPUT_TOKENS eval_dur < "$stats_file"
    STATS_PROMPT_TOKENS="${STATS_PROMPT_TOKENS:-0}"
    STATS_OUTPUT_TOKENS="${STATS_OUTPUT_TOKENS:-0}"
    eval_dur="${eval_dur:-0}"
    if [ "$eval_dur" -gt 0 ] && [ "$STATS_OUTPUT_TOKENS" -gt 0 ]; then
      STATS_TOKENS_PER_SEC=$(( STATS_OUTPUT_TOKENS * 1000000000 / eval_dur ))
    fi
    rm -f "$stats_file"
  fi
}
