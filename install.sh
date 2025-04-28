#!/bin/sh
# Installer script for almd on Linux/macOS
# Copies src/ to $HOME/.almd and wrapper to $HOME/.local/bin
set -e

APP_HOME="$HOME/.almd"
WRAPPER_DIR="$HOME/.local/bin"

printf '%s\n' "Installing almd to $APP_HOME ..."
mkdir -p "$APP_HOME"
cp -r src "$APP_HOME/"

printf '%s\n' "Installing wrapper script to $WRAPPER_DIR ..."
mkdir -p "$WRAPPER_DIR"
cp install/almd.sh "$WRAPPER_DIR/almd"
chmod +x "$WRAPPER_DIR/almd"

printf '\nInstallation complete!\n'
printf 'Make sure %s is in your PATH. You may need to restart your shell.\n' "$WRAPPER_DIR"
