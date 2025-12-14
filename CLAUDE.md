# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

```bash
# Build the package
nix build

# Run Stable Diffusion WebUI
nix run                     # Default (localhost only)
nix run .#api               # With API enabled
nix run .#listen            # Listen on network (localhost access only)
nix run .#remote            # Remote access with auth (admin:admin)
nix run .#share             # Remote access via Gradio public tunnel
nix run -- --debug          # With debug logging

# Run all CI checks (package build, shellcheck, nixfmt)
nix flake check

# Enter development shell
nix develop

# Format Nix files
nix fmt

# Linting
nix run .#lint              # Run ruff linter
nix run .#lint-fix          # Run ruff with auto-fix

# Docker images
nix run .#buildDocker       # Build CPU image
nix run .#buildDockerCuda   # Build CUDA image

# Check for upstream SD WebUI updates
nix run .#update
```

## Environment Variables

- `CUDA_VERSION`: Override PyTorch CUDA version (`cu118`, `cu121`, `cu124`, `cpu`). Default: `cu124`
- `SD_WEBUI_USER_DIR`: Override the user data directory. Default: `~/sd-webui`. **IMPORTANT:** Path must NOT contain dotfile directories (starting with `.`) - Gradio blocks file serving from such paths.

## Architecture Overview

This is a Nix flake that packages [Stable Diffusion WebUI](https://github.com/AUTOMATIC1111/stable-diffusion-webui) for reproducible deployment. The flake uses a hybrid approach: Nix handles environment setup and packaging, while pip manages Python dependencies at runtime.

### Key Design Decisions

1. **Runtime pip installation**: Python dependencies are installed via pip into a venv at `~/sd-webui/venv` on first run, not at Nix build time. This allows GPU-specific PyTorch versions to be detected and installed dynamically.

2. **Nix variable substitution**: Shell scripts use `@varName@` placeholders that `pkgs.replaceVars` substitutes at build time:
   - `config.sh`: `@pythonEnv@`, `@sdWebuiSrc@`, `@sdWebuiVersion@`
   - `launcher.sh`: `@libPath@`
   - Other scripts (`logger.sh`, `install.sh`, `persistence.sh`, `runtime.sh`) are copied directly without substitutions.

3. **Persistent data**: All user data lives in `~/sd-webui/` with symlinks from the app directory. Models, outputs, extensions, and venv persist across updates.

4. **Git repository initialization**: After copying SD WebUI source, `install.sh` initializes a minimal git repository with the version tag. This allows SD WebUI to detect its version properly and prevents "fatal: not a git repository" errors.

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
- **Apps**: `default`, `api`, `listen`, `remote`, `share`, `buildDocker`, `buildDockerCuda`, `update`, linting apps
- **Checks**: `package`, `shellcheck`, `nixfmt`

### Directory Structure

```
~/sd-webui/
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

## Network/Remote Access

Gradio 3.41.x has strict file serving security that can cause 403 errors when accessing from remote clients.

### Root Cause: Dotfile Paths

**IMPORTANT**: The most common cause of 403 errors is having SD WebUI installed in a path containing dotfile directories (directories starting with `.`). For example, `~/.config/sd-webui/` will cause Gradio to block ALL file serving because `.config` is treated as a dotfile path.

**Solution**: Use a path without dotfiles, like `~/sd-webui/` (the new default).

See: [GitHub Issue #13507](https://github.com/AUTOMATIC1111/stable-diffusion-webui/issues/13507)

### Option 1: Gradio Public Tunnel

The most reliable way to access SD WebUI remotely. Creates a public URL that bypasses all local network issues.

```bash
nix run .#share                    # Creates https://xxxxx.gradio.live URL
nix run .#share -- --api           # With API enabled
```

Note: Share links expire after 72 hours and require internet connectivity.

### Option 2: SSH Tunnel (Secure, No Internet Required)

Forward the local port through SSH. Works reliably for LAN access.

```bash
# On your local machine, create a tunnel to the server running SD WebUI:
ssh -L 7860:localhost:7860 user@server-hostname

# Then access SD WebUI at http://localhost:7860
```

### Option 3: Listen with Authentication

Enable network listening with authentication. May still have issues with static files in some Gradio versions.

```bash
nix run .#remote                           # Default admin:admin
SD_WEBUI_AUTH=user:pass nix run .#remote   # Custom credentials
```

### Option 4: Direct Listen (Limited)

Basic network listening without authentication. Only works properly from localhost.

```bash
nix run .#listen                   # 403 errors expected from remote clients
```

### Troubleshooting 403 Errors

If you see 403 errors for `style.css`, `script.js`, or other static files:

1. **Check your installation path** - If it contains `.` directories (like `~/.config/`), move to `~/sd-webui/`
2. **Set SD_WEBUI_USER_DIR** - `SD_WEBUI_USER_DIR=~/sd-webui nix run .#listen`
3. **Use SSH tunnel** - `ssh -L 7860:localhost:7860 user@host`
4. **Use `nix run .#share`** - Creates a public tunnel URL
5. **Verify paths** - Run with `--debug` to see the paths being used

## Updating SD WebUI Version

SD WebUI source is tracked as a flake input, so updating is simple:

```bash
nix flake update sd-webui-src
```

This fetches the latest HEAD from GitHub. The version shown will be the git short rev (e.g., `ae05379`).
