#!/bin/sh
# IL TUO FIX WI-FI ORIGINALE E FUNZIONANTE - NON MODIFICARE

PCI_ID="0000:03:00.0"

case $1 in
    pre)
        echo "Rimozione driver Wi-Fi originale..."
        /sbin/modprobe -r mt76x0e mt76x02_lib mt76x0_common mt76

        if [ -e "/sys/bus/pci/devices/$PCI_ID/remove" ]; then
            echo 1 > "/sys/bus/pci/devices/$PCI_ID/remove"
        fi
        ;;
    post)
        sleep 2
        echo "Forzatura risonoscimento bus PCIe..."
        echo 1 > /sys/bus/pci/rescan

        sleep 2
        echo "Ricaricamento driver Wi-Fi..."
        /sbin/modprobe mt76x0e

        # AUTOMAZIONE BLUETOOTH: Chiamiamo lo script locale in differita
        # Il simbolo '&' lo lancia in background senza bloccare il ripristino dello schermo
        /etc/local.d/99-mt7630e-bluetooth.start &
        ;;
esac
