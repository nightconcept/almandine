#!/bin/sh
# Installer script for almd on Linux/macOS
# Fetches and installs almd from GitHub Releases, or locally with -local
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
  printf '%s\n' "[DEV] Installing from local repository ..."
  mkdir -p "$APP_HOME"
  cp -r ./src "$APP_HOME/"
  mkdir -p "$WRAPPER_DIR"
  cp ./install/almd "$WRAPPER_DIR/almd"
  chmod +x "$WRAPPER_DIR/almd"
  printf '\n[DEV] Local installation complete!\n'
  printf 'Make sure %s is in your PATH. You may need to restart your shell.\n' "$WRAPPER_DIR"
  exit 0
fi

# Determine tag to install
if [ -n "$VERSION" ]; then
  TAG="$VERSION"
else
  printf '%s\n' "Fetching latest tag ..."
  TAG=$(curl -sL "https://api.github.com/repos/$REPO/tags?per_page=1" | \
    grep '"name"' | head -n1 | sed -E 's/ *\"name\": *\"([^\"]+)\".*/\1/')
  if [ -z "$TAG" ]; then
    printf '%s\n' "Error: Could not determine latest tag from GitHub." >&2
    exit 1
  fi
fi

ARCHIVE_URL="https://github.com/$REPO/archive/refs/tags/$TAG.zip"
ARCHIVE_NAME="$(echo "$REPO-$TAG.zip" | tr '/' '-')"

printf '%s\n' "Downloading archive for tag $TAG ..."
download "$ARCHIVE_URL" "$TMP_DIR/$ARCHIVE_NAME"

printf '%s\n' "Extracting CLI ..."
unzip -q -o "$TMP_DIR/$ARCHIVE_NAME" -d "$TMP_DIR"

# Find extracted folder (name format: almandine-<tag> or almandine-v<tag>)
EXTRACTED_DIR="$TMP_DIR/almandine-$TAG"
if [ ! -d "$EXTRACTED_DIR" ]; then
  EXTRACTED_DIR="$TMP_DIR/almandine-v$TAG"
  if [ ! -d "$EXTRACTED_DIR" ]; then
    printf '%s\n' "Error: Could not find extracted directory for tag $TAG." >&2
    exit 1
  fi
fi

printf '%s\n' "Installing CLI to $APP_HOME ..."
mkdir -p "$APP_HOME"
cp -r "$EXTRACTED_DIR/src" "$APP_HOME/"

printf '%s\n' "Installing wrapper script to $WRAPPER_DIR ..."
mkdir -p "$WRAPPER_DIR"
cp "$EXTRACTED_DIR/install/almd" "$WRAPPER_DIR/almd"
chmod +x "$WRAPPER_DIR/almd"

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
      printf 'To add it, run (for bash):\n  echo ''export PATH="$HOME/.local/bin:$PATH"'' >> ~/.bashrc && source ~/.bashrc\n'
      printf 'Or for zsh:\n  echo ''export PATH="$HOME/.local/bin:$PATH"'' >> ~/.zshrc && source ~/.zshrc\n'
      printf 'Then restart your terminal or run ''exec $SHELL'' to reload your PATH.\n'
    fi
    ;;
esac

rm -rf "$TMP_DIR"
