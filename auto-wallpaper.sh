#!/bin/bash
# Auto-Wallpaper Switcher for Zenbook Duo (2025)
# Watches the Rust daemon's state.json for keyboard and orientation changes,
# then applies the appropriate wallpaper mode.
#
# Compatible with zenbook-duo-linux Rust daemon (v2+).
# State source: /var/lib/zenbook-duo/state.json

WALLPAPER_DIR="${HOME}/Pictures/ZenbookWallpapers"
STATE_FILE="/var/lib/zenbook-duo/state.json"
CONFIG_FILE="${HOME}/.config/zenbook-wallpaper/config"
MODE_FILE="/tmp/zenbook_wallpaper_mode"
LOCK_FILE="/tmp/zenbook_wallpaper_lock"

# --- Defaults (overridable via config) ---
ENABLED=true
LAPTOP_MODE=random;   LAPTOP_DEFAULT_IMAGE=
DUAL_MODE=random;     DUAL_DEFAULT_IMAGE=
DESKTOP_MODE=random;  DESKTOP_DEFAULT_IMAGE=
SHARING_MODE=random;  SHARING_DEFAULT_IMAGE=

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi
}
load_config

if [ "$ENABLED" != "true" ]; then
    echo "$(date) - Auto-wallpaper disabled in config. Exiting."
    exit 0
fi

mkdir -p "${WALLPAPER_DIR}/"{Laptop,Dual,Desktop,Sharing}

# ============================================================
# Image helpers
# ============================================================

pick_image() {
    local dir="$1" mode_setting="$2" default_path="$3" exclude="${4:-}"
    if [ "$mode_setting" = "default" ] && [ -n "$default_path" ] && [ -f "$default_path" ]; then
        echo "$default_path"
    elif [ -d "$dir" ]; then
        if [ -n "$exclude" ]; then
            find "$dir" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' \) \
                | grep -Fv "$exclude" | shuf -n 1
        else
            find "$dir" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' \) \
                | shuf -n 1
        fi
    fi
}

apply_wallpaper() {
    local opts="$1"
    local uri="$2"
    echo "$(date) - WALLPAPER - opts=$opts uri=file://$uri"
    gsettings set org.gnome.desktop.background picture-options  "$opts"
    gsettings set org.gnome.desktop.background picture-uri      "file://$uri"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://$uri"
    gdbus call --session \
        --dest org.gnome.Shell \
        --object-path /org/gnome/Shell \
        --method org.gnome.Shell.Eval \
        "Main.layoutManager._updateBackgrounds();" \
        2>/dev/null || true
    echo "$(date) - WALLPAPER - Done"
}

# ============================================================
# Core switch -- runs in a background subshell with flock()
# so watchers never block, and concurrent calls don't pile up.
# ============================================================

