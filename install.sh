#!/bin/sh
# Installer script for almd on Linux/macOS
# Fetches and installs almd from GitHub Releases
# Requires: curl or wget, unzip, (jq optional for best experience)
set -e

REPO="nightconcept/almandine"
ASSET="almd-release.zip"
APP_HOME="$HOME/.almd"
WRAPPER_DIR="$HOME/.local/bin"
TMP_DIR="$(mktemp -d)"
VERSION=""

# Usage: install.sh [version]
if [ $# -gt 0 ]; then
  VERSION="$1"
fi

# Helper: download file (curl or wget)
download() {
  url="$1"
  dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -L --fail --retry 3 -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$dest" "$url"
  else
    printf '%s\n' "Error: Neither curl nor wget found. Please install one and re-run." >&2
    exit 1
  fi
}

# Helper: fetch release API JSON
github_api() {
  url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -sL "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$url"
  else
    printf '%s\n' "Error: Neither curl nor wget found. Please install one and re-run." >&2
    exit 1
  fi
}

# Determine release download URL
if [ -n "$VERSION" ]; then
  API_URL="https://api.github.com/repos/$REPO/releases/tags/$VERSION"
else
  API_URL="https://api.github.com/repos/$REPO/releases/latest"
fi

printf '%s\n' "Fetching release info ..."
RELEASE_JSON="$(github_api "$API_URL")"

if command -v jq >/dev/null 2>&1; then
  ZIP_URL="$(printf '%s' "$RELEASE_JSON" | jq -r '.assets[] | select(.name == "$ASSET") | .browser_download_url')"
else
  ZIP_URL="$(printf '%s' "$RELEASE_JSON" | grep 'browser_download_url' | grep "$ASSET" | head -n1 | sed -E 's/.*"(https:[^"]+)".*/\1/')"
fi

if [ -z "$ZIP_URL" ] || [ "$ZIP_URL" = "null" ]; then
  printf '%s\n' "Error: Could not find $ASSET in release. Check version or release status." >&2
  exit 1
fi

printf '%s\n' "Downloading $ASSET ..."
download "$ZIP_URL" "$TMP_DIR/$ASSET"

printf '%s\n' "Extracting CLI ..."
unzip -q -o "$TMP_DIR/$ASSET" -d "$TMP_DIR"

printf '%s\n' "Installing CLI to $APP_HOME ..."
mkdir -p "$APP_HOME"
cp -r "$TMP_DIR/release/src" "$APP_HOME/"

printf '%s\n' "Installing wrapper script to $WRAPPER_DIR ..."
mkdir -p "$WRAPPER_DIR"
cp "$TMP_DIR/release/install/almd.sh" "$WRAPPER_DIR/almd"
chmod +x "$WRAPPER_DIR/almd"

printf '\nInstallation complete!\n'
printf 'Make sure %s is in your PATH. You may need to restart your shell.\n' "$WRAPPER_DIR"

rm -rf "$TMP_DIR"
