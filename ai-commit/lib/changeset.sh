#!/usr/bin/env bash
# ── changeset.sh ── Changeset detection, preview, and creation ───────────────

# ── State (shared between preview and confirm) ──────────────────────────────

CHANGESET_ACTIVE=false
CHANGESET_CONTENT=""
EXISTING_CHANGESET_FILE=""

# ── Detection ────────────────────────────────────────────────────────────────

has_changesets() {
  [ -f "${1}/.changeset/config.json" ]
}

get_ignored_packages() {
  jq -r '.ignore // [] | .[]' "${1}/.changeset/config.json" 2>/dev/null || true
}

# ── Package discovery ────────────────────────────────────────────────────────

discover_packages() {
  local root="$1"
  local workspace_globs=()

  # Read workspace patterns
  if [ -f "${root}/pnpm-workspace.yaml" ]; then
    workspace_globs=($(grep -E '^\s*-\s+' "${root}/pnpm-workspace.yaml" \
      | sed "s/^[[:space:]]*-[[:space:]]*//" \
      | sed "s/['\"]//g" \
      || true))
  elif [ -f "${root}/package.json" ]; then
    workspace_globs=($(
      jq -r '.workspaces // [] | .[] // empty' "${root}/package.json" 2>/dev/null \
      || jq -r '.workspaces.packages // [] | .[] // empty' "${root}/package.json" 2>/dev/null \
      || true
    ))
  fi

  # Single-package repo fallback
  if [ ${#workspace_globs[@]} -eq 0 ]; then
    if [ -f "${root}/package.json" ]; then
      local name private
      name=$(jq -r '.name // empty' "${root}/package.json" 2>/dev/null)
      private=$(jq -r '.private // false' "${root}/package.json" 2>/dev/null)
      [ -n "$name" ] && [ "$private" != "true" ] && echo "${name}|."
    fi
    return
  fi

  # Expand workspace globs
  for glob in "${workspace_globs[@]}"; do
    local clean_glob="${glob%/\*\*}"
    clean_glob="${clean_glob%/\*}"

    for pkg_json in ${root}/${clean_glob}/*/package.json ${root}/${clean_glob}/package.json; do
      [ -f "$pkg_json" ] || continue

      local name private rel_path
      name=$(jq -r '.name // empty' "$pkg_json" 2>/dev/null)
      private=$(jq -r '.private // false' "$pkg_json" 2>/dev/null)
      rel_path=$(dirname "$pkg_json")
      rel_path="${rel_path#${root}/}"

      [ -n "$name" ] && echo "${name}|${rel_path}|${private}"
    done
  done | sort -u
}

get_affected_packages() {
  local root="$1"
  local staged_files="$2"
  local ignored packages
  ignored=$(get_ignored_packages "$root")
  packages=$(discover_packages "$root")

  [ -z "$packages" ] && return

  local affected=()
  while IFS='|' read -r pkg_name pkg_path pkg_private; do
    [ -z "$pkg_name" ] && continue
    echo "$ignored" | grep -qxF "$pkg_name" && continue
    echo "$staged_files" | grep -q "^${pkg_path}/" && affected+=("$pkg_name")
  done <<< "$packages"

  printf '%s\n' "${affected[@]}" | sort -u
}

# ── SemVer mapping ──────────────────────────────────────────────────────────

commit_type_to_bump() {
  case "$1" in
    feat) echo "minor" ;;
    *)    echo "patch" ;;
  esac
}

is_breaking_change() {
  local msg="$1"
  local first_line
  first_line=$(echo "$msg" | head -1)

  echo "$first_line" | grep -qE '^[a-z]+(\(.+\))?!:' && return 0
  echo "$msg" | grep -qi '^BREAKING CHANGE:' && return 0
  return 1
}

# ── Content generation ──────────────────────────────────────────────────────

generate_changeset_name() {
  local adjectives=(
    bright calm cool dry fast flat gold green heavy kind
    late lean long loud neat new old pink proud quick
    rare red rich shy slim slow soft tall thin tiny
    warm weak wide wild wise young
  )
  local nouns=(
    ants bats beds bees cats cups dogs eels eggs fans
    fish foxes hats keys maps mice owls pans pigs rays
    rugs seals toes vans yaks
  )

  echo "${adjectives[$((RANDOM % ${#adjectives[@]}))]}-${nouns[$((RANDOM % ${#nouns[@]}))]}-$((RANDOM % 100))"
}

build_changeset_content() {
  local packages="$1"
  local bump="$2"
  local description="$3"
  local content="---"$'\n'

  while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    content+="\"${pkg}\": ${bump}"$'\n'
  done <<< "$packages"

  content+="---"$'\n\n'"${description}"$'\n'
  echo "$content"
}

extract_changelog_description() {
  local commit_msg="$1"
  local first_line subject body
  first_line=$(echo "$commit_msg" | head -1)

  # Strip type(scope): prefix and capitalize
  subject=$(echo "$first_line" | sed -E 's/^[a-z]+(\([^)]*\))?!?:[[:space:]]*//')
  subject="$(echo "${subject:0:1}" | tr '[:lower:]' '[:upper:]')${subject:1}"

  # Append body if present
  body=$(echo "$commit_msg" | tail -n +3)
  if [ -n "$body" ]; then
    echo "${subject}"$'\n\n'"${body}"
  else
    echo "$subject"
  fi
}

# ── Branch changeset detection ───────────────────────────────────────────────

# Find existing changeset files added on the current branch
# Returns: filepaths of .changeset/*.md files that don't exist on base branch
find_branch_changesets() {
  local root="$1"
  local base_branch

  # Read base branch from changeset config, fallback to main
  base_branch=$(jq -r '.baseBranch // "main"' "${root}/.changeset/config.json" 2>/dev/null || echo "main")

  # Files added/modified in .changeset/ since diverging from base
  git diff --name-only "${base_branch}...HEAD" -- '.changeset/*.md' 2>/dev/null || true

  # Also check staged but not yet committed
  git diff --cached --name-only -- '.changeset/*.md' 2>/dev/null || true

  # Also check untracked changeset files
  git ls-files --others --exclude-standard -- '.changeset/*.md' 2>/dev/null || true
}

# Read an existing changeset file and extract its metadata
read_changeset_file() {
  local filepath="$1"
  [ -f "$filepath" ] && cat "$filepath"
}

# ── Preview (shown before user menu) ─────────────────────────────────────────

preview_changeset() {
  local root="$1"
  local commit_msg="$2"
  local staged_files="$3"

  CHANGESET_ACTIVE=false
  CHANGESET_CONTENT=""
  EXISTING_CHANGESET_FILE=""

  has_changesets "$root" || return 0

  local affected
  affected=$(get_affected_packages "$root" "$staged_files")

  if [ -z "$affected" ]; then
    echo ""
    dim "  Changesets: no tracked packages affected"
    return 0
  fi

  # Determine bump type
  local commit_type bump
  commit_type=$(echo "$commit_msg" | head -1 | grep -oP '^[a-z]+' || echo "chore")

  if is_breaking_change "$commit_msg"; then
    bump="major"
  else
    bump=$(commit_type_to_bump "$commit_type")
  fi

  # Check for existing changeset on this branch
  local existing_files
  existing_files=$(find_branch_changesets "$root" | sort -u | grep -v '^$' || true)

  if [ -n "$existing_files" ]; then
    # Show existing changeset(s)
    local file_count
    file_count=$(echo "$existing_files" | wc -l)

    echo ""
    warn "Existing changeset(s) found on this branch (${file_count}):"
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      local rel_name
      rel_name=$(basename "$f")
      echo -e "  ${YELLOW}${rel_name}${NC}"

      # Show current content dimmed
      if [ -f "${root}/${f}" ]; then
        head -5 "${root}/${f}" | while IFS= read -r line; do
          dim "    ${line}"
        done
        local total_lines
        total_lines=$(wc -l < "${root}/${f}")
        [ "$total_lines" -gt 5 ] && dim "    ... (${total_lines} lines)"
      fi
    done <<< "$existing_files"

    # Use the first one as the target for updates
    EXISTING_CHANGESET_FILE=$(echo "$existing_files" | head -1)
  fi

  # Build proposed content
  local description
  description=$(extract_changelog_description "$commit_msg")
  CHANGESET_CONTENT=$(build_changeset_content "$affected" "$bump" "$description")
  CHANGESET_ACTIVE=true

  # Display proposed changeset
  local pkg_count
  pkg_count=$(echo "$affected" | wc -l)

  echo ""
  if [ -n "$EXISTING_CHANGESET_FILE" ]; then
    info "Proposed changeset update — ${pkg_count} package(s):"
  else
    info "Proposed changeset — ${pkg_count} package(s):"
  fi

  while IFS= read -r pkg; do
    echo -e "  ${CYAN}${pkg}${NC} → ${YELLOW}${bump}${NC}"
  done <<< "$affected"

  echo ""
  divider
  echo -e "${BOLD}${CHANGESET_CONTENT}${NC}"
  divider
}

# ── Confirm (called on accept) ──────────────────────────────────────────────

confirm_changeset() {
  local root="$1"
  [ "$CHANGESET_ACTIVE" = "true" ] || return 0

  echo ""
  if [ -n "$EXISTING_CHANGESET_FILE" ]; then
    # Existing changeset — offer update/replace/new/skip
    local existing_name
    existing_name=$(basename "$EXISTING_CHANGESET_FILE")
    menu_option "u" "update ${existing_name}    "
    menu_option "n" "create new    "
    menu_option "e" "edit first    "
    menu_option "s" "skip"
  else
    # No existing — offer create/edit/skip
    menu_option "a" "create changeset    "
    menu_option "e" "edit first    "
    menu_option "s" "skip"
  fi
  echo ""
  echo ""
  read -r -p "  > " cs_choice

  case "${cs_choice,,}" in
    u)
      # Update existing changeset
      if [ -n "$EXISTING_CHANGESET_FILE" ]; then
        update_changeset_file "$root" "$EXISTING_CHANGESET_FILE" "$CHANGESET_CONTENT"
      fi
      ;;
    a|n)
      create_changeset_file "$root" "$CHANGESET_CONTENT"
      ;;
    e)
      local tmpfile initial_content
      tmpfile=$(mktemp /tmp/ai-changeset-XXXXXX.md)

      # If updating, start with existing content merged with new
      if [ -n "$EXISTING_CHANGESET_FILE" ] && [ -f "${root}/${EXISTING_CHANGESET_FILE}" ]; then
        # Show existing content with new appended for editing
        {
          echo "# Existing changeset (${EXISTING_CHANGESET_FILE}):"
          echo "# Lines starting with # will be removed."
          echo ""
          cat "${root}/${EXISTING_CHANGESET_FILE}"
          echo ""
          echo "# --- Proposed addition from this commit: ---"
          echo ""
          echo "$CHANGESET_CONTENT"
        } > "$tmpfile"
      else
        printf '%s\n' "$CHANGESET_CONTENT" > "$tmpfile"
      fi

      ${EDITOR:-vim} "$tmpfile"
      local edited
      edited=$(grep -v '^#' "$tmpfile" | sed '/./,$!d')
      rm -f "$tmpfile"

      if [ -n "$edited" ]; then
        if [ -n "$EXISTING_CHANGESET_FILE" ]; then
          update_changeset_file "$root" "$EXISTING_CHANGESET_FILE" "$edited"
        else
          create_changeset_file "$root" "$edited"
        fi
      else
        warn "Empty changeset, skipped."
      fi
      ;;
    *)
      dim "  Changeset skipped."
      ;;
  esac
}

# ── File creation ────────────────────────────────────────────────────────────

create_changeset_file() {
  local root="$1"
  local content="$2"
  local name filepath
  name=$(generate_changeset_name)
  filepath="${root}/.changeset/${name}.md"

  printf '%s\n' "$content" > "$filepath"
  git add "$filepath"

  success "  Created: .changeset/${name}.md (staged)"
}

# ── File update ──────────────────────────────────────────────────────────────

update_changeset_file() {
  local root="$1"
  local existing_file="$2"
  local new_content="$3"
  local filepath="${root}/${existing_file}"

  # Replace the file with new content (preserves the filename)
  printf '%s\n' "$new_content" > "$filepath"
  git add "$filepath"

  success "  Updated: ${existing_file} (staged)"
}
