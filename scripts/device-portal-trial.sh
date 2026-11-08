#!/bin/sh
# Run only on the verified module, after copying the ISO into /tmp.
# Read-only by default. A trial restores the original USB composition after 90 s.
set -eu
base=/sys/class/android_usb/android0
image=/tmp/LTEModemCompact-Install-Portal.iso
case "$(uname -r)" in 3.18.44) ;; *) echo 'Unverified kernel'; exit 1;; esac
original=$(cat "$base/functions")
case "$original" in diag,serial,ecm,ffs) ;; *) echo 'Unverified USB composition'; exit 1;; esac
[ "$(cat "$base/idVendor")" = '2ca3' ] || exit 1
[ "$(cat "$base/idProduct")" = '4006' ] || exit 1
[ "$(cat "$base/enable")" = 1 ] || exit 1
[ -f "$image" ] && [ ! -L "$image" ] || exit 1
[ -w "$base/f_mass_storage/lun/file" ] && [ -w "$base/f_mass_storage/lun/ro" ] || exit 1
[ -z "$(cat "$base/f_mass_storage/lun/file")" ] || { echo 'Storage backing already in use'; exit 1; }
expected=${2:-}
case "$expected" in *[!0-9a-f]*|'') echo 'Expected SHA-256 required'; exit 1;; esac
[ "${#expected}" = 64 ] || exit 1
actual=$(sha256sum "$image"); actual=${actual%% *}
[ "$actual" = "$expected" ] || { echo 'Image checksum mismatch'; exit 1; }
if [ "${1:-}" != --apply-temporary ]; then echo 'Preflight passed; no changes made'; exit 0; fi
# Private, fixed marker prevents overlapping trials. No rootfs writes.
state=/tmp/ltemodem-portal-trial
mkdir "$state" || exit 1
chmod 700 "$state"
old_ro=$(cat "$base/f_mass_storage/lun/ro")
printf '%s\n' "$original" > "$state/original-functions"
printf '%s\n' "$old_ro" > "$state/original-ro"
restore() {
    trap - EXIT HUP INT TERM
    set +e
    echo 0 > "$base/enable"
    sleep 2
    printf '%s' "$original" > "$base/functions"
    printf '\n' > "$base/f_mass_storage/lun/file"
    printf '%s' "$old_ro" > "$base/f_mass_storage/lun/ro"
    echo 1 > "$base/enable"
    if [ "$(cat "$base/functions")" = "$original" ] && [ "$(cat "$base/enable")" = 1 ]; then
        echo restored > "$state/result"
    else
        echo restore-needs-replug > "$state/result"
    fi
}
trap restore EXIT HUP INT TERM
# This process must be launched through nohup/setsid before USB disconnects.
echo 0 > "$base/enable"
sleep 2
echo 1 > "$base/f_mass_storage/lun/ro"
printf '%s' "$image" > "$base/f_mass_storage/lun/file"
printf '%s' "$original,mass_storage" > "$base/functions"
echo 1 > "$base/enable"
echo active > "$state/result"
sleep 90
