#!/usr/bin/env bash
# Downloads the latest pandoc binary for Linux and macOS, placing it at:
#   flutter_app/pandoc/linux/pandoc    (Linux)
#   flutter_app/pandoc/macos/pandoc    (macOS)
#
# Usage:
#   ./scripts/download_pandoc.sh          # auto-detect OS, latest version
#   ./scripts/download_pandoc.sh 3.6.4    # specific version

set -euo pipefail

VERSION="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect OS
if [[ "$(uname)" == "Darwin" ]]; then
    PLATFORM="macos"
else
    PLATFORM="linux"
fi

OUT_DIR="$SCRIPT_DIR/../pandoc/$PLATFORM"
OUT_FILE="$OUT_DIR/pandoc"

if [[ -f "$OUT_FILE" ]]; then
    echo "pandoc already present at $OUT_FILE — skipping download."
    exit 0
fi

# Resolve version
if [[ -z "$VERSION" ]]; then
    echo "Fetching latest pandoc release version..."
    VERSION=$(curl -fsSL "https://api.github.com/repos/jgm/pandoc/releases/latest" \
        | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": "\(.*\)".*/\1/')
fi

echo "Downloading pandoc $VERSION for $PLATFORM..."

ARCH="$(uname -m)"
if [[ "$PLATFORM" == "macos" ]]; then
    # macOS: try arm64 first, fall back to x86_64
    if [[ "$ARCH" == "arm64" ]]; then
        FILE="pandoc-${VERSION}-arm64-macOS.zip"
    else
        FILE="pandoc-${VERSION}-x86_64-macOS.zip"
    fi
else
    FILE="pandoc-${VERSION}-linux-amd64.tar.gz"
fi

URL="https://github.com/jgm/pandoc/releases/download/${VERSION}/${FILE}"
TMP_DIR="$(mktemp -d)"

curl -fsSL "$URL" -o "$TMP_DIR/$FILE"

if [[ "$FILE" == *.zip ]]; then
    unzip -q "$TMP_DIR/$FILE" -d "$TMP_DIR/extracted"
else
    tar xf "$TMP_DIR/$FILE" -C "$TMP_DIR/extracted" --strip-components=0 2>/dev/null || \
    tar xf "$TMP_DIR/$FILE" -C "$TMP_DIR/extracted"
fi

PANDOC_BIN=$(find "$TMP_DIR/extracted" -name "pandoc" -type f | grep "bin/pandoc" | head -1)
if [[ -z "$PANDOC_BIN" ]]; then
    PANDOC_BIN=$(find "$TMP_DIR/extracted" -name "pandoc" -type f | head -1)
fi

if [[ -z "$PANDOC_BIN" ]]; then
    echo "ERROR: pandoc binary not found in downloaded archive." >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
cp "$PANDOC_BIN" "$OUT_FILE"
chmod +x "$OUT_FILE"
rm -rf "$TMP_DIR"

echo "pandoc $VERSION installed to $OUT_FILE"