switch_wallpaper() {
    local mode="$1"

    # Debounce: skip if we're already in this mode
    local last
    last=$(cat "$MODE_FILE" 2>/dev/null || echo "")
    if [ "$mode" = "$last" ]; then
        echo "$(date) - SWITCH - Already in $mode, skipping"
        return
    fi
    echo "$mode" > "$MODE_FILE"
    echo "$(date) - SWITCH - mode=$mode (was: ${last:-none})"

    (
        exec 9>"$LOCK_FILE"
        flock 9

        load_config
        local wp_dir="${WALLPAPER_DIR}/${mode}"

        case "$mode" in
            Laptop)
                local img ts out
                img=$(pick_image "$wp_dir" "$LAPTOP_MODE" "$LAPTOP_DEFAULT_IMAGE")
                if [ -n "$img" ]; then
                    ts=$(date +%s%3N)
                    out="/tmp/zenbook_wallpaper_laptop_${ts}.jpg"
                    cp "$img" "$out"
                    find /tmp -maxdepth 1 -name 'zenbook_wallpaper_laptop_*.jpg' \
                        ! -name "$(basename "$out")" -delete 2>/dev/null
                    apply_wallpaper "zoom" "$out"
                    local scale
                    scale=$(gdctl show 2>/dev/null | awk '/Scale:/{print $2; exit}')
                    [ -z "$scale" ] && scale=1.66
                    gdctl set --logical-monitor --primary --scale "$scale" --monitor eDP-1 2>/dev/null || true
                else
                    echo "$(date) - No images in $wp_dir"
                fi
                ;;
            Dual)
                local img ts out
                img=$(pick_image "$wp_dir" "$DUAL_MODE" "$DUAL_DEFAULT_IMAGE")
                if [ -n "$img" ]; then
                    ts=$(date +%s%3N)
                    out="/tmp/zenbook_wallpaper_dual_${ts}.jpg"
                    magick "$img" -filter Lanczos -resize 2880x3600^ -gravity center -extent 2880x3600 \
                        -unsharp 0x0.75+0.75+0.008 "$out"
                    find /tmp -maxdepth 1 -name 'zenbook_wallpaper_dual_*.jpg' \
                        ! -name "$(basename "$out")" -delete 2>/dev/null
                    apply_wallpaper "spanned" "$out"
                else
                    echo "$(date) - No images in $wp_dir"
                fi
                ;;
            Desktop)
                local img ts out
                img=$(pick_image "$wp_dir" "$DESKTOP_MODE" "$DESKTOP_DEFAULT_IMAGE")
                if [ -n "$img" ]; then
                    ts=$(date +%s%3N)
                    out="/tmp/zenbook_wallpaper_desktop_${ts}.jpg"
                    magick "$img" -filter Lanczos -resize 3600x2880^ -gravity center -extent 3600x2880 \
                        -unsharp 0x0.75+0.75+0.008 "$out"
                    find /tmp -maxdepth 1 -name 'zenbook_wallpaper_desktop_*.jpg' \
                        ! -name "$(basename "$out")" -delete 2>/dev/null
                    apply_wallpaper "spanned" "$out"
                else
                    echo "$(date) - No images in $wp_dir"
                fi
                ;;
            Sharing)
                local img1 img2 ts out
                img1=$(pick_image "$wp_dir" "$SHARING_MODE" "$SHARING_DEFAULT_IMAGE")
                if [ -n "$img1" ]; then
                    img2=$(pick_image "$wp_dir" "$SHARING_MODE" "$SHARING_DEFAULT_IMAGE" "$img1")
                    [ -z "$img2" ] && img2="$img1"
                    ts=$(date +%s%3N)
                    out="/tmp/zenbook_wallpaper_sharing_${ts}.jpg"
                    magick "$img1" -filter Lanczos -resize 2880x1800^ -gravity center -extent 2880x1800 \
                        -rotate 180 -unsharp 0x0.75+0.75+0.008 /tmp/zw_share_top.jpg
                    magick "$img2" -filter Lanczos -resize 2880x1800^ -gravity center -extent 2880x1800 \
                        -unsharp 0x0.75+0.75+0.008 /tmp/zw_share_bottom.jpg
                    magick /tmp/zw_share_top.jpg /tmp/zw_share_bottom.jpg -append "$out"
                    find /tmp -maxdepth 1 -name 'zenbook_wallpaper_sharing_*.jpg' \
                        ! -name "$(basename "$out")" -delete 2>/dev/null
                    apply_wallpaper "spanned" "$out"
                else
                    echo "$(date) - No images in $wp_dir"
                fi
                ;;
        esac
    ) &
}

# ============================================================
# State reader -- derives wallpaper mode from daemon state
# ============================================================

read_mode_from_state() {
    local attached orientation
    attached=$(jq -r '.status.keyboardAttached' "$STATE_FILE" 2>/dev/null)
    orientation=$(jq -r '.status.orientation' "$STATE_FILE" 2>/dev/null)

    if [ "$attached" = "true" ]; then
        echo "Laptop"
    else
        case "$orientation" in
            left|right)   echo "Desktop" ;;
            inverted)     echo "Sharing" ;;
            *)            echo "Dual" ;;
        esac
    fi
}

# ============================================================
# Initial state
# ============================================================

echo "$(date) - Starting Zenbook Duo Auto-Wallpaper Switcher"
echo "$(date) - Watching $STATE_FILE (Rust daemon)"

# Clean up stale wallpaper files from any previous run
rm -f "$MODE_FILE"
find /tmp -maxdepth 1 -name 'zenbook_wallpaper_*.jpg' -delete 2>/dev/null
echo "$(date) - Cleaned up stale wallpaper files"

# Wait up to 30s for the daemon to create state.json
wait_count=0
while [ ! -f "$STATE_FILE" ] && [ "$wait_count" -lt 30 ]; do
    echo "$(date) - Waiting for $STATE_FILE..."
    sleep 1
    wait_count=$((wait_count + 1))
done

if [ -f "$STATE_FILE" ]; then
    mode=$(read_mode_from_state)
    echo "$(date) - Initial state: mode=$mode"
    switch_wallpaper "$mode"
else
    echo "$(date) - $STATE_FILE not found after 30s; defaulting to Dual"
    switch_wallpaper "Dual"
fi

# ============================================================
# Watch state.json for changes via inotifywait
# ============================================================

echo "$(date) - Watching $STATE_FILE for state changes"

inotifywait -m -e modify -e moved_to --format '%w%f' \
    "$(dirname "$STATE_FILE")" 2>/dev/null \
| while read -r changed_file; do
    # Only react to state.json changes (ignore daemon.log, etc.)
    [ "$(basename "$changed_file")" = "state.json" ] || continue

    # Brief pause to let the daemon finish writing
    sleep 0.5

    mode=$(read_mode_from_state)
    switch_wallpaper "$mode"
done
