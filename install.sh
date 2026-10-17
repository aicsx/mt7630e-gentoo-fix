#!/bin/bash
# MT7630E Gentoo Fix - installer candidato con rilevamento dinamico.
# Non modifica GRUB o /etc/conf.d/modules.
# Eseguire solo dopo aver controllato questo file.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$SCRIPT_DIR/build/etc" ]]; then
    ROOT="$SCRIPT_DIR"
else
    ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
fi
BUILD="$ROOT/build"
USB_ROOT="/sys/bus/usb/devices"
PCI_ROOT="/sys/bus/pci/devices"

die() {
    printf 'ERRORE: %s\n' "$*" >&2
    exit 1
}

info() {
    printf '[+] %s\n' "$*"
}

usage() {
    cat <<'EOF'
Uso:
  sudo ./build/install.sh
  ./build/install.sh --check
  ./build/install.sh --help

Il rilevamento hardware precede qualsiasi modifica al sistema.
I file sostituiti vengono salvati in /root/mt7630e-fix-backup-DATA-ORA.
GRUB e /etc/conf.d/modules non vengono modificati.
EOF
}

CHECK_ONLY=false
case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --check) CHECK_ONLY=true ;;
    "") ;;
    *) usage >&2; exit 2 ;;
esac


if [[ "$CHECK_ONLY" != true && $EUID -ne 0 ]]; then
    die "eseguire con sudo: sudo ./build/install.sh"
fi

# Controlla le dipendenze prima di qualsiasi modifica al sistema.
for cmd in bash sh sed install mktemp cp date grep tr udevadm cmp readlink mkdir rm flock; do
    command -v "$cmd" >/dev/null 2>&1 || die "comando richiesto non trovato: $cmd"
done

command -v rc-update >/dev/null 2>&1 || die "rc-update non trovato"

# Verifica tutti i sorgenti prima di rilevare l'hardware.
RULE_TEMPLATE="$BUILD/etc/udev/rules.d/99-mt7630e-bluetooth.rules.in"
BT_SCRIPT="$BUILD/etc/local.d/99-mt7630e-bluetooth.start"
SLEEP_HOOK="$BUILD/lib/elogind/system-sleep/40-mediatek-wifi.sh"

for f in "$RULE_TEMPLATE" "$BT_SCRIPT" "$SLEEP_HOOK"; do
    [[ -f "$f" ]] || die "file candidato mancante: $f"
done

bash -n "$BT_SCRIPT" || die "errore di sintassi nello script Bluetooth"
sh -n "$SLEEP_HOOK" || die "errore di sintassi nell'hook elogind"

# Individua un dispositivo USB Bluetooth.
# Preferisce le interfacce USB Bluetooth standard; usa i descrittori
# MediaTek/Foxconn/Bluetooth come fallback per i dispositivi proprietari.
usb_count=0
USB_VENDOR=""
USB_PRODUCT=""
USB_DEVICE=""
USB_LABEL=""

for d in "$USB_ROOT"/*; do
    [[ -r "$d/idVendor" && -r "$d/idProduct" ]] || continue

    vendor="$(<"$d/idVendor")"
    product="$(<"$d/idProduct")"
    manufacturer=""
    description=""

    [[ ! -r "$d/manufacturer" ]] || manufacturer="$(<"$d/manufacturer")"
    [[ ! -r "$d/product" ]] || description="$(<"$d/product")"

    label="$(printf '%s %s' "$manufacturer" "$description" |
        tr '[:upper:]' '[:lower:]')"

    is_bluetooth=false

    # Interfaccia USB Bluetooth standard: classe e0, sottoclasse 01.
    for iface in "$d":*; do
        [[ -r "$iface/bInterfaceClass" ]] || continue
        iface_class="$(<"$iface/bInterfaceClass")"
        iface_subclass=""
        [[ ! -r "$iface/bInterfaceSubClass" ]] ||
            iface_subclass="$(<"$iface/bInterfaceSubClass")"

        if [[ "${iface_class,,}" == "e0" &&
              "${iface_subclass,,}" == "01" ]]; then
            is_bluetooth=true
            break
        fi
    done

    # Fallback per il dispositivo MediaTek/Foxconn con descrittori noti.
    if [[ "$is_bluetooth" == false ]]; then
        case "$label" in
            *mediatek*bt*|*foxconn*bt*|*bluetooth*)
                is_bluetooth=true
                ;;
        esac
    fi

    [[ "$is_bluetooth" == true ]] || continue

    ((usb_count += 1))
    USB_VENDOR="$vendor"
    USB_PRODUCT="$product"
    USB_DEVICE="${d##*/}"
    USB_LABEL="$manufacturer $description"
