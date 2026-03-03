# ASUS Zenbook Duo (2025) Lower Touchscreen Toggle

A robust and un-intrusive bash script that gracefully toggles the touch functionality of the lower display on your ASUS Zenbook Duo UX8406CA (2025), **without disabling the ASUS active stylus**.

## The Problem
Standard display or input toggling on the Zenbook Duo often completely disables the second screen's I2C controller, unbinding both the finger touch data *and* the active stylus simultaneously. Wayland and `libinput` also automatically switch to phantom 'UNKNOWN' or 'Touchpad' alias nodes if you selectively lock the physical controller.

## The Solution
This script scans for all active `ELAN9009` multi-touch event nodes that handle screen touches, bypassing any generic Stylus interfaces. It dynamically compiles a tiny, lightning-fast native `C` binary in the background that instantly locks those nodes using a strict kernel `EVIOCGRAB` hold.
This physically prevents the Linux kernel from forwarding finger touches to your desktop display server, while leaving the stylus fully operational. Running the script again kills the background lock and restores touch.

## Prerequisites
- Linux (designed around GNOME + Wayland, but `evdev` grabs operate at the kernel level across all distributions).
- Requires `gcc` compiler installed on your system (usually pre-installed via build-essentials) to dynamically compile the C locking binary on-the-fly.
- Requires `libnotify-bin` (`notify-send`) for desktop toast notifications.

## Installation 

To use this script seamlessly from a keyboard shortcut without a password prompt popping up, you need to grant the script permission to execute via `sudo` securely.

1. Clone or download this repository to your preferred script folder (e.g. `~/projects/touch toggle/`).
2. Make the script and installer executable:
```bash
chmod +x toggle-lower-touch.sh
chmod +x install.sh
```
3. Run the installer to authorize the passwordless sudo shortcut rule.
```bash
sudo ./install.sh
```

## Setup Keyboard Shortcut (GNOME)
Currently, touching the script using a GNOME Custom Shortcut is the easiest way to switch on the fly.

1. Open **Settings** -> **Keyboard** -> **View and Customize Shortcuts** -> **Custom Shortcuts**.
2. Click **Add Shortcut**.
3. Name it `Toggle Lower Touch`.
4. Command: **You must append the `sudo` prefix and enclose the path in quotes if it contains spaces.** 
   ```bash
   sudo "/path/to/your/folder/toggle-lower-touch.sh"
   ```
5. Click **Set Shortcut...** and bind it to your desired hotkey (e.g., `Ctrl + Shift + T`).

## Logging
Toast Notifications will indicate current state ("Lower Touchscreen DISABLED" and "Lower Touchscreen ENABLED"). If an error arises, a localized `notify-send` error pop-up will trigger. Background lock state is maintained dynamically via `/tmp/duo_touch_grabber.pid`.
