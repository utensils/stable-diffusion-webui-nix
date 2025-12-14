#!/usr/bin/env bash
# Main launcher for Stable Diffusion WebUI - entry point that sources modular components

# Enable strict mode but with error trapping
set -uo pipefail

# Add error trap for debugging
trap 'echo "ERROR: Command failed with exit code $? at line $LINENO in $BASH_SOURCE"' ERR

# Get the directory where this script is located
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# When running in production from Nix store, scripts will be in share directory
if [[ "$SCRIPT_DIR" == *"/bin" ]]; then
  SHARE_DIR="$(dirname "$SCRIPT_DIR")/share/sd-webui/nix-launcher"
  if [[ -d "$SHARE_DIR" ]]; then
    SCRIPT_DIR="$SHARE_DIR"
  fi
fi

# Source the component scripts
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/logger.sh"
source "$SCRIPT_DIR/install.sh"
source "$SCRIPT_DIR/persistence.sh"
source "$SCRIPT_DIR/runtime.sh"

# Platform-specific library path handling
# Note: @libPath@ is only set on Linux, empty on macOS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux: Set LD_LIBRARY_PATH for libstdc++ and other required libraries
    # shellcheck disable=SC2157  # @libPath@ is substituted at build time by Nix
    if [[ -n "@libPath@" ]]; then
        export LD_LIBRARY_PATH="@libPath@:${LD_LIBRARY_PATH:-}"
    fi
    # Add NVIDIA/CUDA libraries if available
    if [ -d "/run/opengl-driver/lib" ]; then
        export LD_LIBRARY_PATH="/run/opengl-driver/lib:${LD_LIBRARY_PATH}"
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS: No library path manipulation needed
    # Nix handles all library dependencies, and MPS env vars are set in config.sh
    :
fi

# Main function
main() {
    # Parse command-line arguments
    parse_arguments "$@"

    # Export configuration
    export_config

    # Welcome message
    log_section "Stable Diffusion WebUI Launcher"
    log_info "Starting SD WebUI launcher for version $SD_WEBUI_VERSION"

    # Call debug function from config.sh
    debug_vars

    # Debug info (only shown in debug mode)
    log_debug "SCRIPT_DIR: $SCRIPT_DIR"
    log_debug "BASE_DIR: $BASE_DIR"
    log_debug "PYTHONPATH: $PYTHONPATH"
    log_debug "SD_WEBUI_SRC: $SD_WEBUI_SRC"

    # Installation steps (includes persistence setup)
    install_all

    # Start SD WebUI
    start_sd_webui
}

# Run the main function
main "$@"
