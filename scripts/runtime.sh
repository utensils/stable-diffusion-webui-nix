#!/usr/bin/env bash
# runtime.sh: Runtime functions for Stable Diffusion WebUI

# Guard against multiple sourcing
[[ -n "${_RUNTIME_SH_SOURCED:-}" ]] && return
_RUNTIME_SH_SOURCED=1

# Source shared libraries
[ -z "$SCRIPT_DIR" ] && SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
source "$SCRIPT_DIR/logger.sh"

# Check if port is already in use
check_port() {
    log_section "Checking port availability"

    if nc -z localhost "$SD_WEBUI_PORT" 2>/dev/null; then
        log_warn "Port $SD_WEBUI_PORT is in use. SD WebUI may already be running."
        display_options "1. Open browser to existing SD WebUI" "2. Try a different port" "3. Kill the process using port $SD_WEBUI_PORT"

        echo -n "Enter choice (1-3, default=1): "
        read -r choice

        case "$choice" in
            "3")
                free_port
                ;;
            "2")
                log_info "To use a different port, restart with --port option."
                exit 0
                ;;
            *)
                log_info "Opening browser to existing SD WebUI"
                open_browser "http://127.0.0.1:$SD_WEBUI_PORT"
                exit 0
                ;;
        esac
    else
        log_info "Port $SD_WEBUI_PORT is available"
    fi
}

# Free up the port by killing processes
free_port() {
    log_info "Attempting to free up port $SD_WEBUI_PORT"

    PIDS=$(lsof -t -i:"$SD_WEBUI_PORT" 2>/dev/null || netstat -anv | grep ".$SD_WEBUI_PORT " | awk '{print $9}' | sort -u)
    if [ -n "$PIDS" ]; then
        for PID in $PIDS; do
            log_info "Killing process $PID"
            kill -9 "$PID" 2>/dev/null
        done

        sleep 2
        if nc -z localhost "$SD_WEBUI_PORT" 2>/dev/null; then
            log_error "Failed to free up port $SD_WEBUI_PORT. Try a different port."
            exit 1
        else
            log_info "Successfully freed port $SD_WEBUI_PORT"
        fi
    else
        log_warn "Could not find any process using port $SD_WEBUI_PORT"
    fi
}

# Display final startup information
display_startup_info() {
    display_url_info
    display_notices
}

# Build the SD WebUI command arguments
build_sd_webui_args() {
    local args=()

    # Add port
    args+=("--port" "$SD_WEBUI_PORT")

    # Skip the internal torch check since we handle it ourselves
    args+=("--skip-torch-cuda-test")

    # Note: We don't use --skip-install because SD WebUI needs to clone
    # repositories (k-diffusion, BLIP, etc.) and install additional packages
    # like clip, open_clip on first run

    # Set data directory
    args+=("--data-dir" "$BASE_DIR")

    # Add paths to Gradio's allowed_paths to fix 403 errors when listening on network
    # This is required because Gradio applies stricter security when --listen is used
    args+=("--gradio-allowed-path" "$CODE_DIR")
    args+=("--gradio-allowed-path" "$BASE_DIR")
    args+=("--gradio-allowed-path" "$OUTPUTS_DIR")

    # Add any additional arguments passed through (ARGS is set in config.sh)
    # shellcheck disable=SC2153
    args+=("${ARGS[@]}")

    echo "${args[@]}"
}

# Start SD WebUI with browser opening if requested
start_with_browser() {
    log_section "Starting Stable Diffusion WebUI with browser"

    # Set up a trap to kill the child process when this script receives a signal
    trap 'kill "$PID" 2>/dev/null' INT TERM

    # Start SD WebUI in the background using launch.py directly
    cd "$CODE_DIR" || exit 1
    log_info "Starting SD WebUI in background..."

    # Build command arguments as an array to preserve proper argument handling
    local -a sd_webui_args=()
    sd_webui_args+=("--port" "$SD_WEBUI_PORT")
    sd_webui_args+=("--skip-torch-cuda-test")
    sd_webui_args+=("--data-dir" "$BASE_DIR")
    # Add paths to Gradio's allowed_paths - use realpath for canonical paths
    sd_webui_args+=("--gradio-allowed-path" "$(realpath "$CODE_DIR")")
    sd_webui_args+=("--gradio-allowed-path" "$(realpath "$BASE_DIR")")
    sd_webui_args+=("--gradio-allowed-path" "$(realpath "$OUTPUTS_DIR")")
    # Add any user-provided arguments
    sd_webui_args+=("${ARGS[@]}")

    log_debug "Launch args: ${sd_webui_args[*]}"

    # Ensure library paths are preserved for the Python subprocess
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}" "$SD_WEBUI_VENV/bin/python" "$CODE_DIR/launch.py" "${sd_webui_args[@]}" &
    else
        "$SD_WEBUI_VENV/bin/python" "$CODE_DIR/launch.py" "${sd_webui_args[@]}" &
    fi
    PID=$!

    # Wait for server to start
    log_info "Waiting for SD WebUI to start..."
    until nc -z localhost "$SD_WEBUI_PORT" 2>/dev/null; do
        sleep 1
        # Check if process is still running
        if ! kill -0 "$PID" 2>/dev/null; then
            log_error "SD WebUI process exited unexpectedly"
            exit 1
        fi
    done

    log_info "SD WebUI started! Opening browser..."
    open_browser "http://127.0.0.1:$SD_WEBUI_PORT"

    # Wait for the process to finish
    while kill -0 "$PID" 2>/dev/null; do
        wait "$PID" 2>/dev/null || break
    done

    # Make sure to clean up any remaining process
    kill "$PID" 2>/dev/null || true
    log_info "SD WebUI has shut down"
    exit 0
}

# Start SD WebUI normally without browser opening
start_normal() {
    log_section "Starting Stable Diffusion WebUI"

    cd "$CODE_DIR" || exit 1
    log_info "Starting SD WebUI... Press Ctrl+C to exit"

    # Build command arguments as an array to preserve proper argument handling
    local -a sd_webui_args=()
    sd_webui_args+=("--port" "$SD_WEBUI_PORT")
    sd_webui_args+=("--skip-torch-cuda-test")
    sd_webui_args+=("--data-dir" "$BASE_DIR")
    # Add paths to Gradio's allowed_paths - use realpath for canonical paths
    sd_webui_args+=("--gradio-allowed-path" "$(realpath "$CODE_DIR")")
    sd_webui_args+=("--gradio-allowed-path" "$(realpath "$BASE_DIR")")
    sd_webui_args+=("--gradio-allowed-path" "$(realpath "$OUTPUTS_DIR")")
    # Add any user-provided arguments
    sd_webui_args+=("${ARGS[@]}")

    log_debug "Launch args: ${sd_webui_args[*]}"

    # Ensure library paths are preserved for the Python subprocess
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}" exec "$SD_WEBUI_VENV/bin/python" "$CODE_DIR/launch.py" "${sd_webui_args[@]}"
    else
        exec "$SD_WEBUI_VENV/bin/python" "$CODE_DIR/launch.py" "${sd_webui_args[@]}"
    fi
}

# Start SD WebUI with appropriate mode
start_sd_webui() {
    check_port
    display_startup_info

    if [ "$OPEN_BROWSER" = true ]; then
        start_with_browser
    else
        start_normal
    fi
}
