#!/usr/bin/env bash
# ── commit.sh ── Message cleaning, validation, and execution ─────────────────

VALID_TYPES='feat|fix|docs|style|refactor|perf|test|build|ci|chore'

# ── Response cleaning ────────────────────────────────────────────────────────

clean_response() {
  local text="$1"

  # Find the first line starting with a valid conventional commit type
  local commit_line
  commit_line=$(echo "$text" | grep -m1 -E "^(${VALID_TYPES})(\(.+\))?!?: " || true)

  if [ -n "$commit_line" ]; then
    echo "$text" \
      | sed -n "/^${commit_line//\//\\/}/,\$p" \
      | sed '/^```/d; /^[Hh]ere/d; /^[Tt]hese changes/d; /^---/d' \
      | sed 's/\*\*//g' \
      | sed -e ':a' -e '/^[[:space:]]*$/{ $d; N; ba; }' \
      || true
  else
    echo "$text" \
      | sed '/^```/d; s/\*\*//g; /^[Hh]ere/d' \
      | sed 's/^[[:space:]]*//' \
      | sed '/./,$!d' \
      || true
  fi
}

# ── Validation ───────────────────────────────────────────────────────────────

validate_commit_msg() {
  local msg="$1"
  local first_line
  first_line=$(echo "$msg" | head -1)
  local valid=true

  if ! echo "$first_line" | grep -qE "^(${VALID_TYPES})(\(.+\))?!?: .+$"; then
    warn "First line doesn't match Conventional Commits format."
    warn "  Got:      ${first_line}"
    warn "  Expected: <type>(<scope>): <description>"
    valid=false
  fi

  if [ "${#first_line}" -gt 72 ]; then
    warn "Subject line is ${#first_line} chars (max 72)."
    valid=false
  fi

  if [ "$valid" = true ]; then
    success "  Validation passed."
  fi
}

# ── Commit execution ────────────────────────────────────────────────────────

do_commit() {
  local msg="$1"
  local tmpfile
  tmpfile=$(mktemp /tmp/ai-commit-msg-XXXXXX)
  printf '%s\n' "$msg" > "$tmpfile"

  if GIT_EDITOR=true git commit --cleanup=verbatim -F "$tmpfile"; then
    success "Committed!"
    rm -f "$tmpfile"
  else
    error "Commit failed. Check the error above."
    warn "Message saved to: ${tmpfile}"
    return 1
  fi
}

# ── Clipboard ────────────────────────────────────────────────────────────────

copy_to_clipboard() {
  local msg="$1"
  local tools=(
    "clip.exe"    # WSL2
    "wl-copy"     # Wayland
    "xclip"       # X11 (needs -selection clipboard)
    "xsel"        # X11 (needs --clipboard)
    "pbcopy"      # macOS
  )

  for tool in "${tools[@]}"; do
    if command -v "$tool" &>/dev/null; then
      case "$tool" in
        xclip) echo -n "$msg" | "$tool" -selection clipboard ;;
        xsel)  echo -n "$msg" | "$tool" --clipboard ;;
        *)     echo -n "$msg" | "$tool" ;;
      esac
      success "Copied to clipboard."
      return 0
    fi
  done

  warn "No clipboard tool found. Message printed above."
  return 1
}
