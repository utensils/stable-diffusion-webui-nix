#!/usr/bin/env bash
# install.sh: Installation steps for Stable Diffusion WebUI

# Guard against multiple sourcing
[[ -n "${_INSTALL_SH_SOURCED:-}" ]] && return
_INSTALL_SH_SOURCED=1

# Source shared libraries
[ -z "$SCRIPT_DIR" ] && SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
source "$SCRIPT_DIR/logger.sh"

# Create directory structures
create_directories() {
    log_section "Creating directory structure"

    # Add debugging to see what's in DIRECTORIES
    log_debug "Directory types: ${!DIRECTORIES[*]}"

    for dir_type in "${!DIRECTORIES[@]}"; do
        log_debug "Creating $dir_type directories: ${DIRECTORIES[$dir_type]}"
        for dir in ${DIRECTORIES[$dir_type]}; do
            mkdir -p "$dir"
            log_debug "Created: $dir"
        done
    done

    log_info "All directories created successfully"
}

# Install SD WebUI core
install_sd_webui() {
    log_section "Installing Stable Diffusion WebUI $SD_WEBUI_VERSION"

    # Remove existing directory (but keep symlinked content safe)
    log_info "Preparing fresh installation in $CODE_DIR"
    rm -rf "$CODE_DIR"
    mkdir -p "$CODE_DIR"

    # Copy the SD WebUI source
    log_info "Copying SD WebUI source code"
    cp -r "$SD_WEBUI_SRC"/* "$CODE_DIR/"
    echo "$SD_WEBUI_VERSION" > "$CODE_DIR/VERSION"

    # Ensure proper permissions
    chmod -R u+rw "$CODE_DIR"

    log_info "SD WebUI core installed successfully"
}

# Detect GPU and determine PyTorch installation
# Uses stable PyTorch releases instead of nightly builds for production stability
# CUDA version can be configured via CUDA_VERSION environment variable
detect_pytorch_version() {
    local TORCH_INSTALL=""
    local cuda_ver="${CUDA_VERSION:-cu124}"

    # Check for NVIDIA GPU
    if command -v nvidia-smi &> /dev/null; then
        log_info "NVIDIA GPU detected"
        if nvidia-smi &> /dev/null; then
            log_info "NVIDIA driver is functional"
            log_info "Using CUDA version: $cuda_ver (override with CUDA_VERSION env var)"
            # Install stable PyTorch with CUDA support
            TORCH_INSTALL="torch torchvision torchaudio --index-url https://download.pytorch.org/whl/${cuda_ver}"
        else
            log_warn "NVIDIA driver not functioning properly, falling back to CPU"
            TORCH_INSTALL="torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]] && [[ $(uname -m) == "arm64" ]]; then
        log_info "Apple Silicon detected, using MPS acceleration"
        # On macOS, use default PyPI packages which include MPS support
        TORCH_INSTALL="torch torchvision torchaudio"
    else
        log_info "No GPU detected, using CPU-only PyTorch"
        TORCH_INSTALL="torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu"
    fi

    echo "$TORCH_INSTALL"
}

# Setup Python virtual environment
setup_venv() {
    log_section "Setting up Python environment"

    local version_file="$SD_WEBUI_VENV/.sd_webui_version"
    local needs_requirements_update=false

    if [ ! -d "$SD_WEBUI_VENV" ]; then
        log_info "Creating virtual environment for SD WebUI at $SD_WEBUI_VENV"
        "$PYTHON_ENV" -m venv "$SD_WEBUI_VENV"
        needs_requirements_update=true
    else
        log_info "Using existing Python environment"
        # Check if SD WebUI version changed - if so, we need to update requirements
        if [ -f "$version_file" ]; then
            local installed_version
            installed_version=$(cat "$version_file")
            if [ "$installed_version" != "$SD_WEBUI_VERSION" ]; then
                log_info "SD WebUI version changed ($installed_version -> $SD_WEBUI_VERSION)"
                needs_requirements_update=true
            fi
        else
            # No version file means old installation, needs update
            log_info "Upgrading venv for new SD WebUI version"
            needs_requirements_update=true
        fi
    fi

    if [ "$needs_requirements_update" = true ]; then
        log_info "Installing/updating Python dependencies for SD WebUI $SD_WEBUI_VERSION"
        "$SD_WEBUI_VENV/bin/pip" install --upgrade pip

        # Detect and install appropriate PyTorch version first
        local TORCH_INSTALL
        TORCH_INSTALL=$(detect_pytorch_version)
        log_info "Installing PyTorch: $TORCH_INSTALL"
        # shellcheck disable=SC2086
        "$SD_WEBUI_VENV/bin/pip" install $TORCH_INSTALL

        # Install from requirements_versions.txt (primary method)
        if [ -f "$CODE_DIR/requirements_versions.txt" ]; then
            log_info "Installing from requirements_versions.txt..."
            "$SD_WEBUI_VENV/bin/pip" install -r "$CODE_DIR/requirements_versions.txt" || {
                log_warn "Some requirements_versions.txt packages failed, continuing..."
            }
        elif [ -f "$CODE_DIR/requirements.txt" ]; then
            log_info "Installing from requirements.txt..."
            "$SD_WEBUI_VENV/bin/pip" install -r "$CODE_DIR/requirements.txt" || {
                log_warn "Some requirements.txt packages failed, continuing..."
            }
        fi

        # Install base packages
        "$SD_WEBUI_VENV/bin/pip" install "${BASE_PACKAGES[@]}"

        # Record installed version
        echo "$SD_WEBUI_VERSION" > "$version_file"
        log_info "Python environment setup complete for SD WebUI $SD_WEBUI_VERSION"

        # Clear CUDA check file to re-verify after update
        rm -f "$SD_WEBUI_VENV/.cuda_checked"
    fi

    # Check if we need to upgrade PyTorch for GPU support
    local cuda_check_file="$SD_WEBUI_VENV/.cuda_checked"
    if [ ! -f "$cuda_check_file" ] && command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        # Test CUDA availability with proper library paths
        local cuda_test_result=1
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}" "$SD_WEBUI_VENV/bin/python" -c "import torch; exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null && cuda_test_result=0
        else
            "$SD_WEBUI_VENV/bin/python" -c "import torch; exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null && cuda_test_result=0
        fi

        if [ $cuda_test_result -ne 0 ]; then
            log_warn "CUDA not available in current PyTorch installation"
            log_info "Reinstalling PyTorch with CUDA support..."
            local TORCH_INSTALL
            TORCH_INSTALL=$(detect_pytorch_version)
            "$SD_WEBUI_VENV/bin/pip" uninstall -y torch torchvision torchaudio
            # shellcheck disable=SC2086
            "$SD_WEBUI_VENV/bin/pip" install $TORCH_INSTALL
            touch "$cuda_check_file"
        else
            log_info "PyTorch already has CUDA support"
            touch "$cuda_check_file"
        fi
    else
        log_debug "Skipping CUDA check (already verified)"
    fi
}

# Main installation function
install_all() {
    create_directories
    install_sd_webui
    setup_venv

    # Now set up the actual symlinks
    source "$SCRIPT_DIR/persistence.sh"
    setup_persistence

    log_section "Installation complete"
    log_info "Stable Diffusion WebUI $SD_WEBUI_VERSION has been successfully installed"
}
