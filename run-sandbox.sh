#!/bin/bash
# Isolated JavaScript Sandbox using isolate
# Usage: ./run-sandbox.sh <javascript-file-or-inline-code>
#
# Environment variables:
#   BOX_ID      - Sandbox ID (default: 0, use different IDs for parallel execution)
#   TIME_LIMIT  - CPU time limit in seconds (default: 30)
#   WALL_TIME   - Wall clock time limit in seconds (default: 60)
#   MEM_LIMIT   - Memory limit in KB (default: 512000 = 512MB)
#   SHARE_NET   - Set to "1" to enable network access
#
# The script also loads .env file if present for:
#   STRIPE_API_KEY - Your Stripe API key
#
# When network is enabled (SHARE_NET=1), the devbox egress proxy is configured
# automatically via HTTP_PROXY and HTTPS_PROXY environment variables.
#
# Examples:
#   ./run-sandbox.sh example.js                    # Run a file
#   ./run-sandbox.sh 'console.log("hello")'        # Run inline code
#   SHARE_NET=1 ./run-sandbox.sh script.js         # Run with network
#   BOX_ID=1 ./run-sandbox.sh script.js            # Use different sandbox

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env file if it exists
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi
NODE_BIN="/usr/stripe/nodenv/nodenv-1.1.2/versions/18.14.0/bin/node"
BOX_ID="${BOX_ID:-0}"

# Resource limits
TIME_LIMIT="${TIME_LIMIT:-30}"
WALL_TIME="${WALL_TIME:-60}"
MEM_LIMIT="${MEM_LIMIT:-512000}"

# Cleanup any existing sandbox
sudo isolate --box-id="$BOX_ID" --cleanup 2>/dev/null || true

# Initialize sandbox
BOX_DIR=$(sudo isolate --box-id="$BOX_ID" --init)
if [ -z "$BOX_DIR" ]; then
    echo "Error: Failed to initialize sandbox" >&2
    exit 1
fi

BOX_WORK="$BOX_DIR/box"

# Cleanup on exit
cleanup() {
    sudo isolate --box-id="$BOX_ID" --cleanup 2>/dev/null || true
}
trap cleanup EXIT

# Copy node_modules into sandbox
sudo cp -r "$SCRIPT_DIR/node_modules" "$BOX_WORK/"

# Handle input - either a file path or inline code
if [ -f "$1" ]; then
    sudo cp "$1" "$BOX_WORK/script.js"
elif [ -n "$1" ]; then
    echo "$1" | sudo tee "$BOX_WORK/script.js" > /dev/null
else
    echo "Usage: $0 <javascript-file-or-inline-code>" >&2
    exit 1
fi

# Build isolate options
ISOLATE_OPTS=(
    --box-id="$BOX_ID"
    --run
    --processes
    --dir=/etc
    --env=NODE_PATH=/box/node_modules
    --env=HOME=/box
    --time="$TIME_LIMIT"
    --wall-time="$WALL_TIME"
    --mem="$MEM_LIMIT"
    --chdir=/box
)

# Add STRIPE_API_KEY if set
if [ -n "$STRIPE_API_KEY" ]; then
    ISOLATE_OPTS+=(--env=STRIPE_API_KEY="$STRIPE_API_KEY")
fi

# Add network if requested
if [ "$SHARE_NET" = "1" ]; then
    ISOLATE_OPTS+=(--share-net)
    # Configure devbox egress proxy for internet access
    ISOLATE_OPTS+=(--env=HTTP_PROXY=http://trusted-egress-proxy.service.envoy:10072)
    ISOLATE_OPTS+=(--env=HTTPS_PROXY=http://trusted-egress-proxy.service.envoy:10072)
    ISOLATE_OPTS+=(--env=NO_PROXY=localhost,127.0.0.1)
fi

# Run the script
sudo isolate "${ISOLATE_OPTS[@]}" -- "$NODE_BIN" /box/script.js
