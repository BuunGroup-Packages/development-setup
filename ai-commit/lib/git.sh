#!/usr/bin/env bash
# ── git.sh ── Git context gathering ──────────────────────────────────────────

# ── Preflight ────────────────────────────────────────────────────────────────

require_git_repo() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    error "Not inside a git repository."
    exit 1
  fi
}

# ── Repo metadata ────────────────────────────────────────────────────────────

get_repo_root()  { git rev-parse --show-toplevel; }
get_repo_name()  { basename "$(get_repo_root)"; }
get_branch()     { git branch --show-current 2>/dev/null || echo "detached"; }

# ── Staged changes ───────────────────────────────────────────────────────────

get_staged_stat()  { git diff --cached --stat; }
get_staged_diff()  { git diff --cached | head -n "$MAX_DIFF_LINES" || true; }
get_staged_files() { git diff --cached --name-only; }

require_staged_changes() {
  local stat
  stat=$(get_staged_stat)

  if [ -z "$stat" ]; then
    warn "No staged changes. Stage files first with 'git add'."
    git status --short
    exit 1
  fi

  echo "$stat"
}

# ── History ──────────────────────────────────────────────────────────────────

get_recent_log() {
  git log --oneline --no-decorate -n "$MAX_LOG_ENTRIES" 2>/dev/null \
    || echo "(no history)"
}

get_recent_scopes() {
  git log --oneline --no-decorate -n 50 2>/dev/null \
    | grep -oP '^\w+ \w+\(\K[^)]+' \
    | sort -u \
    | tr '\n' ', ' \
    | sed 's/,$//' || true
}

# ── Convention detection ─────────────────────────────────────────────────────

detect_conventions() {
  local root="$1"
  local rules=""

  # Commitlint config
  local configs=(
    commitlint.config.js commitlint.config.cjs commitlint.config.mjs
    .commitlintrc .commitlintrc.json .commitlintrc.yml .commitlintrc.yaml
  )
  for cfg in "${configs[@]}"; do
    if [ -f "${root}/${cfg}" ]; then
      rules+="commitlint config (${cfg}):"$'\n'
      rules+="$(head -50 "${root}/${cfg}" 2>/dev/null)"$'\n'
      break
    fi
  done

  # Commit-msg hooks
  local hooks=("${root}/.husky/commit-msg" "${root}/.git/hooks/commit-msg")
  for hook in "${hooks[@]}"; do
    if [ -f "$hook" ]; then
      rules+="commit-msg hook:"$'\n'
      rules+="$(head -30 "$hook" 2>/dev/null)"$'\n'
      break
    fi
  done

  # Commitlint in package.json
  if [ -f "${root}/package.json" ]; then
    local pkgs
    pkgs=$(jq -r '
      .devDependencies // {} | keys[]
      | select(startswith("@commitlint") or startswith("commitlint"))
    ' "${root}/package.json" 2>/dev/null || true)
    [ -n "$pkgs" ] && rules+="Commitlint packages: ${pkgs}"$'\n'

    local inline
    inline=$(jq -r '.commitlint // empty' "${root}/package.json" 2>/dev/null || true)
    [ -n "$inline" ] && rules+="Inline commitlint config: ${inline}"$'\n'
  fi

  echo "$rules"
}
