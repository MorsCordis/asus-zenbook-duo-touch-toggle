#!/bin/bash
# Auto-Wallpaper Switcher for Zenbook Duo (2025)
# Watches /tmp/duo/duo.log for orientation/mode changes and sets GNOME wallpaper.

WALLPAPER_DIR="${HOME}/Pictures/ZenbookWallpapers"
LOG_FILE="/tmp/duo/duo.log"
CONFIG_FILE="${HOME}/.config/zenbook-wallpaper/config"
LAST_MODE=""

# --- Load config ---
ENABLED=true
LAPTOP_MODE=random;   LAPTOP_DEFAULT_IMAGE=
DUAL_MODE=random;     DUAL_DEFAULT_IMAGE=
DESKTOP_MODE=random;  DESKTOP_DEFAULT_IMAGE=
SHARING_MODE=random;  SHARING_DEFAULT_IMAGE=

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

# Exit immediately if disabled
if [ "$ENABLED" != "true" ]; then
    echo "$(date) - Auto-wallpaper is disabled in config. Exiting."
    exit 0
fi

# --- Screen geometry (physical pixels) ---
# Laptop:  single screen 2880x1800
# Dual:    two screens stacked vertically  → virtual desktop 2880x3600
# Desktop: two screens side-by-side (90°) → virtual desktop 3600x2880
# Sharing: two screens stacked, top rotated 180° → 2880x3600

function apply_wallpaper() {
    local bg="$1"
    local opts="$2"
    echo "$(date) - Applying wallpaper: $bg [options=$opts]"
    # Set options first so GNOME picks them up when URI changes
    gsettings set org.gnome.desktop.background picture-options "$opts"
    gsettings set org.gnome.desktop.background picture-uri "file://$bg"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://$bg"
}

# Returns the image to use for a given mode.
# Uses MODE_DEFAULT_IMAGE if MODE=default and the file exists, otherwise random.
function pick_image() {
    local dir="$1"
    local mode_setting="$2"      # "random" or "default"
    local default_path="$3"      # path to default image (may be empty)
    local exclude="${4:-}"        # optional: exclude this file from random pick

    if [ "$mode_setting" = "default" ] && [ -n "$default_path" ] && [ -f "$default_path" ]; then
        echo "$default_path"
    else
        # Random pick from the folder
        if [ -d "$dir" ]; then
            if [ -n "$exclude" ]; then
                find "$dir" -maxdepth 1 -type f \( -iname \*.jpg -o -iname \*.png -o -iname \*.jpeg \) \
                    | grep -v "$exclude" | shuf -n 1
            else
                find "$dir" -maxdepth 1 -type f \( -iname \*.jpg -o -iname \*.png -o -iname \*.jpeg \) \
                    | shuf -n 1
            fi
        fi
    fi
}

