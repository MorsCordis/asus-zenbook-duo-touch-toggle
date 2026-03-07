#!/bin/bash
# Auto-Wallpaper Switcher for Zenbook Duo (2025)
# Hooks into zenbook-duo-linux's duo.sh via:
#   /tmp/duo/status  — inotifywait watches this for keyboard attach/detach
#   /tmp/duo/duo.log — single awk process watches for rotation events
#
# Image processing runs in a background subshell with a flock() so
# events never block the watchers, and concurrent switches can't pile up.

WALLPAPER_DIR="${HOME}/Pictures/ZenbookWallpapers"
LOG_FILE="/tmp/duo/duo.log"
STATUS_FILE="/tmp/duo/status"
CONFIG_FILE="${HOME}/.config/zenbook-wallpaper/config"
# Each mode uses its own output file so the URI genuinely changes between
# mode switches — GNOME's background compositor caches by URI, not by file
# content, so sharing one path means it never refreshes the rendered layer.
IMG_LAPTOP="/tmp/zenbook_wallpaper_laptop.jpg"
IMG_DUAL="/tmp/zenbook_wallpaper_dual.jpg"
IMG_DESKTOP="/tmp/zenbook_wallpaper_desktop.jpg"
IMG_SHARING="/tmp/zenbook_wallpaper_sharing.jpg"
MODE_FILE="/tmp/zenbook_wallpaper_mode"    # persists last mode (debounce)
LOCK_FILE="/tmp/zenbook_wallpaper_lock"   # prevents concurrent magick runs

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
    local uri="$2"   # must be a unique path each call — GNOME caches by URI
    echo "$(date) - WALLPAPER - opts=$opts uri=file://$uri"
    gsettings set org.gnome.desktop.background picture-options  "$opts"
    gsettings set org.gnome.desktop.background picture-uri      "file://$uri"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://$uri"
    # Explicitly tell GNOME Shell to rebuild its background actors.
    # When a monitor is removed (dual→single), Mutter keeps the old background
    # actor rather than recreating it, so gsettings changes don't reach it.
    # _updateBackgrounds() tears down and recreates all actors with current settings.
    # Shell.Eval requires unsafe-mode in GNOME 44+ so the || true swallows failures.
    gdbus call --session \
        --dest org.gnome.Shell \
        --object-path /org/gnome/Shell \
        --method org.gnome.Shell.Eval \
        "Main.layoutManager._updateBackgrounds();" \
        2>/dev/null || true
    echo "$(date) - WALLPAPER - Done"
}

# ============================================================
# Core switch — runs in a background subshell with flock()
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

    # Run image processing in background; flock prevents pile-ups
    (
        exec 9>"$LOCK_FILE"
        flock 9   # blocks only if another switch is actively running

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
                    # GNOME background actors are not rebuilt by gsettings changes alone
                    # after a monitors-changed event (dual→single transition).
                    # Re-applying the same single-monitor gdctl config fires
                    # monitors-changed again, which forces GNOME Shell to recreate
                    # background actors from the current gsettings (our new wallpaper).
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
# Initial state
# ============================================================

echo "$(date) - Starting Zenbook Duo Auto-Wallpaper Switcher"

# Clean up all stale wallpaper files from any previous run
rm -f "$MODE_FILE"
find /tmp -maxdepth 1 -name 'zenbook_wallpaper_*.jpg' -delete 2>/dev/null
echo "$(date) - Cleaned up stale wallpaper files"

# Wait up to 15s for duo.sh to create the status file
wait_count=0
while [ ! -f "$STATUS_FILE" ] && [ "$wait_count" -lt 15 ]; do
    echo "$(date) - Waiting for $STATUS_FILE..."
    sleep 1
    wait_count=$((wait_count + 1))
done

if [ -f "$STATUS_FILE" ]; then
    # shellcheck disable=SC1090
    source "$STATUS_FILE"
    if [ "$KEYBOARD_ATTACHED" = "true" ]; then
        switch_wallpaper "Laptop"
    else
        switch_wallpaper "Dual"
    fi
else
    echo "$(date) - $STATUS_FILE not found after 15s; defaulting to Dual"
    switch_wallpaper "Dual"
fi

# ============================================================
# Single log watcher — all events come from duo.log
# ============================================================
# Key insight: "MONITOR - Disabled/Enabled bottom display" is logged by
# duo.sh AFTER duo-display-set-single/dual-below fully completes and
# duo-set-status is written. That means Mutter's monitor reconfiguration
# is done before we ever apply a new wallpaper — no more race conditions.
#
# By contrast, watching /tmp/duo/status fires BEFORE the display change,
# causing GNOME's background actor recreate (triggered by monitor changes)
# to overwrite our wallpaper setting.

watch_log() {
    echo "$(date) - Watching $LOG_FILE for display and rotation events"
    tail -n 0 -F "$LOG_FILE" 2>/dev/null \
    | awk '
        /MONITOR - Disabled bottom display/ { print "Laptop";         fflush() }
        /MONITOR - Enabled bottom display/  { print "Dual";           fflush() }
        /ROTATE - Left-up/                  { print "Desktop:check";  fflush() }
        /ROTATE - Right-up/                 { print "Desktop:check";  fflush() }
        /ROTATE - Bottom-up/                { print "Sharing:check";  fflush() }
        /ROTATE - Normal/                   { print "Dual:check";     fflush() }
    ' \
    | while read -r event; do
        local mode="${event%%:*}"
        local check="${event##*:}"

        # Rotation events only fire when keyboard is detached; verify before acting.
        if [ "$check" = "check" ]; then
            # shellcheck disable=SC1090
            source "$STATUS_FILE" 2>/dev/null
            if [ "$KEYBOARD_ATTACHED" != "false" ]; then
                continue
            fi
        fi

        # Brief pause to let duo.sh finish its gdctl call before we kick off ours.
        sleep 0.8
        switch_wallpaper "$mode"
    done
}

# ============================================================
# Run watcher, wait for background jobs
# ============================================================

watch_log &

wait
