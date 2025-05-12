#!/bin/sh
# Installer script for almd on Linux/macOS
# Fetches and installs almd from GitHub Releases, or locally with --local
# Requires: curl or wget, unzip, (jq optional for best experience)
set -e

REPO="nightconcept/almandine"
APP_HOME="$HOME/.almd"
PRIMARY_WRAPPER_DIR="/usr/local/bin"
FALLBACK_WRAPPER_DIR="$HOME/.local/bin"
WRAPPER_DIR=""
TMP_DIR="$(mktemp -d)"
VERSION=""
LOCAL_MODE=0

# Determine install location: /usr/local/bin (preferred), $HOME/.local/bin (fallback)
if [ -w "$PRIMARY_WRAPPER_DIR" ]; then
  WRAPPER_DIR="$PRIMARY_WRAPPER_DIR"
else
  WRAPPER_DIR="$FALLBACK_WRAPPER_DIR"
fi

# Usage: install.sh [--local] [version]
while [ $# -gt 0 ]; do
  case "$1" in
    --local)
      LOCAL_MODE=1
      ;;
    *)
      VERSION="$1"
      ;;
  esac
  shift
done

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

if [ "$LOCAL_MODE" -eq 1 ]; then
  printf '%s\n' "[DEV] Installing local almd binary..."
  mkdir -p "$APP_HOME" # Keep for potential app config/data

  # Ensure WRAPPER_DIR exists and copy the local binary 'almd' to it
  mkdir -p "$WRAPPER_DIR"
  cp ./build/almd "$WRAPPER_DIR/almd" # Use the 'almd' binary from the project root
  chmod +x "$WRAPPER_DIR/almd"

  printf '\n[DEV] Local almd binary installation complete!\n'
  printf 'Make sure %s is in your PATH. You may need to restart your shell.\n' "$WRAPPER_DIR"
  exit 0
fi

# --- Determine OS and Architecture ---
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64 | amd64) ARCH="amd64" ;;
  arm64 | aarch64) ARCH="arm64" ;;
  *)
    printf "Error: Unsupported architecture: %s\n" "$ARCH" >&2
    exit 1
    ;;
esac
case "$OS" in
  linux) OS_NAME="linux" ;;
  darwin) OS_NAME="darwin" ;; # macOS
  *)
    printf "Error: Unsupported operating system: %s\n" "$OS" >&2
    exit 1
    ;;
esac

# --- Determine Tag to Install ---
if [ -z "$VERSION" ]; then
  printf '%s\n' "Fetching latest release tag ..."
  # Get the latest *release* tag, not just the latest tag
  RELEASE_API_URL="https://api.github.com/repos/$REPO/releases/latest"
  if command -v jq >/dev/null 2>&1; then
    TAG=$(curl -sL "$RELEASE_API_URL" | jq -r '.tag_name')
  else
    # Fallback using grep/sed (less robust)
    TAG=$(curl -sL "$RELEASE_API_URL" | grep '"tag_name":' | head -n1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
  fi
  if [ -z "$TAG" ] || [ "$TAG" = "null" ]; then
    printf '%s\n' "Error: Could not determine latest release tag from GitHub." >&2
    exit 1
  fi
  printf "Latest release tag: %s\n" "$TAG"
else
  TAG="$VERSION"
  printf "Using specified tag: %s\n" "$TAG"
  RELEASE_API_URL="https://api.github.com/repos/$REPO/releases/tags/$TAG"
fi

# --- Find Asset Download URL ---
TAG_NO_V=$(echo "$TAG" | sed 's/^v//') # Remove leading 'v' for asset name
ASSET_NAME="almd_${TAG_NO_V}_${OS_NAME}_${ARCH}.tar.gz" # Correct asset name format
printf "Searching for asset: %s\n" "$ASSET_NAME"

if command -v jq >/dev/null 2>&1; then
  ASSET_URL=$(curl -sL "$RELEASE_API_URL" | jq -r --arg NAME "$ASSET_NAME" '.assets[] | select(.name == $NAME) | .browser_download_url')
else
  # Fallback using grep/sed (even less robust)
  ASSET_URL=$(curl -sL "$RELEASE_API_URL" | grep -C 5 "\"name\": *\"$ASSET_NAME\"" | grep '"browser_download_url":' | head -n1 | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/')
fi

if [ -z "$ASSET_URL" ] || [ "$ASSET_URL" = "null" ]; then
  printf "Error: Could not find asset '%s' for tag %s.\n" "$ASSET_NAME" "$TAG" >&2
  printf "Please check the release page: https://github.com/%s/releases/tag/%s\n" "$REPO" "$TAG" >&2
  exit 1
fi

# --- Download and Extract Binary ---
ASSET_DEST="$TMP_DIR/$ASSET_NAME"
printf "Downloading asset from %s ...\n" "$ASSET_URL"
download "$ASSET_URL" "$ASSET_DEST"

printf "Extracting binary from %s ...\n" "$ASSET_NAME"
tar -xzf "$ASSET_DEST" -C "$TMP_DIR"
# Verify extraction (optional but good practice)
if [ ! -f "$TMP_DIR/almd" ]; then
    printf "Error: Failed to extract 'almd' binary from %s\n" "$ASSET_NAME" >&2
    ls -l "$TMP_DIR" >&2 # List contents for debugging
    exit 1
fi

# --- Install Binary ---
printf "Installing CLI to %s ...\n" "$WRAPPER_DIR"
mkdir -p "$WRAPPER_DIR"
cp "$TMP_DIR/almd" "$WRAPPER_DIR/almd" # Copy the extracted binary
chmod +x "$WRAPPER_DIR/almd"

# Keep APP_HOME creation for potential future config/data storage
mkdir -p "$APP_HOME"

printf '\nInstallation complete!\n'
printf 'Make sure %s is in your PATH. You may need to restart your shell.\n' "$WRAPPER_DIR"

# Check if $WRAPPER_DIR is in PATH, recommend adding if missing
case ":$PATH:" in
  *:"$WRAPPER_DIR":*)
    # Already in PATH, nothing to do
    ;;
  *)
    printf '\n[INFO] %s is not in your PATH.\n' "$WRAPPER_DIR"
    if [ "$WRAPPER_DIR" = "$PRIMARY_WRAPPER_DIR" ]; then
      printf 'You may want to add it to your PATH or check your shell configuration.\n'
    else
      printf "To add it, run (for bash):\n  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc\n"
      printf "Or for zsh:\n  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc\n"
      printf "Then restart your terminal or run 'exec %s' to reload your PATH.\n" "$SHELL"
    fi
    ;;
esac

rm -rf "$TMP_DIR"
