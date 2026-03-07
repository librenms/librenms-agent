#!/bin/sh

# distro.sh
# Extracts OpenWrt version string from banner (from "OpenWrt" onwards)

grep OpenWrt /etc/banner | sed 's/.*OpenWrt/OpenWrt/' | head -1