done

[[ "$usb_count" -eq 1 ]] ||
    die "rilevamento Bluetooth assente o ambiguo: $usb_count dispositivi candidati; nessun file installato"

# I valori provengono da sysfs e devono essere ID esadecimali.
[[ "$USB_VENDOR" =~ ^[[:xdigit:]]{4}$ ]] ||
    die "idVendor USB non valido: $USB_VENDOR"
[[ "$USB_PRODUCT" =~ ^[[:xdigit:]]{4}$ ]] ||
    die "idProduct USB non valido: $USB_PRODUCT"

# Individua in modo univoco la scheda Wi-Fi MediaTek MT7630E.
pci_count=0
PCI_BDF=""

for d in "$PCI_ROOT"/*; do
    [[ -r "$d/vendor" && -r "$d/device" ]] || continue
    [[ "$(<"$d/vendor")" == "0x14c3" ]] || continue
    [[ "$(<"$d/device")" == "0x7630" ]] || continue

    ((pci_count += 1))
    PCI_BDF="${d##*/}"
done

[[ "$pci_count" -eq 1 ]] ||
    die "scheda PCI 14c3:7630 assente o ambigua: $pci_count dispositivi; nessun file installato"

info "Bluetooth rilevato: $USB_DEVICE ($USB_LABEL)"
info "ID USB: $USB_VENDOR:$USB_PRODUCT"
info "Wi-Fi PCI: $PCI_BDF (14c3:7630)"
info "Controlli hardware superati."
if [[ "$CHECK_ONLY" == true ]]; then
    printf "\nVerifica completata: nessuna modifica al sistema eseguita.\n"
    printf "Bluetooth USB: %s:%s (%s)\n" "$USB_VENDOR" "$USB_PRODUCT" "$USB_DEVICE"
    printf "Wi-Fi PCI: %s\n" "$PCI_BDF"
    exit 0
fi


# Destinazione dell'hook: preferisci /usr/lib se già presente.
if [[ -d /usr/lib/elogind/system-sleep ]]; then
    HOOK_DIR="/usr/lib/elogind/system-sleep"
elif [[ -d /lib/elogind/system-sleep ]]; then
    HOOK_DIR="/lib/elogind/system-sleep"
else
    die "directory elogind system-sleep non trovata"
fi

RULE_DIR="/etc/udev/rules.d"
LOCAL_DIR="/etc/local.d"

# Prepara tutto in una directory temporanea PRIMA di toccare i file installati.
STAGE="$(mktemp -d)"
cleanup() {
    rm -rf -- "$STAGE"
}
trap cleanup EXIT

sed -e "s/@USB_VENDOR@/$USB_VENDOR/g" -e "s/@USB_PRODUCT@/$USB_PRODUCT/g" "$RULE_TEMPLATE" > "$STAGE/99-mt7630e-bluetooth.rules" ||
    die "impossibile preparare la regola udev"

if grep -Eq "@USB_VENDOR@|@USB_PRODUCT@" "$STAGE/99-mt7630e-bluetooth.rules"; then
    die "la regola udev contiene ancora segnaposto non sostituiti"
fi
grep -Fq "ATTR{idVendor}==\"$USB_VENDOR\"" "$STAGE/99-mt7630e-bluetooth.rules" || die "ID vendor assente dalla regola udev"
grep -Fq "ATTR{idProduct}==\"$USB_PRODUCT\"" "$STAGE/99-mt7630e-bluetooth.rules" || die "ID product assente dalla regola udev"

install -m 0755 "$BT_SCRIPT" "$STAGE/99-mt7630e-bluetooth.start"
install -m 0755 "$SLEEP_HOOK" "$STAGE/40-mediatek-wifi.sh"

# Controlla la regola generata e gli script prima dell'installazione.

