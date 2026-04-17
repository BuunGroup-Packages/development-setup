# Development Setup
# Run 'just' to see available recipes

# Default: show available recipes
default:
    @just --list

# Install everything (dependencies, Ollama, ai-commit, model)
install:
    @bash scripts/install.sh

# Uninstall ai-commit and optionally remove the Ollama model
uninstall:
    @bash scripts/uninstall.sh

# List available model profiles
profiles:
    @bash ai-commit/models/build.sh --list

# Build Modelfile(s) from profiles.conf + system prompt
build profile='':
    @if [ -n "{{ profile }}" ]; then \
        bash ai-commit/models/build.sh "{{ profile }}"; \
    else \
        bash ai-commit/models/build.sh; \
    fi

# Create an Ollama model from a built profile
create profile='default':
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ profile }}" = "default" ]; then
        name="buun-commit"
    else
        name="buun-commit-{{ profile }}"
    fi
    modelfile="ai-commit/models/generated/{{ profile }}.modelfile"
    if [ ! -f "$modelfile" ]; then
        echo "Modelfile not found. Building first..."
        bash ai-commit/models/build.sh "{{ profile }}"
    fi
    ollama create "$name" -f "$modelfile"
    echo "Created: $name"

# Build and create a profile in one step
add-profile profile:
    just build {{ profile }}
    just create {{ profile }}

# Rebuild all profiles and recreate their Ollama models
rebuild:
    #!/usr/bin/env bash
    set -euo pipefail
    bash ai-commit/models/build.sh
    while IFS='|' read -r profile base temp predict ctx desc; do
        [[ "$profile" =~ ^#.*$ || -z "$profile" ]] && continue
        if [ "$profile" = "default" ]; then
            name="buun-commit"
        else
            name="buun-commit-${profile}"
        fi
        echo "Creating ${name}..."
        ollama create "$name" -f "ai-commit/models/generated/${profile}.modelfile"
    done < ai-commit/models/profiles.conf
    echo "All models rebuilt."

# Install git hooks into a repo (current dir or specify path)
hooks repo='':
    @if [ -n "{{ repo }}" ]; then \
        bash scripts/install-hooks.sh "{{ repo }}"; \
    else \
        bash scripts/install-hooks.sh; \
    fi

# Install git hooks with specific scopes
hooks-scoped scopes repo='':
    @if [ -n "{{ repo }}" ]; then \
        bash scripts/install-hooks.sh --scopes "{{ scopes }}" "{{ repo }}"; \
    else \
        bash scripts/install-hooks.sh --scopes "{{ scopes }}"; \
    fi

# Test ai-commit against the current repo
test:
    @cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" && ai-commit

# Show which model profile is currently active
status:
    #!/usr/bin/env bash
    profile_file="${HOME}/.local/share/ai-commit/.profile"
    if [ -f "$profile_file" ]; then
        echo "Active profile: $(cat "$profile_file")"
    else
        echo "No profile set (not installed)"
    fi
    echo ""
    echo "Installed models:"
    ollama list 2>/dev/null | grep buun-commit || echo "  (none)"
