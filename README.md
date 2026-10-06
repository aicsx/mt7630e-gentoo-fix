# Asus X555LA MediaTek MT7630E Fix for Gentoo OpenRC

Custom power management and initialization infrastructure tailored for the **MediaTek MT7630E (Combo Wi-Fi & Bluetooth)** hardware layout embedded inside the **Asus X555LA (Intel Core i3 variant)** laptop architecture running **Gentoo Linux** under **OpenRC** and **elogind**.

## Maintainer Info
* **Author:** ax (`ax@slackware.eu`)
* **IRC Network:** `irc1.slacware.eu` channel `#lug`
* **Channel/SLK:** `UmbrellaNet`

---

## The Hardware Problem
The MediaTek MT7630E chipset shares a unified internal bus configuration where the Wi-Fi card interfaces directly via PCIe (`0000:03:00.0`), while the integrated Bluetooth transceiver is mapped as an obscure Foxconn internal USB device (`ID 0489:e080`).

On vanilla Linux kernels, this deployment suffers from two fatal architectural race conditions:
1. **At Boot:** The native `btusb` driver initializes prior to the expansion of the virtual system environment (`sysfs`), failing to attach the hardware vendor bindings and leaving the Bluetooth interface completely missing.
2. **On Suspend/Resume:** Wakeup routines throw severe host controller interface failures (`Bluetooth: hci0: Opcode 0x0c03 failed: -110`) while the wireless networking state breaks down entirely, dropping `wlan0`.

## The Solution Architectural Design
This repository deploys an isolated, robust automated shell interface to safely orchestrate device power pathways without altering stable mainstream kernel structures:
* **`install.sh`**: Automated installer providing systemic string injection and layout setup.
* **`40-mediatek-wifi.sh`**: Handles clean teardown/unload of the active `mt76` network stacks during suspension, executing hot-unplug and hot-plug bus recalibrations via `rescan` hooks on wakeup.
* **`99-mt7630e-bluetooth.start`**: Asynchronously delays Bluetooth interface probing, performing an uninhibited runtime reset and dynamic device assignment (`new_id`) once system resource nodes stabilize.
* **`99-mt7630e-bluetooth.rules`**: Preserves raw modular dynamic configurations over long-term Portage environments.

---

## Installation

### 1. Clone and Deploy
Clone this project repository and run the setup logic inside your terminal:
```bash
git clone https://github.com
cd mt7630e-gentoo-fix
sudo chmod +x install.sh
sudo ./install.sh
```

### 2. Manual GRUB Step
To completely inhibit internal ACPI runtime crashes on your Asus motherboard layout, update your target kernel bootsmith variables:

1. Open `/etc/default/grub` using **Vim** and append the explicit low-energy states disablers (`pcie_aspm=off` and `intel_iommu=off`) inside your production bootline string:
   ```text
   GRUB_CMDLINE_LINUX_DEFAULT=\"net.ifnames=0 quiet splash resume=UUID=0b930a6b-5014-4a54-9885-ab09aa1a26af pcie_aspm=off intel_iommu=off\"
   ```
2. Recompile and update the active boot selection map:
   ```bash
   sudo grub-mkconfig -o /boot/grub/grub.cfg
   ```

### 3. Reboot
Perform a cold system reboot sequence to settle initialization daemons:
```bash
sudo reboot
```

---

## Operational Verification
After boot or immediate display/lid wakeup sequences, check functionality via standard diagnostic tools:
* Verify device pairing interface visibility: `bluetoothctl list`
* Verify physical kernel device enumeration: `lsusb`
* Trace active wireless link configuration: `ip a` or `ifconfig wlan0`