# Backup verificato prima di qualsiasi sostituzione.
RULE_DEST="$RULE_DIR/99-mt7630e-bluetooth.rules"
LOCAL_DEST="$LOCAL_DIR/99-mt7630e-bluetooth.start"
HOOK_DEST="$HOOK_DIR/40-mediatek-wifi.sh"

HAD_RULE=false
HAD_LOCAL=false
HAD_HOOK=false
LOCAL_WAS_ENABLED=false
BLUETOOTH_WAS_ENABLED=false

[[ -e "$RULE_DEST" || -L "$RULE_DEST" ]] && HAD_RULE=true
[[ -e "$LOCAL_DEST" || -L "$LOCAL_DEST" ]] && HAD_LOCAL=true
[[ -e "$HOOK_DEST" || -L "$HOOK_DEST" ]] && HAD_HOOK=true
[[ -e /etc/runlevels/default/local || -L /etc/runlevels/default/local ]] &&
    LOCAL_WAS_ENABLED=true
[[ -e /etc/runlevels/default/bluetooth || -L /etc/runlevels/default/bluetooth ]] &&
    BLUETOOTH_WAS_ENABLED=true

BACKUP="$(mktemp -d "/root/mt7630e-fix-backup-$(date +%Y%m%d-%H%M%S)-XXXXXX")" ||
    die "impossibile creare il backup in /root"

backup_file() {
    local src="$1" rel="$2" dst
    dst="$BACKUP/$rel"

    if [[ -e "$src" || -L "$src" ]]; then
        mkdir -p "$(dirname "$dst")" ||
            die "impossibile preparare il backup di $src"
        cp -a -- "$src" "$dst" ||
            die "backup fallito per $src"

        if [[ -L "$src" ]]; then
            [[ -L "$dst" ]] &&
            [[ "$(readlink "$src")" == "$(readlink "$dst")" ]] ||
                die "verifica del backup fallita per $src"
        else
            [[ -f "$dst" ]] && cmp -s -- "$src" "$dst" ||
                die "verifica del backup fallita per $src"
        fi
    fi
}

backup_file "$RULE_DEST" "etc/udev/rules.d/99-mt7630e-bluetooth.rules"
backup_file "$LOCAL_DEST" "etc/local.d/99-mt7630e-bluetooth.start"
backup_file "$HOOK_DEST" "${HOOK_DIR#/}/40-mediatek-wifi.sh"

restore_file() {
    local dest="$1" saved="$2" existed="$3"

    if [[ "$existed" == true ]]; then
        if [[ ! -e "$saved" && ! -L "$saved" ]]; then
            printf 'ATTENZIONE: backup mancante per %s\n' "$dest" >&2
            return 1
        fi

        if ! rm -f -- "$dest"; then
            printf 'ATTENZIONE: impossibile rimuovere la destinazione %s\n' "$dest" >&2
            return 1
        fi

        if ! cp -a -- "$saved" "$dest"; then
            printf 'ATTENZIONE: copia di ripristino fallita per %s\n' "$dest" >&2
            return 1
        fi

        if [[ -L "$saved" ]]; then
            if [[ ! -L "$dest" ]] ||
               [[ "$(readlink -- "$saved")" != "$(readlink -- "$dest")" ]]; then
                printf 'ATTENZIONE: verifica del collegamento simbolico fallita per %s\n' "$dest" >&2
                return 1
            fi
        else
            if [[ ! -f "$dest" ]] || ! cmp -s -- "$saved" "$dest"; then
                printf 'ATTENZIONE: verifica del contenuto ripristinato fallita per %s\n' "$dest" >&2
                return 1
            fi
        fi
    else
        if ! rm -f -- "$dest"; then
            printf 'ATTENZIONE: impossibile rimuovere il file creato durante l’installazione: %s\n' "$dest" >&2
            return 1
        fi

        if [[ -e "$dest" || -L "$dest" ]]; then
            printf 'ATTENZIONE: la destinazione esiste ancora dopo la rimozione: %s\n' "$dest" >&2
            return 1
        fi
    fi

    return 0
}
TX_ACTIVE=false

