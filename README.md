<p align="center">
  <img src="https://buungroup.com/logo/logo.svg" alt="Buun Group" height="60" />
</p>

<h1 align="center">Development Setup</h1>

<p align="center">
  Shared development tooling by Buun Group. One command to install, runs entirely local.
</p>

---

## Quick Install

One command - installs `just`, clones the repo, and runs the full setup:

```bash
curl -fsSL https://raw.githubusercontent.com/BuunGroup-Packages/development-setup/main/setup.sh | bash
```

Or if you prefer to clone manually:

```bash
git clone https://github.com/buun-group/development-setup.git
cd development-setup
just install
```

The installer walks you through everything: `just`, system dependencies, Ollama, model profile selection, git hooks, and PATH setup.

> **Windows users:** Run inside WSL2. Native Windows/PowerShell is not supported.

## Available Commands

```
just                        # list all commands
just install                # full end-to-end install
just uninstall              # remove ai-commit and optionally the Ollama model
just profiles               # list available model profiles
just build                  # build all Modelfiles from config
just build large            # build a specific profile
just create large           # create an Ollama model from a built profile
just add-profile large      # build + create in one step
just rebuild                # rebuild all profiles and recreate all Ollama models
just hooks                  # install git hooks into current repo
just hooks /path/to/repo    # install git hooks into specific repo
just hooks-scoped "api,app" # install hooks with specific scopes
just status                 # show active profile and installed models
just test                   # run ai-commit in current repo
```

## What Gets Installed

### ai-commit

AI-powered git commit message generator using a local Ollama model. Analyzes your staged diff, commit history, and repo conventions to generate Conventional Commits messages aligned with SemVer 2.0.0.

```bash
git add -p
ai-commit
```

**Features:**
- Runs 100% locally via Ollama (no API keys, no data leaves your machine)
- Auto-detects commitlint config, husky hooks, and repo conventions
- Validates output against Conventional Commits format
- Auto-generates changesets for monorepos using `@changesets/cli`
- Interactive: accept, edit, regenerate, copy, or quit
- Multiple model profiles for different hardware

### Git Hooks

Configurable git hooks that enforce standards without external dependencies (no husky, no commitlint npm packages needed).

```bash
# Install into any repo
just hooks

# Install with specific scopes
just hooks-scoped "api,app,shared,ui"
```

**What gets installed:**

| Hook | What it does |
|------|-------------|
| `commit-msg` | Validates Conventional Commits format, types, scopes, length |
| `pre-commit` | Blocks sensitive files (`.env`, `.pem`, credentials), debug artifacts (`.sqlite`, `.wrangler/`), warns on `console.log()` |

**Configuration:** Each repo gets a `.githooks.conf` that controls the hooks:

```bash
# .githooks.conf — committed to the repo, shared with the team
COMMIT_TYPES="feat|fix|perf|chore|docs|refactor|test|ci|build|style"
COMMIT_SCOPES="api|app|shared|ui"          # leave empty for any scope
COMMIT_MAX_LENGTH=100
COMMIT_REQUIRE_SCOPE=false
FORBIDDEN_FILES='\.env$|\.pem$|\.key$'     # regex patterns
CONSOLE_LOG_EXTENSIONS='ts|tsx|js|jsx'
```

The hooks auto-detect scopes from your `apps/` and `packages/` directories during install. Commit the hooks and config to your repo so the whole team gets them on `npm install` (via the `prepare` script).

## Model Profiles

Ollama models are created as `buun-commit-<profile>`. The installer lets you pick a profile. Switch anytime:

| Profile   | Base Model     | Context | Best for                        |
|-----------|----------------|---------|----------------------------------|
| `default` | gemma4 8B      | 8K      | Balanced speed and quality       |
| `small`   | gemma3 4B      | 4K      | Fast, lower resource usage       |
| `qwen`    | qwen3 8B       | 8K      | Alternative model                |
| `large`   | gemma4 8B      | 32K     | Huge diffs, monorepos            |

Switch profile per-command:
```bash
OLLAMA_COMMIT_PROFILE=large ai-commit
```

Set default profile:
```bash
echo "small" > ~/.local/share/ai-commit/.profile
```

### Adding a Custom Profile

```bash
# 1. Add a line to profiles.conf
# 2. Build and create in one step
just add-profile myprofile
```

Or rebuild everything after editing the system prompt:
```bash
just rebuild
```

## File Structure

```
development-setup/                               # this repo
  justfile                                        # command runner
  scripts/
    install.sh                                    # end-to-end installer
    install-hooks.sh                              # git hooks installer
    uninstall.sh                                  # clean removal
  ai-commit/
    ai-commit                                     # main script
    lib/                                          # bash libraries
      changeset.sh                                # changeset detection + generation
    hooks/                                        # git hook templates
      commit-msg                                  # conventional commits validation
      pre-commit                                  # sensitive file / debug checks
      hooks.conf.example                          # config reference
    models/
      system-prompt.txt                           # shared prompt (all profiles)
      profiles.conf                               # profile definitions
      build.sh                                    # generates Modelfiles

~/.local/bin/ai-commit                            # installed binary
~/.local/share/ai-commit/                         # installed data
  .profile                                        # active profile
  lib/                                            # runtime libraries
  hooks/                                          # hook templates
  models/                                         # model configs + generated files

your-repo/                                        # after just hooks
  .githooks/
    commit-msg                                    # installed hook
    pre-commit                                    # installed hook
  .githooks.conf                                  # hook configuration
```

## Uninstall

```bash
just uninstall
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add new model profiles, modify the system prompt, or add new tools.
