# Stable Diffusion WebUI Nix

A Nix flake for [AUTOMATIC1111/stable-diffusion-webui](https://github.com/AUTOMATIC1111/stable-diffusion-webui) providing reproducible deployment with automatic GPU detection and Docker support.

## Features

- **Reproducible builds** via Nix flake
- **Automatic GPU detection** (NVIDIA CUDA, Apple MPS, CPU fallback)
- **Persistent data** in `~/.config/sd-webui/`
- **Docker images** (CPU and CUDA variants)
- **Python 3.10** (official upstream requirement)

## Quick Start

```bash
# Run Stable Diffusion WebUI
nix run github:utensils/stable-diffusion-webui-nix

# Run with network access (listen on 0.0.0.0)
nix run github:utensils/stable-diffusion-webui-nix -- --listen

# Run with API enabled
nix run github:utensils/stable-diffusion-webui-nix -- --api
```

## Installation

### Using Flakes (Recommended)

```bash
# Clone the repository
git clone https://github.com/utensils/stable-diffusion-webui-nix.git
cd stable-diffusion-webui-nix

# Run directly
nix run

# Or build and run
nix build
./result/bin/sd-webui
```

### Development Shell

```bash
nix develop
```

## Usage

### Command Line Options

```bash
# Basic usage
nix run

# Listen on all interfaces (for remote access)
nix run -- --listen

# Enable API
nix run -- --api

# Custom port
nix run -- --port 7861

# Open browser automatically
nix run -- --open

# Combine options
nix run -- --listen --api --port 7861
```

### Docker

```bash
# Build CPU image
nix run .#buildDocker

# Build CUDA image
nix run .#buildDockerCuda

# Run CPU container
docker run -p 7860:7860 -v $PWD/data:/data sd-webui:latest

# Run CUDA container
docker run --gpus all -p 7860:7860 -v $PWD/data:/data sd-webui:cuda
```

## Directory Structure

User data is stored in `~/.config/sd-webui/`:

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

## GPU Support

The flake automatically detects your GPU and installs the appropriate PyTorch version:

- **NVIDIA GPU**: Installs CUDA-enabled PyTorch (configurable via `CUDA_VERSION` env var)
- **Apple Silicon**: Uses MPS acceleration
- **No GPU**: Falls back to CPU-only PyTorch

### CUDA Version

Override the CUDA version with:

```bash
CUDA_VERSION=cu121 nix run -- --listen
```

Supported values: `cu118`, `cu121`, `cu124`, `cpu`

## Development

```bash
# Enter development shell
nix develop

# Run checks
nix flake check

# Format Nix files
nix fmt

# Lint shell scripts
nix run .#lint

# Check for updates
nix run .#update
```

## Updating

```bash
# Update SD WebUI source
nix flake update sd-webui-src

# Update all inputs
nix flake update
```

## License

This Nix flake is licensed under the [MIT License](LICENSE).

Note: Stable Diffusion WebUI itself is licensed under [AGPL-3.0](https://github.com/AUTOMATIC1111/stable-diffusion-webui/blob/master/LICENSE.txt).

## Credits

- [AUTOMATIC1111/stable-diffusion-webui](https://github.com/AUTOMATIC1111/stable-diffusion-webui) - The upstream project
- [utensils](https://github.com/utensils) - Nix packaging
