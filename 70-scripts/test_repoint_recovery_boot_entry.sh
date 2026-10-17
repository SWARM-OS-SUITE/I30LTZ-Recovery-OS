#!/usr/bin/env bash
# Tests repoint_recovery_boot_entry.sh against a stub efibootmgr seeded with the REAL entries from the 2026-10-10 preflight.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*"; exit 1; }; ok() { echo "ok   $*"; }
mkdir -p "$T/esp/EFI/i30ltz"; : > "$T/esp/EFI/i30ltz/shimx64.efi"
cat > "$T/state" <<'EOS'
BootCurrent: 0003
Timeout: 2 seconds
BootOrder: 0003,0000,0004,0005,0001
Boot0000* SWARM_OS	HD(1,GPT,41cd2e0e-92fe-4300-9d8d-f37ad7f486d7,0x800,0x41a000)/File(\EFI\SWARM_OS\grubx64.efi)
Boot0001* I30LTZ Recovery OS	HD(1,GPT,e25e5715-f3b8-4ddb-9796-d1c270804140,0x800,0x200000)/File(\EFI\i30ltz\grubx64.efi)
Boot0003* debian	HD(1,GPT,c2da7f22-db73-4cc3-b73f-6446fa6aad3d,0x800,0x219800)/File(\EFI\debian\shimx64.efi)
Boot0004* Ubuntu	HD(1,GPT,c2da7f22-db73-4cc3-b73f-6446fa6aad3d,0x800,0x219800)/File(\EFI\ubuntu\shimx64.efi)
Boot0005* Fedora	HD(1,GPT,c2da7f22-db73-4cc3-b73f-6446fa6aad3d,0x800,0x219800)/File(\EFI\fedora\shimx64.efi)
EOS
# stub: -v prints the state; -c adds a FIRST-in-order entry; -o sets order; -b N -B deletes. Logs every call.
cat > "$T/efibootmgr" <<'EOS'
#!/usr/bin/env bash
S=$(dirname "$0")/state; echo "$*" >> "$(dirname "$0")/calls"
case "$1" in
  -v|"") cat "$S" ;;
  -c) lbl="" ld=""; shift; while [[ $# -gt 0 ]]; do case $1 in -L) lbl=$2; shift 2;; -l) ld=$2; shift 2;; *) shift 2;; esac; done
      n=0006; printf 'Boot%s* %s\tHD(1,GPT,e25e5715-f3b8-4ddb-9796-d1c270804140,0x800,0x200000)/File(%s)\n' "$n" "$lbl" "$ld" >> "$S"
      sed -i "s/^BootOrder: /BootOrder: $n,/" "$S"; cat "$S" ;;
  -o) sed -i "s/^BootOrder: .*/BootOrder: $2/" "$S" ;;
  -b) sed -i "/^Boot$2/d" "$S"; sed -i "s/^\(BootOrder: .*\)\b$2,\?/\1/;s/,\$//" "$S" ;;
esac
EOS
chmod +x "$T/efibootmgr"
run() { EFIBOOTMGR="$T/efibootmgr" ESP_ROOT_OVERRIDE="$T/esp" bash "$HERE/repoint_recovery_boot_entry.sh" "$@"; }

# the script also needs /sys/firmware/efi to exist; skip the whole test on a BIOS-booted machine
[[ -d /sys/firmware/efi ]] || { echo "skip: not a UEFI machine"; exit 0; }

out=$(run); [[ $out == *"Boot0001"* && $out == *"grubx64.efi"* ]] || fail "should read the real entry: $out"
[[ $out == *"[dry-run]"* ]] || fail "should say it is a dry run"
! grep -qE '^(-c|-o|-b) ' "$T/calls" || fail "dry run must not write to the firmware: $(cat "$T/calls")"
[[ $(grep -c . "$T/state") == 8 ]] || fail "dry run changed the firmware state"; ok "dry run shows the plan and changes nothing"

run --apply >/dev/null
grep -q 'I30LTZ Recovery OS.*shimx64.efi' "$T/state" || fail "new entry should point at the shim"
grep -q 'Boot0001' "$T/state" && fail "old entry should be gone"
grep -q '^BootOrder: 0003,0000,0004,0005,0006$' "$T/state" || fail "the new entry should take the old one's place: $(grep BootOrder "$T/state")"
grep -q 'Boot0003\* debian' "$T/state" && grep -q 'Boot0000\* SWARM_OS' "$T/state" || fail "other entries must be untouched"
ok "apply: new entry uses the shim, takes the old slot in BootOrder, old entry removed, others untouched"

before=$(cat "$T/state"); calls=$(wc -l < "$T/calls")
out=$(run --apply); [[ $out == *"nothing to do"* ]] || fail "second run should do nothing: $out"
[[ $(cat "$T/state") == "$before" ]] || fail "second run changed state"; ok "idempotent: running it again does nothing"

rm "$T/esp/EFI/i30ltz/shimx64.efi"
sed -i 's/shimx64.efi)/grubx64.efi)/' "$T/state"; sed -i 's/^Boot0003\*.*grubx64/Boot0003* debian\tHD(1,GPT,x,0x800,0x1)\/File(\\EFI\\debian\\shimx64/' "$T/state"
out=$(run --apply 2>&1 || true); [[ $out == *"no EFI/i30ltz/shimx64.efi"* ]] || fail "should refuse when there is no shim to point at: $out"; ok "refuses (and changes nothing) when the shim is not on the EFI partition"
echo "ALL OK"
