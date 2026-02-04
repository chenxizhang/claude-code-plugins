#!/usr/bin/env bash
# ensure-jq.sh
# Ensures jq is available, downloads if necessary

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ_VERSION="1.7.1"
LOCAL_JQ="$SCRIPT_DIR/bin/jq"

# Check if jq is already available
find_jq() {
    # First check local installation
    if [ -x "$LOCAL_JQ" ]; then
        echo "$LOCAL_JQ"
        return 0
    fi

    # Then check system PATH
    if command -v jq &> /dev/null; then
        command -v jq
        return 0
    fi

    return 1
}

# Detect OS and architecture
detect_platform() {
    local os arch

    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"

    case "$os" in
        linux*)
            os="linux"
            ;;
        darwin*)
            os="macos"
            ;;
        mingw*|msys*|cygwin*)
            os="windows"
            ;;
        *)
            echo "unsupported"
            return 1
            ;;
    esac

    case "$arch" in
        x86_64|amd64)
            arch="amd64"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        i386|i686)
            arch="i386"
            ;;
        *)
            echo "unsupported"
            return 1
            ;;
    esac

    echo "${os}-${arch}"
}

# Get download URL for jq
get_download_url() {
    local platform="$1"
    local base_url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}"

    case "$platform" in
        linux-amd64)
            echo "${base_url}/jq-linux-amd64"
            ;;
        linux-arm64)
            echo "${base_url}/jq-linux-arm64"
            ;;
        linux-i386)
            echo "${base_url}/jq-linux-i386"
            ;;
        macos-amd64)
            echo "${base_url}/jq-macos-amd64"
            ;;
        macos-arm64)
            echo "${base_url}/jq-macos-arm64"
            ;;
        windows-amd64)
            echo "${base_url}/jq-windows-amd64.exe"
            ;;
        windows-i386)
            echo "${base_url}/jq-windows-i386.exe"
            ;;
        *)
            return 1
            ;;
    esac
}

# Download jq
download_jq() {
    local url="$1"
    local output="$2"

    mkdir -p "$(dirname "$output")"

    # Try curl first, then wget
    if command -v curl &> /dev/null; then
        curl -fsSL "$url" -o "$output"
    elif command -v wget &> /dev/null; then
        wget -q "$url" -O "$output"
    else
        echo "Error: Neither curl nor wget found. Cannot download jq." >&2
        return 1
    fi

    chmod +x "$output"
}

# Main logic
main() {
    # Check if jq exists
    if JQ_PATH=$(find_jq); then
        echo "$JQ_PATH"
        return 0
    fi

    # Need to download jq
    local platform
    platform=$(detect_platform)

    if [ "$platform" = "unsupported" ]; then
        echo "Error: Unsupported platform. Please install jq manually." >&2
        return 1
    fi

    local url
    url=$(get_download_url "$platform")

    if [ -z "$url" ]; then
        echo "Error: Could not determine download URL for jq." >&2
        return 1
    fi

    # Determine output filename
    local output_file="$LOCAL_JQ"
    if [[ "$platform" == windows-* ]]; then
        output_file="${LOCAL_JQ}.exe"
    fi

    echo "Downloading jq for $platform..." >&2

    if download_jq "$url" "$output_file"; then
        echo "jq installed successfully to $output_file" >&2
        echo "$output_file"
        return 0
    else
        echo "Error: Failed to download jq." >&2
        return 1
    fi
}

main "$@"
