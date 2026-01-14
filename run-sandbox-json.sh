#!/bin/bash
# Isolated JavaScript Sandbox with JSON I/O for MCP integration
# Usage: echo '{"code": "...", "timeout": 30}' | ./run-sandbox-json.sh
#
# Input (JSON on stdin):
#   code      - JavaScript code to execute (required)
#   timeout   - Execution timeout in seconds (default: 30)
#   memory    - Memory limit in KB (default: 512000)
#   network   - Enable network access (default: false)
#
# Output (JSON on stdout):
#   success   - Boolean indicating success
#   output    - stdout from the script
#   error     - stderr or error message (if any)
#   exit_code - Process exit code
#   stats     - Execution statistics (time, memory)
#
# The script also loads .env file if present for:
#   STRIPE_API_KEY - Your Stripe API key
#
# When network is enabled, the devbox egress proxy is configured
# automatically via HTTP_PROXY and HTTPS_PROXY environment variables.

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

# Read JSON input from stdin
INPUT=$(cat)

# Parse JSON input using node
read -r CODE TIMEOUT MEMORY NETWORK < <($NODE_BIN -e "
const input = JSON.parse(process.argv[1]);
const code = (input.code || '').replace(/'/g, \"'\\\\''\");
const timeout = input.timeout || 30;
const memory = input.memory || 512000;
const network = input.network ? '1' : '0';
console.log([code, timeout, memory, network].join(' '));
" "$INPUT" 2>/dev/null || echo "'' 30 512000 0")

# Validate we have code
if [ -z "$CODE" ] || [ "$CODE" = "''" ]; then
    echo '{"success": false, "error": "No code provided", "output": "", "exit_code": 1, "stats": {}}'
    exit 0
fi

# Cleanup any existing sandbox
sudo isolate --box-id="$BOX_ID" --cleanup 2>/dev/null || true

# Initialize sandbox
BOX_DIR=$(sudo isolate --box-id="$BOX_ID" --init 2>/dev/null)
if [ -z "$BOX_DIR" ]; then
    echo '{"success": false, "error": "Failed to initialize sandbox", "output": "", "exit_code": 1, "stats": {}}'
    exit 0
fi

BOX_WORK="$BOX_DIR/box"

# Cleanup on exit
cleanup() {
    sudo isolate --box-id="$BOX_ID" --cleanup 2>/dev/null || true
}
trap cleanup EXIT

# Copy node_modules into sandbox
sudo cp -r "$SCRIPT_DIR/node_modules" "$BOX_WORK/" 2>/dev/null

# Write the code to script file
echo "$CODE" | sudo tee "$BOX_WORK/script.js" > /dev/null

# Create metadata file for output
META_FILE=$(mktemp)

# Build isolate options
ISOLATE_OPTS=(
    --box-id="$BOX_ID"
    --run
    --processes
    --dir=/etc
    --env=NODE_PATH=/box/node_modules
    --env=HOME=/box
    --time="$TIMEOUT"
    --wall-time="$((TIMEOUT * 2))"
    --mem="$MEMORY"
    --chdir=/box
    --meta="$META_FILE"
)

# Add STRIPE_API_KEY if set
if [ -n "$STRIPE_API_KEY" ]; then
    ISOLATE_OPTS+=(--env=STRIPE_API_KEY="$STRIPE_API_KEY")
fi

# Add network if requested
if [ "$NETWORK" = "1" ]; then
    ISOLATE_OPTS+=(--share-net)
    # Configure devbox egress proxy for internet access
    ISOLATE_OPTS+=(--env=HTTP_PROXY=http://trusted-egress-proxy.service.envoy:10072)
    ISOLATE_OPTS+=(--env=HTTPS_PROXY=http://trusted-egress-proxy.service.envoy:10072)
    ISOLATE_OPTS+=(--env=NO_PROXY=localhost,127.0.0.1)
fi

# Capture stdout and stderr separately
STDOUT_FILE=$(mktemp)
STDERR_FILE=$(mktemp)

# Run the script
set +e
sudo isolate "${ISOLATE_OPTS[@]}" -- "$NODE_BIN" /box/script.js > "$STDOUT_FILE" 2> "$STDERR_FILE"
EXIT_CODE=$?
set -e

# Read outputs
STDOUT_CONTENT=$(cat "$STDOUT_FILE" | head -c 100000)
STDERR_CONTENT=$(cat "$STDERR_FILE" | head -c 10000)

# Parse metadata
TIME_REAL=$(grep "^time:" "$META_FILE" 2>/dev/null | cut -d: -f2 || echo "0")
TIME_WALL=$(grep "^time-wall:" "$META_FILE" 2>/dev/null | cut -d: -f2 || echo "0")
MAX_RSS=$(grep "^max-rss:" "$META_FILE" 2>/dev/null | cut -d: -f2 || echo "0")
STATUS=$(grep "^status:" "$META_FILE" 2>/dev/null | cut -d: -f2 || echo "")

# Cleanup temp files
rm -f "$STDOUT_FILE" "$STDERR_FILE" "$META_FILE"

# Determine success
SUCCESS="true"
if [ $EXIT_CODE -ne 0 ]; then
    SUCCESS="false"
fi

# Output JSON result using node for proper escaping
$NODE_BIN -e "
const result = {
    success: $SUCCESS,
    output: process.argv[1],
    error: process.argv[2],
    exit_code: $EXIT_CODE,
    stats: {
        time_cpu: parseFloat('$TIME_REAL') || 0,
        time_wall: parseFloat('$TIME_WALL') || 0,
        memory_kb: parseInt('$MAX_RSS') || 0,
        status: '$STATUS'
    }
};
console.log(JSON.stringify(result));
" "$STDOUT_CONTENT" "$STDERR_CONTENT"
