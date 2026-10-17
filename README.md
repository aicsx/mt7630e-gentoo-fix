# ASUS X555LA — MediaTek MT7630E Fix for Gentoo OpenRC

Scripts for the MediaTek MT7630E Wi-Fi/Bluetooth combo device on Gentoo Linux with OpenRC and elogind.

The installer detects the hardware at runtime instead of assuming fixed USB and PCI addresses.

## Features

- Detects the Bluetooth USB device using sysfs interface descriptors, with manufacturer/product labels as a fallback.
- Detects the MediaTek MT7630E Wi-Fi PCI device using vendor/device IDs.
- Installs a Bluetooth initialization script for OpenRC.
- Installs an elogind suspend/resume hook for the Wi-Fi PCI device.
- Generates an active udev rule using the USB vendor and product IDs detected at installation time. Bluetooth initialization and suspend/resume handling remain in the existing scripts.
- Creates backups before replacing installed files.
- Provides rollback handling if installation fails.
- Does not modify GRUB or `/etc/conf.d/modules`.

## Requirements

- Gentoo Linux
- OpenRC
- elogind
- Bash, `flock`, `udevadm`, `rc-update`, and standard system utilities
- Root privileges for installation

## Hardware detection

The installer detects the Bluetooth USB device and Wi-Fi PCI device from sysfs. It stops if detection is missing or ambiguous.

The detected IDs describe the current machine and are not hard-coded into the runtime scripts.

## Installation

Clone the repository and enter its directory:

    git clone https://github.com/aicsx/mt7630e-gentoo-fix.git
    cd mt7630e-gentoo-fix

Check the detected hardware without changing the system:

    bash build/install.sh --check

Review the installer, then run it with root privileges:

    sudo bash build/install.sh

The installer creates a timestamped backup directory under `/root` before replacing the target files. Keep this directory until the new configuration has been tested.

## Installed files

- `/etc/udev/rules.d/99-mt7630e-bluetooth.rules`
- `/etc/local.d/99-mt7630e-bluetooth.start`
- `/usr/lib/elogind/system-sleep/40-mediatek-wifi.sh`, if that directory exists; otherwise `/lib/elogind/system-sleep/40-mediatek-wifi.sh`

The installer enables the OpenRC `local` and `bluetooth` services.

## Verification

Check Bluetooth enumeration:

    lsusb
    bluetoothctl list

Check the Wi-Fi PCI device and driver:

    lspci -nnk
    ip link

Check OpenRC service status:

    rc-service bluetooth status
    rc-service local status

Test suspend/resume and verify that Wi-Fi and Bluetooth recover correctly.

## GRUB and kernel parameters

This project does not change GRUB configuration or kernel command-line parameters. Do not copy an example resume UUID or add kernel parameters without confirming that they are appropriate for your system.

## Safety

Review the scripts before installation. The `--check` mode performs hardware detection and validation only; it does not install files or enable services.
