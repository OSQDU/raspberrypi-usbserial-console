#!/bin/bash
# List available serial console devices

echo "USB Serial Console Devices:"
echo "=========================="

if ls /dev/{{USB_DEVICE_PREFIX}}-* >/dev/null 2>&1; then
    for device in /dev/{{USB_DEVICE_PREFIX}}-*; do
        device_name=$(basename "${device}")
        if [[ -c "${device}" ]]; then
            echo "  ${device_name} -> ${device}"
        fi
    done
else
    echo "  No USB serial devices found"
    echo ""
    echo "Make sure USB serial adapters are connected and udev rules are loaded."
fi

echo ""
echo "Usage: console [device]"
echo "Example: console /dev/{{USB_DEVICE_PREFIX}}-1.0"
