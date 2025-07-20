#!/bin/bash
# Quick serial console access script

DEVICE="${1:-/dev/{{USB_DEVICE_PREFIX}}-1}"

if [[ ! -e "$DEVICE" ]]; then
    echo "Error: Serial device $DEVICE not found"
    echo "Available devices:"
    ls /dev/{{USB_DEVICE_PREFIX}}-* 2>/dev/null || echo "  No USB serial devices found"
    exit 1
fi

echo "Connecting to $DEVICE..."
echo "Press Ctrl+A X to exit minicom"
exec minicom -D "$DEVICE"