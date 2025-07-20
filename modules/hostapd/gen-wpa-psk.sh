#!/bin/bash
ifconfig wlan0 | sed -n -e '/^.*ether \([:[:xdigit:]\-]*\).*/{s//\1/;y/abcdef/ABCDEF/;s/://g;s/^/00:00:00:00:00:00 /;p}' | cut -c1-26 | tee hostapd.wpa_psk
