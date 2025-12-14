#!/usr/bin/env bash
# config.sh: Configuration variables for Stable Diffusion WebUI launcher

# Guard against multiple sourcing
[[ -n "${_CONFIG_SH_SOURCED:-}" ]] && return
_CONFIG_SH_SOURCED=1

# Enable strict mode but with verbose error reporting
set -uo pipefail

# Function to print variable values for debugging
debug_vars() {
  # Only show debug variables when in debug mode
  if [[ $LOG_LEVEL -le $DEBUG ]]; then
    echo "DEBUG VARIABLES:"
    echo "SD_WEBUI_VERSION=$SD_WEBUI_VERSION"
    echo "BASE_DIR=$BASE_DIR"
    echo "CODE_DIR=$CODE_DIR"
    echo "SD_WEBUI_SRC=$SD_WEBUI_SRC"
  fi
}

# Add trap for debugging
trap 'echo "ERROR in config.sh: Command failed with exit code $? at line $LINENO"' ERR

# Version and port configuration
# Version is substituted from Nix flake input (git short rev)
SD_WEBUI_VERSION="@sdWebuiVersion@"
SD_WEBUI_PORT="7860"

# CUDA configuration (can be overridden via environment)
# Supported versions: cu118, cu121, cu124, cpu
CUDA_VERSION="${CUDA_VERSION:-cu124}"

# Directory structure
# IMPORTANT: Path must NOT contain dotfiles (directories starting with .)
# Gradio blocks file serving from paths like ~/.config/ due to dotfile security.
# See: https://github.com/AUTOMATIC1111/stable-diffusion-webui/issues/13507
BASE_DIR="${SD_WEBUI_USER_DIR:-$HOME/sd-webui}"
CODE_DIR="$BASE_DIR/app"
SD_WEBUI_VENV="$BASE_DIR/venv"
OUTPUTS_DIR="$BASE_DIR/outputs"

# Environment variables for SD WebUI
ENV_VARS=(
  "PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0"
  "SD_WEBUI_USER_DIR=$BASE_DIR"
  "GRADIO_SERVER_PORT=$SD_WEBUI_PORT"
)

# Flag for browser opening
OPEN_BROWSER=false

# Additional flags for SD WebUI
LISTEN_MODE=false
API_MODE=false
SHARE_MODE=false

# Python paths (to be substituted by Nix)
PYTHON_ENV="@pythonEnv@/bin/python"

# Source paths (to be substituted by Nix)
SD_WEBUI_SRC="@sdWebuiSrc@"

# Directory lists for creation (single line to avoid newline issues)
# shellcheck disable=SC2034  # Used by install.sh when sourced
declare -A DIRECTORIES=(
  [base]="$BASE_DIR $CODE_DIR"
  [main]="$BASE_DIR/outputs $BASE_DIR/outputs/txt2img-images $BASE_DIR/outputs/img2img-images $BASE_DIR/outputs/extras-images $BASE_DIR/outputs/txt2img-grids $BASE_DIR/outputs/img2img-grids"
  [models]="$BASE_DIR/models/Stable-diffusion $BASE_DIR/models/Lora $BASE_DIR/models/VAE $BASE_DIR/models/hypernetworks $BASE_DIR/models/embeddings $BASE_DIR/models/ESRGAN $BASE_DIR/models/GFPGAN $BASE_DIR/models/Codeformer $BASE_DIR/models/ControlNet $BASE_DIR/models/BLIP $BASE_DIR/models/deepbooru $BASE_DIR/models/karlo"
  [other]="$BASE_DIR/extensions $BASE_DIR/configs"
)

# Python packages to install (as arrays for proper handling)
# shellcheck disable=SC2034  # Used by install.sh when sourced
BASE_PACKAGES=(pip setuptools wheel)

# PyTorch installation will be determined dynamically based on GPU availability
# This is set in install.sh based on platform detection

# Function to parse command line arguments
parse_arguments() {
  ARGS=()
  for arg in "$@"; do
    case "$arg" in
      --open)
        OPEN_BROWSER=true
        ;;
      --port=*)
        SD_WEBUI_PORT="${arg#*=}"
        ;;
      --listen)
        LISTEN_MODE=true
        ARGS+=("$arg")
        ;;
      --api)
        API_MODE=true
        ARGS+=("$arg")
        ;;
      --share)
        SHARE_MODE=true
        ARGS+=("$arg")
        ;;
      --debug)
        export LOG_LEVEL=$DEBUG
        ;;
      --verbose)
        export LOG_LEVEL=$DEBUG
        ;;
      *)
        ARGS+=("$arg")
        ;;
    esac
  done
}

# Export the configuration
export_config() {
  # Export all defined variables to make them available to sourced scripts
  export SD_WEBUI_VERSION SD_WEBUI_PORT BASE_DIR CODE_DIR SD_WEBUI_VENV OUTPUTS_DIR
  export OPEN_BROWSER PYTHON_ENV LISTEN_MODE API_MODE SHARE_MODE
  export SD_WEBUI_SRC

  # Export environment variables (eval is needed to properly export var=value pairs)
  for var in "${ENV_VARS[@]}"; do
    eval export "$var"
  done

  # Add CODE_DIR to PYTHONPATH
  export PYTHONPATH="$CODE_DIR:${PYTHONPATH:-}"
}