rollback() {
    local status="$1"
    local rollback_failed=0

    set +e

    printf '\nATTENZIONE: errore durante l’installazione; avvio rollback.\n' >&2

    if ! restore_file "$RULE_DEST" \
        "$BACKUP/etc/udev/rules.d/99-mt7630e-bluetooth.rules" "$HAD_RULE"; then
        printf 'ATTENZIONE: ripristino fallito: %s\n' "$RULE_DEST" >&2
        rollback_failed=1
    fi

    if ! restore_file "$LOCAL_DEST" \
        "$BACKUP/etc/local.d/99-mt7630e-bluetooth.start" "$HAD_LOCAL"; then
        printf 'ATTENZIONE: ripristino fallito: %s\n' "$LOCAL_DEST" >&2
        rollback_failed=1
    fi

    if ! restore_file "$HOOK_DEST" \
        "$BACKUP/${HOOK_DIR#/}/40-mediatek-wifi.sh" "$HAD_HOOK"; then
        printf 'ATTENZIONE: ripristino fallito: %s\n' "$HOOK_DEST" >&2
        rollback_failed=1
    fi

    if [[ "$LOCAL_WAS_ENABLED" != true ]] &&
       { [[ -e /etc/runlevels/default/local ]] ||
         [[ -L /etc/runlevels/default/local ]]; }; then
        if ! rc-update del local default >/dev/null 2>&1; then
            printf 'ATTENZIONE: impossibile disabilitare local durante il rollback.\n' >&2
            rollback_failed=1
        fi
    fi

    if [[ "$BLUETOOTH_WAS_ENABLED" != true ]] &&
       { [[ -e /etc/runlevels/default/bluetooth ]] ||
         [[ -L /etc/runlevels/default/bluetooth ]]; }; then
        if ! rc-update del bluetooth default >/dev/null 2>&1; then
            printf 'ATTENZIONE: impossibile disabilitare bluetooth durante il rollback.\n' >&2
            rollback_failed=1
        fi
    fi

    if command -v udevadm >/dev/null 2>&1; then
        if ! udevadm control --reload-rules >/dev/null 2>&1; then
            printf 'ATTENZIONE: ricaricamento delle regole udev fallito.\n' >&2
            rollback_failed=1
        fi
    fi

    TX_ACTIVE=false

    if [[ "$rollback_failed" -eq 0 ]]; then
        printf 'Rollback completato senza errori rilevati.\n' >&2
    else
        printf 'ATTENZIONE: ROLLBACK INCOMPLETO. Controllare i file e i servizi segnalati.\n' >&2
    fi

    printf 'Backup disponibile in: %s\n' "$BACKUP" >&2
    return "$status"
}
handle_exit() {
    local original_status=$?
    trap - EXIT

    if [[ "$TX_ACTIVE" == true ]]; then
        rollback "$original_status"
    fi

    cleanup
    exit "$original_status"
}
trap handle_exit EXIT

mkdir -p "$RULE_DIR" "$LOCAL_DIR" "$HOOK_DIR" ||
    die "impossibile preparare le directory di destinazione"

# Da questo punto ogni errore attiva il ripristino.
TX_ACTIVE=true

install -m 0644 "$STAGE/99-mt7630e-bluetooth.rules" "$RULE_DEST" ||
    die "installazione della regola udev fallita"
install -m 0755 "$STAGE/99-mt7630e-bluetooth.start" "$LOCAL_DEST" ||
    die "installazione dello script Bluetooth fallita"
install -m 0755 "$STAGE/40-mediatek-wifi.sh" "$HOOK_DEST" ||
    die "installazione dell'hook di sospensione fallita"

if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules || die "ricaricamento delle regole udev fallito"
fi

rc-update add local default ||
    die "impossibile abilitare local"
rc-update add bluetooth default ||
    die "impossibile abilitare bluetooth"

# Commit: da qui il trap non deve più ripristinare i file.
TX_ACTIVE=false
info "File installati. Backup verificato: $BACKUP"

printf '\nInstallazione completata.\n'
printf 'Bluetooth USB: %s:%s\n' "$USB_VENDOR" "$USB_PRODUCT"
printf 'Wi-Fi PCI:     %s\n' "$PCI_BDF"
printf 'Backup:        %s\n' "$BACKUP"
printf 'GRUB e /etc/conf.d/modules non sono stati modificati.\n'
printf 'Non è stato ricaricato alcun modulo né eseguito un test di sospensione.\n'
