# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Raspberry Pi network management appliance that provides USB serial console access with supporting network services. The system creates a WiFi hotspot with integrated DNS, DHCP, HTTP file server, and TFTP services for managing serial devices.

## Architecture

The project consists of configuration files for multiple system services that work together:

- **Network Layer**: `hostapd` creates WiFi AP "OSQDU-SerialConsole", `dnsmasq` provides DNS/DHCP for domain `osqdu` on 192.168.44.x network
- **Serial Access**: Custom udev rules map CH341 USB-serial adapters to `/dev/ttyQDU[0-3]` devices, `minicom` provides console access
- **File Services**: `nginx` serves files from `/srv/files`, `tftpd-hpa` serves from `/srv/tftp`
- **System Integration**: Network forwarding enabled via sysctl, tmux auto-launch for session management

## Key Configuration Files

- `dnsmasq/dnsmasq.conf`: DNS/DHCP server config with upstream DNS (1.1.1.1, OpenDNS, Hurricane Electric)
- `hostapd/hostapd.conf`: WiFi AP configuration with WPA2-PSK authentication
- `hostapd/gen-wpa-psk.sh`: Generates PSK from wlan0 MAC address
- `udev-rulefile/10-ch341-usbserial.rules`: Creates consistent `/dev/ttyQDU*` device names
- `minicom/minirc.dfl`: Serial console defaults (9600 8N1)
- `nginx/fileserver.conf`: Simple HTTP file server with directory listing
- `sysctl.d/10-router.conf`: Enables IPv4/IPv6 forwarding
- `tmux-bashrc`: Auto-launches tmux sessions

## Device Management

USB serial devices are accessed via `/dev/ttyQDU0` (primary console) through `/dev/ttyQDU3`. The udev rules ensure consistent device naming based on USB port positions on Raspberry Pi hardware.

## Network Configuration

The system creates an isolated network (192.168.44.128/25) with the Pi as gateway. WiFi clients receive DHCP leases and can access local `.osqdu` domain names. Internet access is provided through the eth0 interface with configured upstream DNS servers.