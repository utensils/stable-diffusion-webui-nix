# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

```bash
# Build the package
nix build

# Run Stable Diffusion WebUI
nix run                     # Default (localhost only)
nix run .#api               # With API enabled
nix run .#listen            # Listen on all interfaces (0.0.0.0)
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

- `CUDA_VERSION`: Override PyTorch CUDA version (`cu118`, `cu121`, `cu124`, `cpu`). Default: `cu124`. Only applies to Linux with NVIDIA GPUs.
- `SD_WEBUI_USER_DIR`: Override the user data directory. Default: `~/sd-webui`. **IMPORTANT:** Path must NOT contain dotfile directories (starting with `.`) - Gradio blocks file serving from such paths.
- `SD_WEBUI_FORCE_MPS`: Set to `true` to enable experimental MPS (Metal) acceleration on Apple Silicon instead of CPU mode. May produce corrupted images with PyTorch 2.5+.

## Platform Support

### Linux (x86_64)
- **NVIDIA GPU**: Full CUDA support with configurable CUDA version via `CUDA_VERSION`
- **CPU-only**: Automatically detected if no NVIDIA driver is available

### macOS
- **Apple Silicon (M1/M2/M3/M4)**: Currently runs in CPU mode due to PyTorch MPS bugs (see below)
- **Intel Mac (x86_64)**: CPU-only mode (no GPU acceleration available)

### macOS-Specific Environment Variables
These are automatically set on macOS (currently have no effect due to CPU mode workaround):
- `PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0`: Allows PyTorch to use all available GPU memory
- `PYTORCH_ENABLE_MPS_FALLBACK=1`: Falls back to CPU for operations not supported by MPS

These will take effect when MPS is re-enabled (via `SD_WEBUI_FORCE_MPS=true` or after PyTorch fixes).

### macOS Notes
- Docker images are Linux-only and not available on macOS
- First run on Apple Silicon will verify MPS availability

### Apple Silicon Launch Flags (Auto-Applied)
The following flags are automatically added on Apple Silicon:
- `--no-half`: Run model in full precision (fp32)
- `--use-cpu all`: Run all operations on CPU

### Why CPU Mode Instead of MPS?
PyTorch 2.5+ has known MPS (Metal Performance Shaders) bugs that cause green/corrupted images on Apple Silicon. Until these are fixed upstream, we default to CPU mode for reliability.

See: [PyTorch Issue #139389](https://github.com/pytorch/pytorch/issues/139389)

### Re-enabling MPS Acceleration (Experimental)

**Option 1: Force MPS mode (may produce corrupted images)**
```bash
SD_WEBUI_FORCE_MPS=true nix run
```

**Option 2: Downgrade PyTorch (recommended for MPS)**

Try downgrading to a known-working PyTorch version:
```bash
# First choice: PyTorch 2.3.1 (best MPS compatibility)
~/sd-webui/venv/bin/pip install torch==2.3.1 torchvision==0.18.1 torchaudio==2.3.1

# If 2.3.1 wheels unavailable, try 2.4.1
~/sd-webui/venv/bin/pip install torch==2.4.1 torchvision==0.19.1 torchaudio==2.4.1
```

Then enable MPS mode:
```bash
SD_WEBUI_FORCE_MPS=true nix run
```

Check PyTorch's platform support for available versions: https://pytorch.org/get-started/previous-versions/

### Performance Expectations (Apple Silicon)

| Mode | Generation Speed (512x512) | Image Quality | Notes |
|------|---------------------------|---------------|-------|
| CPU (default) | ~30-60 seconds | ✅ Correct | Reliable, slower |
| MPS + PyTorch 2.3.1 | ~5-10 seconds | ✅ Correct | Requires downgrade |
| MPS + PyTorch 2.5+ | ~5-10 seconds | ❌ Green/corrupted | Known bug |

*Times are approximate and vary by model and system.*

## Architecture Overview

This is a Nix flake that packages [Stable Diffusion WebUI](https://github.com/AUTOMATIC1111/stable-diffusion-webui) for reproducible deployment. The flake uses a hybrid approach: Nix handles environment setup and packaging, while pip manages Python dependencies at runtime.

### Key Design Decisions

1. **Runtime pip installation**: Python dependencies are installed via pip into a venv at `~/sd-webui/venv` on first run, not at Nix build time. This allows GPU-specific PyTorch versions to be detected and installed dynamically.

2. **Nix variable substitution**: Shell scripts use `@varName@` placeholders that `pkgs.replaceVars` substitutes at build time:
   - `config.sh`: `@pythonEnv@`, `@sdWebuiSrc@`, `@sdWebuiVersion@`
   - `launcher.sh`: `@libPath@` (Linux-only; empty on macOS)
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

### Option 4: Direct Listen

Basic network listening without authentication. Works with the new `~/sd-webui` default path.

```bash
nix run .#listen                   # Listen on 0.0.0.0:7860
```

### Troubleshooting 403 Errors

If you see 403 errors for `style.css`, `script.js`, or other static files:

1. **Check your installation path** - If it contains `.` directories (like `~/.config/`), move to `~/sd-webui/`
2. **Set SD_WEBUI_USER_DIR** - `SD_WEBUI_USER_DIR=~/sd-webui nix run .#listen`
3. **Use SSH tunnel** - `ssh -L 7860:localhost:7860 user@host`
4. **Use `nix run .#share`** - Creates a public tunnel URL
5. **Verify paths** - Run with `--debug` to see the paths being used

## Updating SD WebUI Version

SD WebUI source is pinned to a specific tag (currently `v1.10.1`) in the flake input.

To update to a new version, edit `flake.nix` and change the tag:

```nix
sd-webui-src = {
  url = "github:AUTOMATIC1111/stable-diffusion-webui/v1.10.1";  # Change tag here
  flake = false;
};
```

Then update the lock file:

```bash
nix flake update sd-webui-src
```