function switch_wallpaper() {
    local mode="$1"

    # Debounce: skip if same mode was just applied
    if [ "$mode" == "$LAST_MODE" ]; then
        echo "$(date) - Already in mode $mode, skipping"
        return
    fi
    LAST_MODE="$mode"

    echo "$(date) - Switching to mode: $mode"
    local wp_dir="${WALLPAPER_DIR}/${mode}"
    mkdir -p "$wp_dir"
    local out_img="/tmp/zenbook_wallpaper_current.jpg"

    case "$mode" in

        Laptop)
            # Single screen 2880x1800 — one image, zoom to fill
            local img
            img=$(pick_image "$wp_dir" "$LAPTOP_MODE" "$LAPTOP_DEFAULT_IMAGE")
            if [ -n "$img" ]; then
                cp "$img" "$out_img"
                apply_wallpaper "$out_img" "zoom"
            else
                echo "No images in $wp_dir"
            fi
            ;;

        Dual)
            # Virtual desktop 2880x3600 (portrait) — one image spanning both screens
            local img
            img=$(pick_image "$wp_dir" "$DUAL_MODE" "$DUAL_DEFAULT_IMAGE")
            if [ -n "$img" ]; then
                magick "$img" -resize 2880x3600^ -gravity center -extent 2880x3600 "$out_img"
                apply_wallpaper "$out_img" "spanned"
            else
                echo "No images in $wp_dir"
            fi
            ;;

        Desktop)
            # Virtual desktop 3600x2880 (landscape) — one image spanning both screens
            local img
            img=$(pick_image "$wp_dir" "$DESKTOP_MODE" "$DESKTOP_DEFAULT_IMAGE")
            if [ -n "$img" ]; then
                magick "$img" -resize 3600x2880^ -gravity center -extent 3600x2880 "$out_img"
                apply_wallpaper "$out_img" "spanned"
            else
                echo "No images in $wp_dir"
            fi
            ;;

        Sharing)
            # Tent/book mode — two images, top-to-top:
            #   top screen: img1 rotated 180° (faces the person across)
            #   bottom screen: img2 normal (faces the owner)
            local img1 img2
            img1=$(pick_image "$wp_dir" "$SHARING_MODE" "$SHARING_DEFAULT_IMAGE")
            if [ -n "$img1" ]; then
                img2=$(pick_image "$wp_dir" "$SHARING_MODE" "$SHARING_DEFAULT_IMAGE" "$img1")
                [ -z "$img2" ] && img2="$img1"  # fallback: mirror same image

                magick "$img1" -resize 2880x1800^ -gravity center -extent 2880x1800 -rotate 180 /tmp/zw_share_top.jpg
                magick "$img2" -resize 2880x1800^ -gravity center -extent 2880x1800 /tmp/zw_share_bottom.jpg
                magick /tmp/zw_share_top.jpg /tmp/zw_share_bottom.jpg -append "$out_img"
                apply_wallpaper "$out_img" "spanned"
            else
                echo "No images in $wp_dir"
            fi
            ;;

        *)
            echo "Unknown mode: $mode"
            ;;
    esac
}

# ---- Startup ----
echo "Starting Zenbook Duo Auto-Wallpaper Switcher..."
mkdir -p "${WALLPAPER_DIR}/"{Laptop,Dual,Desktop,Sharing}

# Set initial wallpaper based on current state
if [ -f /tmp/duo/status ]; then
    if grep -q "KEYBOARD_ATTACHED=true" /tmp/duo/status; then
        switch_wallpaper "Laptop"
    else
        switch_wallpaper "Dual"
    fi
fi

# ---- Event loop: tail only NEW lines ----
tail -n 0 -F "$LOG_FILE" 2>/dev/null | while read -r line; do

    # Re-load config on each event so live edits take effect without restart
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    if [ "$ENABLED" != "true" ]; then
        echo "$(date) - Disabled via config, ignoring event."
        continue
    fi

    if echo "$line" | grep -q "MONITOR - Keyboard attached: true"; then
        sleep 2
        switch_wallpaper "Laptop"

    elif echo "$line" | grep -q "MONITOR - Enabled bottom display"; then
        sleep 1
        switch_wallpaper "Dual"

    elif echo "$line" | grep -qE "ROTATE - (Left|Right)-up"; then
        if grep -q "KEYBOARD_ATTACHED=false" /tmp/duo/status 2>/dev/null; then
            sleep 1
            switch_wallpaper "Desktop"
        fi

    elif echo "$line" | grep -q "ROTATE - Bottom-up"; then
        if grep -q "KEYBOARD_ATTACHED=false" /tmp/duo/status 2>/dev/null; then
            sleep 1
            switch_wallpaper "Sharing"
        fi

    elif echo "$line" | grep -q "ROTATE - Normal"; then
        if grep -q "KEYBOARD_ATTACHED=false" /tmp/duo/status 2>/dev/null; then
            sleep 1
            switch_wallpaper "Dual"
        fi
    fi
done
