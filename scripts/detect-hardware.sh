#!/bin/sh
# MT7630E Gentoo Fix - rilevamento hardware in sola lettura.
# Non installa file, non carica moduli e non modifica sysfs.

set -u

USB_ROOT="/sys/bus/usb/devices"
PCI_ROOT="/sys/bus/pci/devices"
usb_count=0
pci_count=0

printf '\n===== RILEVAMENTO MT7630E =====\n'

# Cerca il dispositivo Bluetooth MediaTek/Foxconn.
for d in "$USB_ROOT"/*; do
    [ -r "$d/idVendor" ] || continue
    [ -r "$d/idProduct" ] || continue

    vendor=$(cat "$d/idVendor")
    product=$(cat "$d/idProduct")
    manufacturer=""
    description=""

    [ ! -r "$d/manufacturer" ] ||
        manufacturer=$(cat "$d/manufacturer")
    [ ! -r "$d/product" ] ||
        description=$(cat "$d/product")

    label=$(printf '%s %s' "$manufacturer" "$description" |
        tr '[:upper:]' '[:lower:]')

    case "$label" in
        *mediatek*bt*|*foxconn*bt*|*bluetooth*)
            usb_count=$((usb_count + 1))
            usb_path=${d##*/}
            usb_vendor=$vendor
            usb_product=$product
            usb_label="$manufacturer $description"
            ;;
    esac
done

printf '\n===== BLUETOOTH USB =====\n'

if [ "$usb_count" -eq 1 ]; then
    printf 'Dispositivo: %s (%s)\n' "$usb_path" "$usb_label"
    printf 'ID rilevato: %s:%s\n' "$usb_vendor" "$usb_product"

    printf '\nRegola udev proposta (non installata):\n'
    cat <<EOF
SUBSYSTEM=="usb", ATTR{idVendor}=="$usb_vendor", ATTR{idProduct}=="$usb_product", RUN+="/bin/sh -c 'sleep 1 && echo $usb_vendor $usb_product > /sys/bus/usb/drivers/btusb/new_id'"
EOF
elif [ "$usb_count" -eq 0 ]; then
    printf 'Nessun dispositivo Bluetooth candidato riconosciuto.\n'
else
    printf 'ATTENZIONE: trovati %s dispositivi candidati; scelta automatica annullata.\n' "$usb_count"
fi

# Individua la scheda PCI tramite Vendor ID e Device ID.
for d in "$PCI_ROOT"/*; do
    [ -r "$d/vendor" ] || continue
    [ -r "$d/device" ] || continue

    [ "$(cat "$d/vendor")" = "0x14c3" ] || continue
    [ "$(cat "$d/device")" = "0x7630" ] || continue

    pci_count=$((pci_count + 1))
    pci_bdf=${d##*/}
    pci_driver="nessuno"

    if [ -L "$d/driver" ]; then
        pci_driver=$(basename "$(readlink -f "$d/driver")")
    fi
done

printf '\n===== WI-FI PCI =====\n'

if [ "$pci_count" -eq 1 ]; then
    printf 'Indirizzo PCI: %s\n' "$pci_bdf"
    printf 'ID PCI: 14c3:7630\n'
    printf 'Driver attuale: %s\n' "$pci_driver"
elif [ "$pci_count" -eq 0 ]; then
    printf 'Scheda MT7630E non trovata.\n'
else
    printf 'ATTENZIONE: trovate %s schede corrispondenti.\n' "$pci_count"
fi

printf '\n===== ESITO =====\n'
if [ "$usb_count" -eq 1 ] && [ "$pci_count" -eq 1 ]; then
    printf 'Rilevamento univoco completato.\n'
    printf 'Le regole sono solo proposte: nessuna configurazione è stata installata.\n'
else
    printf 'Rilevamento incompleto o ambiguo: non procedere all installazione automatica.\n'
fi
