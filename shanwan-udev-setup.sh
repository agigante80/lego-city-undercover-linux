#!/bin/bash
# shanwan-udev-setup.sh
#
# One-time installer for the SHANWAN Xbox360 controller udev deadzone rule.
# Run once with sudo:
#
#   sudo ./shanwan-udev-setup.sh
#
# Prerequisites:
#   sudo apt install joystick      # provides /usr/bin/evdev-joystick
#
# What this does:
#   Installs /etc/udev/rules.d/99-shanwan-controller.rules, which fires automatically
#   every time the SHANWAN controller is plugged in and applies a 4096-unit deadzone
#   (~12.5%) and fuzz 64 on all four analog stick axes.
#
# Why this is needed:
#   The SHANWAN Xbox360 clone (USB VID:PID 045e:028e) has noisy analog sticks that
#   emit a continuous stream of micro-movement events even when untouched. Under
#   Wine/Proton, these flood the HID report queue with:
#     err:hid_report:process_hid_report Device reports coming in too fast, last report not read yet!
#   This adds thread pressure to Wine's message loop, which can contribute to audio
#   thread deadlocks (RtlpWaitForCriticalSection timeouts) in games with tight audio
#   synchronisation — notably LEGO City Undercover.
#
# Tested on:
#   Ubuntu 24.04.4 LTS (Noble), kernel 6.17.0-20-generic
#   SHANWAN controller: USB 045e:028e, manufacturer string "SHANWAN"
#
# After running: unplug and replug the controller to apply immediately.
# To verify: evdev-joystick --showcal /dev/input/eventXX
#            X/Y/RX/RY axes should show flatness: 4096 (=12.50%)

set -e

RULE_FILE=/etc/udev/rules.d/99-shanwan-controller.rules

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: run this script with sudo." >&2
    exit 1
fi

if ! command -v evdev-joystick &>/dev/null; then
    echo "Error: evdev-joystick not found. Install it first:" >&2
    echo "  sudo apt install joystick" >&2
    exit 1
fi

cat > "$RULE_FILE" << 'EOF'
# SHANWAN Xbox360 clone controller — suppress HID report flooding
#
# This controller spoofs the Microsoft Xbox360 VID:PID (045e:028e) but its USB
# manufacturer string is "SHANWAN". It has noisy analog axes that flood Wine's
# HID report queue ("Device reports coming in too fast"), causing thread pressure
# that contributes to RtlpWaitForCriticalSection deadlocks in LEGO City Undercover.
#
# Fix: set deadzone (flat=4096, ~12.5%) and fuzz (64) on analog stick axes only.
# Triggers (Z/RZ, range 0-255) and d-pad (HAT, range -1/1) are left at 0 — they
# are digital/small-range axes where a 4096 deadzone would disable them entirely.
# %N = full device node path (e.g. /dev/input/event23) — %k alone gives just event23.
# Requires: apt install joystick   (provides /usr/bin/evdev-joystick)

SUBSYSTEM=="input", KERNEL=="event*", \
    ATTRS{idVendor}=="045e", ATTRS{idProduct}=="028e", ATTRS{manufacturer}=="SHANWAN", \
    RUN+="/usr/bin/evdev-joystick --evdev %N --axis 0 --deadzone 4096 --fuzz 64", \
    RUN+="/usr/bin/evdev-joystick --evdev %N --axis 1 --deadzone 4096 --fuzz 64", \
    RUN+="/usr/bin/evdev-joystick --evdev %N --axis 3 --deadzone 4096 --fuzz 64", \
    RUN+="/usr/bin/evdev-joystick --evdev %N --axis 4 --deadzone 4096 --fuzz 64"
EOF

udevadm control --reload-rules

echo "Rule installed to $RULE_FILE"
echo "Done. Unplug and replug the SHANWAN controller to apply."
echo ""
echo "To verify: evdev-joystick --showcal /dev/input/eventXX"
echo "           X/Y/RX/RY should show flatness: 4096 (=12.50%)"
