#!/bin/bash

echo "=========================================="
echo " ASUS Zenbook Duo (2025) Touch Toggle Setup"
echo "=========================================="
echo ""

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
SCRIPT_NAME="toggle-lower-touch.sh"
SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Error: Could not find $SCRIPT_NAME in $SCRIPT_DIR."
    exit 1
fi

echo "Setting execution permissions..."
chmod +x "$SCRIPT_PATH"

echo "Configuring passwordless execution for GNOME shortcuts..."
echo "This requires sudo privileges to create a file in /etc/sudoers.d/"

SUDOERS_FILE="/etc/sudoers.d/touch-toggle"
RULE="$USER ALL=(root) NOPASSWD: $SCRIPT_PATH"

echo "$RULE" | sudo tee "$SUDOERS_FILE" > /dev/null
sudo chmod 0440 "$SUDOERS_FILE"

echo ""
echo "Installation Success! 🎉"
echo "You can now bind a GNOME Custom Shortcut to:"
echo "sudo \"$SCRIPT_PATH\""
echo ""
echo "To also install the Auto-Wallpaper Switcher, run:"
echo "  bash \"$SCRIPT_DIR/install-wallpaper.sh\""
