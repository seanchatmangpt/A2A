#!/bin/bash
set -euo pipefail

echo "==> Setting up A2A development environment..."

# Install system dependencies
echo "→ Installing system packages..."
sudo apt-get update
sudo apt-get install -y \
  curl \
  git \
  jq \
  unzip

# Install Protocol Buffers compiler
echo "→ Installing protoc..."
PROTOC_VERSION="28.3"
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
  PROTOC_ZIP="protoc-${PROTOC_VERSION}-linux-aarch_64.zip"
else
  PROTOC_ZIP="protoc-${PROTOC_VERSION}-linux-x86_64.zip"
fi
curl -fsSL -o /tmp/protoc.zip "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/${PROTOC_ZIP}" || {
  echo "Warning: Failed to download protoc ${PROTOC_VERSION}, trying apt install..."
  sudo apt-get install -y protobuf-compiler || echo "Warning: protoc installation failed"
}
if [ -f /tmp/protoc.zip ]; then
  sudo unzip -q /tmp/protoc.zip -d /usr/local
  rm /tmp/protoc.zip
fi

# Install protoc-gen-jsonschema (bufbuild)
echo "→ Installing protoc-gen-jsonschema..."
if command -v go >/dev/null 2>&1; then
  go install github.com/bufbuild/protoschema-plugins/cmd/protoc-gen-jsonschema@latest
  go_bin_path="$(go env GOPATH)/bin/protoc-gen-jsonschema"
  if [ -f "$go_bin_path" ]; then
    sudo cp "$go_bin_path" /usr/local/bin/
  fi
else
  echo "Warning: Go not installed, skipping protoc-gen-jsonschema"
fi

# Install buf CLI
echo "→ Installing buf..."
if command -v go >/dev/null 2>&1; then
  go install github.com/bufbuild/buf/cmd/buf@latest
  go_bin_path="$(go env GOPATH)/bin/buf"
  if [ -f "$go_bin_path" ]; then
    sudo cp "$go_bin_path" /usr/local/bin/
  fi
else
  echo "Warning: Go not installed, skipping buf CLI"
fi

# Install googleapis proto files to third_party
echo "→ Installing googleapis..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
GOOGLEAPIS_DIR="$WORKSPACE_DIR/third_party/googleapis"
if [ ! -d "$GOOGLEAPIS_DIR" ]; then
  mkdir -p "$WORKSPACE_DIR/third_party"
  cd "$WORKSPACE_DIR/third_party"
  git clone --depth 1 https://github.com/googleapis/googleapis.git
  cd "$WORKSPACE_DIR"
fi

# Install Python dependencies for documentation
echo "→ Installing Python packages..."
if [ -f "requirements-docs.txt" ]; then
  # Try pip3 with break-system-packages flag for newer Ubuntu/Debian (PEP 668)
  pip3 install --no-cache-dir --break-system-packages -r requirements-docs.txt 2>/dev/null || \
  # Fallback to regular pip3
  pip3 install --no-cache-dir -r requirements-docs.txt 2>/dev/null || \
  # Fallback to pip
  pip install --no-cache-dir -r requirements-docs.txt 2>/dev/null || \
  echo "Warning: Some Python packages failed to install (may need --break-system-packages or virtualenv)"
else
  echo "Warning: requirements-docs.txt not found, skipping Python package installation"
fi

# Verify installations
echo ""
echo "==> Verifying installations..."
echo "protoc: $(protoc --version)"
echo "protoc-gen-jsonschema: $(which protoc-gen-jsonschema || echo 'not found')"
echo "buf: $(buf --version 2>/dev/null || echo 'not found')"
echo "jq: $(jq --version)"
echo "python: $(python3 --version 2>/dev/null || python --version 2>/dev/null || echo 'not found')"
if command -v go >/dev/null 2>&1; then
  echo "go: $(go version)"
else
  echo "go: not found (will be installed via devcontainer features)"
fi

echo ""
echo "✓ Development environment ready!"
echo ""
echo "To build documentation:"
echo "  ./scripts/build_docs.sh"
echo ""
echo "To convert proto to JSON Schema:"
echo "  ./scripts/proto_to_json_schema.sh specification/json/a2a.json"
