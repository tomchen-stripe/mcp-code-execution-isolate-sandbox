# Installing IOI Isolate on Devbox

## Prerequisites

Install required dependencies:
```bash
sudo apt-get update
sudo apt-get install -y build-essential pkg-config libcap-dev libsystemd-dev git
```

## Installation Steps

### 1. Create project directory and clone isolate repository
```bash
# Create working directory
mkdir -p ~/stripe/ioi_sandbox
cd ~/stripe/ioi_sandbox

# Clone isolate from GitHub
git clone https://github.com/ioi/isolate.git
cd isolate
```

### 2. Build isolate from source
```bash
make
```

Note: If you get an error about `a2x` (man page generator) not being available, the binaries are still built successfully. You can ignore the error or install `asciidoc` package to build man pages.

### 3. Create config files
```bash
make default.cf systemd/isolate.service
```

### 4. Install isolate (requires sudo)
```bash
sudo make install
```

### 5. Verify installation
```bash
which isolate
isolate --version
```

## Testing Installation

```bash
git clone https://github.com/tomchen-stripe/mcp-code-execution-isolate-sandbox.git ~/stripe/ioi_sandbox/sandbox

# Go to the sandbox directory (adjust path to where you have this repo)
cd ~/stripe/ioi_sandbox/sandbox

# Run security isolation test
./run-sandbox.sh test-isolate.js

# Run Stripe API test (requires STRIPE_API_KEY in .env)
SHARE_NET=1 ./run-sandbox.sh test-stripe.js
```

Both tests should pass.