#!/bin/bash

# Target the bare touchscreen for the lower monitor (no "Stylus" or "Touchpad" suffix)
DEVICE_NAME="ELAN9009:00 04F3:4448"
# Because Python's fcntl.ioctl struct packing fails silently on some modern kernels,
# we compile a tiny, brutal native C binary to hold the EVIOCGRAB locks.
GRABBER_SRC="/tmp/duo_touch_grabber.c"
GRABBER_BIN="/tmp/duo_touch_grabber_bin"

cat << 'EOF' > "$GRABBER_SRC"
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    int i;
    int fds[20];
    
    // Write our PID so the bash script can kill us later
    FILE *pid_file = fopen("/tmp/duo_touch_grabber.pid", "w");
    if (pid_file) {
        fprintf(pid_file, "%d", getpid());
        fclose(pid_file);
    }

    for (i = 1; i < argc; i++) {
        fds[i] = open(argv[i], O_RDONLY);
        if (fds[i] >= 0) {
            ioctl(fds[i], EVIOCGRAB, 1);
        }
    }

    // Hang forever holding the locks until killed
    while (1) {
        sleep(10000);
    }
    return 0;
}
EOF

# Compile it quickly if it doesn't exist or if we just updated it
gcc -O2 -o "$GRABBER_BIN" "$GRABBER_SRC" 2>/dev/null

USER_NAME=$(logname 2>/dev/null || echo $SUDO_USER)
if [ -z "$USER_NAME" ]; then
    USER_NAME=$USER
fi

# If executed via sudo from a GNOME shortcut, the environment is scrubbed. We rebuild it for notify-send.
if [ -z "$DISPLAY" ]; then
    export DISPLAY=:0
fi
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    USER_UID=$(id -u "$USER_NAME")
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_UID/bus"
fi

# Check if the grabber is currently running via the PID file
PID_FILE="/tmp/duo_touch_grabber.pid"

if [ -f "$PID_FILE" ]; then
    GRABBER_PID=$(cat "$PID_FILE")
    # Verify the process is truly python and currently running
    if sudo kill -0 "$GRABBER_PID" 2>/dev/null; then
        # It's running, so touch is disabled. Let's enable it by killing the grabber.
        sudo kill "$GRABBER_PID"
        sudo rm -f "$PID_FILE"
        sudo -u "$USER_NAME" DISPLAY="$DISPLAY" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" notify-send "Zenbook Duo" "Lower Touchscreen ENABLED" -i "input-touchscreen" -t 2000
        exit 0
    else
        # Stale PID file
        sudo rm -f "$PID_FILE"
    fi
fi

# If we get here, touch is currently enabled. Let's disable it perfectly using an evdev exclusively grab.

# 1. Find ALL ELAN event nodes for the LOWER screen (ELAN9009) EXCEPT the Stylus nodes
EVENT_NODES=""
for event_dir in /sys/class/input/event*; do
    if [ -f "$event_dir/device/name" ]; then
        name=$(cat "$event_dir/device/name")
        # Match only the bottom screen ELAN9009 controller, but explicitly EXCLUDE the Stylus so the pen still works!
        if [[ "$name" == *"ELAN9009"* ]] && [[ "$name" != *"Stylus"* ]]; then
            EVENT_NODES="$EVENT_NODES /dev/input/$(basename "$event_dir")"
        fi
    fi
done

if [ -z "$EVENT_NODES" ]; then
    sudo -u "$USER_NAME" DISPLAY="$DISPLAY" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" notify-send "Zenbook Duo" "Error: Could not locate Lower Touchscreen EVENT nodes." -i "error"
    exit 1
fi

# 2. Launch the compiled native C grabber in the background as root
# We spawn it with nohup so it detaches beautifully and holds the locks
sudo nohup "$GRABBER_BIN" $EVENT_NODES >/dev/null 2>&1 &
disown

# Send notification
sudo -u "$USER_NAME" DISPLAY="$DISPLAY" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" notify-send "Zenbook Duo" "Lower Touchscreen DISABLED (Stylus active)" -i "input-tablet" -t 2000
