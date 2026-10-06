#!/bin/bash
# Maintainer: ax - ax@slackware.eu
# IRC: irc1.slacware.eu #lug
# SLK: UmbrellaNet
# Target: Asus X555LA (i3 Core) - MediaTek MT7630E Combo Card Fix

if [ "\$EUID" -ne 0 ]; then
  echo "Errore: Esegui questo script come root (sudo ./install.sh)"
  exit 1
fi

echo "=== Inizio installazione del modulo Fix MT7630E ==="

echo "[+] Copia della regola udev..."
cp etc/udev/rules.d/99-mt7630e-bluetooth.rules /etc/udev/rules.d/
chmod 644 /etc/udev/rules.d/99-mt7630e-bluetooth.rules

echo "[+] Copia dello script locale in local.d..."
cp etc/local.d/99-mt7630e-bluetooth.start /etc/local.d/
chmod +x /etc/local.d/99-mt7630e-bluetooth.start

echo "[+] Copia dell'hook di sospensione per elogind..."
cp lib/elogind/system-sleep/40-mediatek-wifi.sh /lib/elogind/system-sleep/
chmod +x /lib/elogind/system-sleep/40-mediatek-wifi.sh

echo "[+] Verifica e configurazione di /etc/conf.d/modules..."
if ! grep -q "btusb" /etc/conf.d/modules 2>/dev/null; then
    if grep -q "modules=" /etc/conf.d/modules 2>/dev/null; then
        sed -i 's/modules="\(.*\)"/modules="\1 btusb"/' /etc/conf.d/modules
    else
        echo 'modules="btusb"' >> /etc/conf.d/modules
    fi
    echo "    -> Modulo 'btusb' aggiunto all'avvio."
else
    echo "    -> Il modulo 'btusb' è già presente in /etc/conf.d/modules."
fi

echo "[+] Abilitazione servizi OpenRC..."
rc-update add local default >/dev/null 2>&1
rc-update add bluetooth default >/dev/null 2>&1

echo ""
echo "=== ATTENZIONE: PASSO MANUALE RICHIESTO PER GRUB ==="
echo "Assicurati che /etc/default/grub contenga i seguenti parametri energetici:"
echo 'GRUB_CMDLINE_LINUX_DEFAULT="... pcie_aspm=off intel_iommu=off"'
echo "Dopo aver modificato il file, rigenera GRUB con:"
echo "sudo grub-mkconfig -o /boot/grub/grub.cfg"
echo "===================================================="
echo "Installazione completata con successo. Riavvia la macchina."
