#!/bin/bash

echo "================================================"
echo " Zenbook Duo Auto-Wallpaper Switcher - Installer"
echo "================================================"
echo ""

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
WALL_SCRIPT="auto-wallpaper.sh"
WALL_PATH="$SCRIPT_DIR/$WALL_SCRIPT"
SERVICE_FILE="$SCRIPT_DIR/zenbook-wallpaper.service"
CONFIG_DIR="${HOME}/.config/zenbook-wallpaper"
CONFIG_FILE="$CONFIG_DIR/config"

if [ ! -f "$WALL_PATH" ]; then
    echo "Error: Could not find $WALL_SCRIPT in $SCRIPT_DIR."
    exit 1
fi

# --- Install ImageMagick ---
if ! command -v magick &>/dev/null; then
    echo "Installing ImageMagick..."
    sudo dnf install -y ImageMagick
else
    echo "ImageMagick already installed. Skipping."
fi

# --- Create wallpaper directories ---
echo "Creating wallpaper directories..."
WALLPAPER_DIR="${HOME}/Pictures/ZenbookWallpapers"
mkdir -p "${WALLPAPER_DIR}/"{Laptop,Dual,Desktop,Sharing}
echo "  Add images to subfolders in: $WALLPAPER_DIR"

# --- Write default config (only if it doesn't already exist) ---
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating default config at $CONFIG_FILE..."
    cat > "$CONFIG_FILE" << 'EOF'
# Zenbook Duo Auto-Wallpaper Switcher Configuration
# -------------------------------------------------------

# Set to false to disable the wallpaper switcher entirely
ENABLED=true

# --- Per-mode image selection ---
# Set MODE to "random" (pick from folder) or "default" (use a specific file).
# If set to "default", provide the full path to the image in MODE_DEFAULT_IMAGE.

LAPTOP_MODE=random
LAPTOP_DEFAULT_IMAGE=

DUAL_MODE=random
DUAL_DEFAULT_IMAGE=

DESKTOP_MODE=random
DESKTOP_DEFAULT_IMAGE=

SHARING_MODE=random
SHARING_DEFAULT_IMAGE=
EOF
else
    echo "Config already exists at $CONFIG_FILE — skipping (your settings are preserved)."
fi

# --- Install script permissions ---
echo "Setting permissions..."
chmod +x "$WALL_PATH"

# --- Install systemd user service ---
echo "Installing systemd user service..."
mkdir -p "${HOME}/.config/systemd/user/"
cp "$SERVICE_FILE" "${HOME}/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now zenbook-wallpaper.service

echo ""
echo "Installation Success! 🎉"
echo ""
echo "Wallpaper directories: $WALLPAPER_DIR"
echo "  Laptop/   — wallpapers for single-screen laptop mode"
echo "  Dual/     — wallpapers for dual-screen stacked mode"
echo "  Desktop/  — wallpapers for rotated desktop mode"
echo "  Sharing/  — wallpapers for sharing/tent mode"
echo ""
echo "Config file: $CONFIG_FILE"
echo "  Edit this file to disable the switcher or pin a default image per mode."
echo ""
echo "To disable:  systemctl --user stop zenbook-wallpaper.service"
echo "To re-enable: systemctl --user start zenbook-wallpaper.service"
