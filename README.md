# Raspberry Pi network management appliance, with serial console, DNS, DHCP, TFTP and HTTP server
To run this on a freshly installed Pi OS, follow these steps:

# Prerequisites

1. Fresh Raspberry Pi OS (Bookworm or later recommended)
2. Root access (sudo privileges)
3. Internet connection for package downloads

# Installation Steps

1. Clone or Download the Project

- Option A: Using git (if available)

    ```
    git clone <repository-url> raspberrypi-usbserial-console
    cd raspberrypi-usbserial-console
    ```

- Option B: Download and extract if you have the files Transfer files to your Pi and extract to a directory

2. Make Scripts Executable

    ```
    chmod +x install.sh
    find modules -name "*.sh" -exec chmod +x {} \;
    ```

3. Run Full Installation

    Full installation with all modules
    ```
    sudo ./install.sh
    ```
    Or install specific modules only
    ```
    sudo ./install.sh system network hostapd dnsmasq nginx
    ```

4. Check Available Options

    See all available modules
    ```
    ./install.sh --list
    ```

    View help
    ```
    ./install.sh --help
    ```

# What the Installation Does

1. System Preparation: Updates packages, installs dependencies
2. Network Setup: Configures IPv4/IPv6 routing, nftables firewall
3. WiFi Hotspot: Creates USBSerial-Console network with WPA3/WPA2
4. File Sharing: Sets up HTTP, TFTP, and SMB access to /srv/shared
5. USB Serial: Configures device naming and console access scripts
6. Service Coordination: Manages systemd services with proper dependencies

# Post-Installation

## Access the System

- WiFi Network: USBSerial-Console (password is the Pi's MAC address without colons)
- Web Interface: http://192.168.44.1/
- File Sharing: All protocols serve /srv/shared/
- Console Access: Use console and list-consoles commands

## Check Status

Check if services are running
```
sudo systemctl status usbserial-console
sudo systemctl status hostapd dnsmasq nginx
```

View logs
```
sudo journalctl -u usbserial-console -f
```

# Customization

If you need to customize settings, edit config/global.conf before installation:

Edit configuration
```
nano config/global.conf
```

Then run installation
```
sudo ./install.sh
```

# Troubleshooting

## If Installation Fails

- Check /var/log/usbserial/ for detailed logs
- Ensure Pi has internet connection
- Verify you're running as root/sudo
- Check if WiFi interface exists: ip link show wlan0

## Module-Specific Issues

Reinstall specific module
```
sudo ./install.sh --force hostapd
```

Install dependencies manually
```
sudo ./install.sh system network
sudo ./install.sh hostapd
```

# READ THIS !!
The system is designed to work on a completely fresh Pi OS installation with no prior configuration needed!

