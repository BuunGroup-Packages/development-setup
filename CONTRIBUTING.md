# Contributing

## Repository Structure

```
development-setup/
  install.sh                            # wrapper (delegates to scripts/)
  scripts/
    install.sh                          # end-to-end installer
    uninstall.sh                        # clean removal
  ai-commit/
    ai-commit                           # main script
    lib/                                # bash libraries (sourced at runtime)
      colors.sh                         # terminal output helpers
      git.sh                            # git context gathering
      ollama.sh                         # ollama API interaction
      commit.sh                         # message cleaning, validation, commit
    models/
      system-prompt.txt                 # shared system prompt for all profiles
      profiles.conf                     # model profile definitions
      build.sh                          # generates Modelfiles from config
      generated/                        # built Modelfiles (gitignored)
```

## Adding a New Model Profile

Profiles let the team use different Ollama models depending on their hardware or preference. Each profile produces its own Ollama model with the shared system prompt baked in.

### Step 1: Find a model on Ollama

Browse available models at https://ollama.com/search

Some good candidates for commit message generation:

| Model | Size | Link |
|-------|------|------|
| gemma4 | 5.9GB - 9.6GB | https://ollama.com/library/gemma4 |
| gemma3 | 1.6GB - 5.7GB | https://ollama.com/library/gemma3 |
| qwen3 | 2.5GB - 5.2GB | https://ollama.com/library/qwen3 |
| llama3.2 | 2.0GB - 4.9GB | https://ollama.com/library/llama3.2 |
| phi4 | 9.1GB | https://ollama.com/library/phi4 |
| mistral | 4.1GB | https://ollama.com/library/mistral |
| deepseek-r1 | 4.7GB | https://ollama.com/library/deepseek-r1 |

When choosing a model, consider:
- **Size**: smaller models run faster but produce less detailed output
- **Context window**: larger context = more diff lines the model can see
- **Instruction following**: the model must follow strict output formatting — test it before adding

### Step 2: Pull the model locally

```bash
ollama pull gemma4:latest
```

You can see all available tags (sizes/quantizations) on the model's page. For example, https://ollama.com/library/gemma4 shows tags like `gemma4:12b`, `gemma4:27b`, etc.

### Step 3: Add a profile entry

Edit `ai-commit/models/profiles.conf` and add a line:

```
# Format: profile|base_model|temperature|num_predict|num_ctx|description
```

| Field | Description |
|-------|-------------|
| `profile` | Short name used as the identifier (e.g. `fast`, `gpu`, `tiny`) |
| `base_model` | Ollama model name with tag (e.g. `gemma4:latest`, `gemma3:4b`) |
| `temperature` | 0.0-1.0, lower = more deterministic. Use 0.05-0.15 for commits |
| `num_predict` | Max tokens to generate. 300-400 is good for commit messages |
| `num_ctx` | Context window size. Determines how much diff fits. Match to model capability |
| `description` | Shown in the installer menu. Keep it short |

Example:

```
fast|gemma3:1b|0.1|200|2048|Gemma 3 1B - fastest, minimal resources
```

### Step 4: Test it

```bash
# Build and create in one step
just add-profile fast

# Test it
cd /path/to/any/git/repo
git add -p
OLLAMA_COMMIT_PROFILE=fast ai-commit
```

Verify that:
1. The output starts with a valid type (`feat`, `fix`, etc.)
2. No markdown formatting, no preamble text
3. Body bullets are meaningful when multiple files change
4. Subject line stays under 72 characters

### Step 5: Submit a PR

Include:
- The new line in `profiles.conf`
- A note on what hardware you tested on (CPU/GPU, RAM)
- Sample output from a real commit

## Modifying the System Prompt

The system prompt at `ai-commit/models/system-prompt.txt` is shared across all profiles. If you change it:

1. Edit `system-prompt.txt`
2. Rebuild all profiles and recreate Ollama models:
   ```bash
   just rebuild
   ```
3. Test with a real staged diff before submitting

The prompt is the single biggest lever for output quality. Changes should be tested across at least 2-3 different sized commits (single file fix, multi-file feature, large refactor).

## Tuning Parameters

If a model produces poor output, adjust these in `profiles.conf` before changing the prompt:

| Parameter | Effect |
|-----------|--------|
| `temperature` | Lower (0.05) = rigid and repetitive. Higher (0.3) = creative but may ignore format. Sweet spot is 0.1-0.15 |
| `num_predict` | Too low = truncated body. Too high = model rambles. 300-400 works well |
| `num_ctx` | Must match model's actual capability. Setting higher than the model supports wastes memory with no benefit |

## Adding New Tools

This repo is designed to grow beyond `ai-commit`. To add a new tool:

1. Create a new directory at the repo root (e.g. `ai-review/`)
2. Follow the same structure: `lib/` for bash functions, `models/` if it uses Ollama
3. Share common code via a top-level `lib/` if needed
4. Update `scripts/install.sh` to copy the new tool's files
5. Update the README
