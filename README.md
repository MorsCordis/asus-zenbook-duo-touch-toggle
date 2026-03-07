# ASUS Zenbook Duo (2025) Utilities

A collection of scripts for the ASUS Zenbook Duo UX8406CA (2025) running Linux (Fedora + GNOME + Wayland).

---

## 1. Lower Touchscreen Toggle

A robust bash script that gracefully toggles touch functionality on the lower display **without disabling the ASUS active stylus**.

### The Problem

Standard display or input toggling on the Zenbook Duo completely disables the second screen's I2C controller, unbinding both finger touch and the active stylus simultaneously. Wayland and `libinput` also automatically switch to phantom `UNKNOWN` or `Touchpad` alias nodes if you selectively lock the physical controller.

### The Solution

This script scans for all active `ELAN9009` multi-touch event nodes, bypassing stylus interfaces. It dynamically compiles a tiny native `C` binary that locks those nodes using a kernel `EVIOCGRAB` hold — preventing finger touches from reaching the display server while leaving the stylus fully operational. Running the script again kills the lock and restores touch.

### Prerequisites

- Linux (GNOME + Wayland; `evdev` grabs operate at the kernel level across all distributions)
- `gcc` (usually pre-installed via build-essentials)
- `libnotify-bin` (`notify-send`) for desktop toast notifications

### Installation

1. Clone or download this repository (e.g. to `~/projects/touch toggle/`).
2. Make files executable:
   ```bash
   chmod +x toggle-lower-touch.sh install.sh
   ```
3. Run the installer to configure passwordless sudo:
   ```bash
   ./install.sh
   ```

### Setup Keyboard Shortcut (GNOME)

1. Open **Settings → Keyboard → View and Customize Shortcuts → Custom Shortcuts**
2. Click **Add Shortcut**
3. Name: `Toggle Lower Touch`
4. Command (note the `sudo` prefix and quotes for paths with spaces):
   ```bash
   sudo "/path/to/touch toggle/toggle-lower-touch.sh"
   ```
5. Click **Set Shortcut...** and bind your desired hotkey (e.g. `Ctrl+Shift+T`).

### Logging

Toast notifications indicate current state (`Lower Touchscreen DISABLED` / `ENABLED`). Lock state is maintained via `/tmp/duo_touch_grabber.pid`.

---

## 2. Auto-Wallpaper Switcher

Automatically applies appropriate wallpapers when the Zenbook Duo changes orientation or screen mode. Powered by a `systemd` user service that hooks into the [zenbook-duo-linux](https://github.com/zakstam/zenbook-duo-linux) daemon.

### How It Works

A single `awk` process tails `/tmp/duo/duo.log` and reacts to display and rotation events — virtually zero CPU when idle:

| Event in log | Action |
|---|---|
| `MONITOR - Disabled bottom display` | → Laptop wallpaper |
| `MONITOR - Enabled bottom display` | → Dual wallpaper |
| `ROTATE - Left-up` / `Right-up` | → Desktop wallpaper (keyboard detached only) |
| `ROTATE - Bottom-up` | → Sharing wallpaper (keyboard detached only) |
| `ROTATE - Normal` | → Dual wallpaper (keyboard detached only) |

These log lines are written by `duo.sh` *after* each `gdctl` display command completes, so wallpaper changes never race with monitor reconfiguration.

Image processing (`magick`) runs in a background subshell with a `flock` lock so events never block and concurrent switches can't pile up. Each mode writes to a uniquely timestamped temp file (e.g. `zenbook_wallpaper_laptop_1741312800.jpg`) to guarantee GNOME's compositor loads a fresh texture every time.

> **Note — Laptop mode:** When going from dual→single screen, GNOME's background actor doesn't rebuild on `gsettings` changes alone. After setting the wallpaper, the script re-issues the same `gdctl` single-monitor command, which fires `monitors-changed` and forces GNOME Shell to recreate its background actors from the updated settings.

### Modes

| Mode | Trigger | Canvas |
|------|---------|--------|
| **Laptop** | Keyboard attached | One image zoomed to fill the upper screen (2880×1800) |
| **Dual** | Keyboard removed, upright | One image spanned across both vertical screens (2880×3600) |
| **Desktop** | Screen rotated 90° (left or right) | One image spanned across both side-by-side screens (3600×2880) |
| **Sharing** | Screen flipped 180° | Two images stitched top-to-top (one rotated 180° for the person across) |

### Prerequisites

- [zenbook-duo-linux](https://github.com/zakstam/zenbook-duo-linux) installed and its `zenbook-duo-user.service` running (provides `/tmp/duo/duo.log` and `/tmp/duo/status`)
- `ImageMagick` (installed automatically by the installer)
- `inotify-tools` (installed by the zenbook-duo-linux setup script)
- GNOME + Wayland

### Installation

```bash
chmod +x install-wallpaper.sh
./install-wallpaper.sh
```

This will:
- Install `ImageMagick` if not present
- Create wallpaper directories under `~/Pictures/ZenbookWallpapers/`
- Write a default config to `~/.config/zenbook-wallpaper/config`
- Install and enable the `zenbook-wallpaper` systemd user service

### Adding Wallpapers

Place images (`.jpg`, `.png`, `.jpeg`) in the appropriate subfolder:

```
~/Pictures/ZenbookWallpapers/
  Laptop/    ← single-screen wallpapers
  Dual/      ← tall portrait images (or any — auto-cropped to 2880×3600)
  Desktop/   ← wide landscape images (or any — auto-cropped to 3600×2880)
  Sharing/   ← images for sharing/tent mode (two images used if available)
```

At least one image per folder is required for that mode to trigger.

### Configuration

Edit `~/.config/zenbook-wallpaper/config` — changes take effect on the next mode switch without restarting the service.

```bash
# Disable the wallpaper switcher entirely
ENABLED=false

# Use a specific image instead of random for a mode
DUAL_MODE=default
DUAL_DEFAULT_IMAGE=/home/you/Pictures/ZenbookWallpapers/Dual/panoramic.jpg

# Other modes follow the same pattern:
# LAPTOP_MODE=random|default    LAPTOP_DEFAULT_IMAGE=
# DESKTOP_MODE=random|default   DESKTOP_DEFAULT_IMAGE=
# SHARING_MODE=random|default   SHARING_DEFAULT_IMAGE=
```

### Service Management

```bash
# Stop/start without uninstalling
systemctl --user stop zenbook-wallpaper.service
systemctl --user start zenbook-wallpaper.service

# Disable/enable on login
systemctl --user disable zenbook-wallpaper.service
systemctl --user enable zenbook-wallpaper.service

# View live logs
journalctl --user -u zenbook-wallpaper.service -f
```

---

## Acknowledgements

These utilities were developed with the assistance of [Google Gemini](https://gemini.google.com).
