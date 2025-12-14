#!/usr/bin/env bash
# persistence.sh: Setup persistence for Stable Diffusion WebUI data

# Guard against multiple sourcing
[[ -n "${_PERSISTENCE_SH_SOURCED:-}" ]] && return
_PERSISTENCE_SH_SOURCED=1

# Source shared libraries
[ -z "$SCRIPT_DIR" ] && SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
source "$SCRIPT_DIR/logger.sh"

# Create symlinks for persistent directories
create_symlinks() {
    log_section "Setting up symlinks for persistence"

    # Setup output directory symlink
    log_debug "Setting up output directory symlink"
    if [ -d "$CODE_DIR/outputs" ] && [ ! -L "$CODE_DIR/outputs" ]; then
        # Move any existing outputs to persistent location
        if [ "$(ls -A "$CODE_DIR/outputs" 2>/dev/null)" ]; then
            log_info "Migrating existing outputs to persistent location"
            cp -rn "$CODE_DIR/outputs"/* "$BASE_DIR/outputs/" 2>/dev/null || true
        fi
        log_debug "Removing existing directory: $CODE_DIR/outputs"
        rm -rf "${CODE_DIR:?}/outputs"
    fi
    ln -sf "$BASE_DIR/outputs" "$CODE_DIR/outputs"

    # Add main models directory link for compatibility
    log_debug "Setting up models root symlink"
    if [ -d "$CODE_DIR/models" ] && [ ! -L "$CODE_DIR/models" ]; then
        # Move any existing models to persistent location
        if [ "$(ls -A "$CODE_DIR/models" 2>/dev/null)" ]; then
            log_info "Migrating existing models to persistent location"
            cp -rn "$CODE_DIR/models"/* "$BASE_DIR/models/" 2>/dev/null || true
        fi
        rm -rf "${CODE_DIR:?}/models"
    fi
    ln -sf "$BASE_DIR/models" "$CODE_DIR/models"

    # Setup extensions directory symlink
    log_debug "Setting up extensions directory symlink"
    if [ -d "$CODE_DIR/extensions" ] && [ ! -L "$CODE_DIR/extensions" ]; then
        # Move any existing extensions to persistent location
        if [ "$(ls -A "$CODE_DIR/extensions" 2>/dev/null)" ]; then
            log_info "Migrating existing extensions to persistent location"
            cp -rn "$CODE_DIR/extensions"/* "$BASE_DIR/extensions/" 2>/dev/null || true
        fi
        rm -rf "${CODE_DIR:?}/extensions"
    fi
    ln -sf "$BASE_DIR/extensions" "$CODE_DIR/extensions"

    # Setup embeddings directory symlink (SD WebUI stores embeddings separately)
    log_debug "Setting up embeddings directory symlink"
    if [ -d "$CODE_DIR/embeddings" ] && [ ! -L "$CODE_DIR/embeddings" ]; then
        if [ "$(ls -A "$CODE_DIR/embeddings" 2>/dev/null)" ]; then
            log_info "Migrating existing embeddings to persistent location"
            cp -rn "$CODE_DIR/embeddings"/* "$BASE_DIR/models/embeddings/" 2>/dev/null || true
        fi
        rm -rf "${CODE_DIR:?}/embeddings"
    fi
    ln -sf "$BASE_DIR/models/embeddings" "$CODE_DIR/embeddings"

    log_info "Basic symlinks created"
}

# Create symlinks for all model directories
create_model_symlinks() {
    log_section "Setting up model directory symlinks"

    # SD WebUI model directory structure
    local MODEL_DIRS=(
        "Stable-diffusion" "Lora" "VAE" "hypernetworks"
        "embeddings" "ESRGAN" "GFPGAN" "Codeformer"
        "ControlNet" "BLIP" "deepbooru" "karlo"
    )

    # Ensure models directory exists in persistent location
    mkdir -p "$BASE_DIR/models"

    for dir in "${MODEL_DIRS[@]}"; do
        mkdir -p "$BASE_DIR/models/$dir"
        log_debug "Ensured: $BASE_DIR/models/$dir"
    done

    log_info "Model directories prepared"
}

# Verify symlinks are correctly setup
verify_symlinks() {
    log_section "Verifying symlinks"

    local failures=0

    # Check basic symlinks
    for link in "outputs" "models" "extensions"; do
        if [ ! -L "$CODE_DIR/$link" ]; then
            log_error "Missing symlink: $CODE_DIR/$link"
            failures=$((failures+1))
        fi
    done

    # Check model directories exist
    for dir in "Stable-diffusion" "Lora" "VAE" "embeddings"; do
        if [ ! -d "$BASE_DIR/models/$dir" ]; then
            log_error "Missing model directory: $BASE_DIR/models/$dir"
            failures=$((failures+1))
        fi
    done

    if [ $failures -eq 0 ]; then
        log_info "All symlinks verified successfully"
        return 0
    else
        log_warn "Found $failures symlink issues"
        return 1
    fi
}

# Setup all persistence
setup_persistence() {
    create_model_symlinks
    create_symlinks
    verify_symlinks

    log_section "Persistence setup complete"
}
