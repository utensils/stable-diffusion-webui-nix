# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

```bash
# Build the package
nix build

# Run Stable Diffusion WebUI
nix run                     # Default
nix run .#api               # With API enabled
nix run .#listen            # With network listening enabled

# Run all CI checks (package build, shellcheck, nixfmt)
nix flake check

# Enter development shell
nix develop

# Format Nix files
nix fmt

# Docker images
nix run .#buildDocker       # Build CPU image
nix run .#buildDockerCuda   # Build CUDA image

# Check for upstream SD WebUI updates
nix run .#update
```

## Architecture Overview

This is a Nix flake that packages [Stable Diffusion WebUI](https://github.com/AUTOMATIC1111/stable-diffusion-webui) for reproducible deployment. The flake uses a hybrid approach: Nix handles environment setup and packaging, while pip manages Python dependencies at runtime.

### Key Design Decisions

1. **Runtime pip installation**: Python dependencies are installed via pip into a venv at `~/.config/sd-webui/venv` on first run, not at Nix build time. This allows GPU-specific PyTorch versions to be detected and installed dynamically.

2. **Nix variable substitution**: Shell scripts use `@varName@` placeholders that `pkgs.replaceVars` substitutes at build time. Only `config.sh` and `launcher.sh` have substitutions; other scripts are copied directly.

3. **Persistent data**: All user data lives in `~/.config/sd-webui/` with symlinks from the app directory. Models, outputs, extensions, and venv persist across updates.

### Script Flow

```
launcher.sh (entry point)
  -> sources config.sh (sets paths, parses args)
  -> sources logger.sh (logging utilities)
  -> sources install.sh (creates venv, installs deps)
  -> sources persistence.sh (sets up symlinks)
  -> sources runtime.sh (starts SD WebUI via launch.py)
```

### Flake Structure

- **Inputs**: `nixpkgs`, `flake-utils`, `sd-webui-src` (non-flake GitHub source)
- **Version**: Derived from `sd-webui-src.shortRev` (git short hash)
- **Packages**: `default` (main), `dockerImage` (CPU), `dockerImageCuda` (CUDA)
- **Apps**: `default`, `api`, `listen`, `buildDocker`, `buildDockerCuda`, `update`, linting apps
- **Checks**: `package`, `shellcheck`, `nixfmt`

### Directory Structure

```
~/.config/sd-webui/
├── app/                    # SD WebUI source code
├── venv/                   # Python virtual environment
├── models/                 # Model storage
│   ├── Stable-diffusion/   # Main checkpoints
│   ├── Lora/
│   ├── VAE/
│   ├── hypernetworks/
│   ├── embeddings/
│   └── ...
├── outputs/                # Generated images
├── extensions/             # Installed extensions
└── configs/                # User configurations
```

## Updating SD WebUI Version

SD WebUI source is tracked as a flake input, so updating is simple:

```bash
nix flake update sd-webui-src
```

This fetches the latest HEAD from GitHub. The version shown will be the git short rev (e.g., `ae05379`).
