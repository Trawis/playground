#!/usr/bin/env bash
# Behavioral tests for pve-ip-mount-retry that don't require a live
# Proxmox host or NAS. systemctl/findmnt/systemd-escape/mount/umount are
# all overridden as shell functions (which bash prefers over anything on
# PATH), so the real system is never touched.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/pve-ip-mount-retry"

pass=0
fail=0

ok()  { pass=$((pass + 1)); printf 'ok - %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf 'not ok - %s\n' "$*"; }

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        ok "$desc"
    else
        bad "$desc (expected [$expected], got [$actual])"
    fi
}

assert_match() {
    local desc="$1" pattern="$2" haystack="$3"
    if [[ "$haystack" == *"$pattern"* ]]; then
        ok "$desc"
    else
        bad "$desc (expected to find [$pattern] in output: $haystack)"
    fi
}

# --- Guard rails: this project must never shell out to mount/umount. ------
mount_calls=0
umount_calls=0
mount()  { mount_calls=$((mount_calls + 1)); return 1; }
umount() { umount_calls=$((umount_calls + 1)); return 1; }

# --- Controllable stand-ins for the systemd/findmnt world. -----------------
FINDMNT_M_SOURCE=""      # `findmnt -rn -M TARGET -o SOURCE` output
SYSTEMCTL_CAT_OK=1       # whether `systemctl cat UNIT` succeeds
SYSTEMCTL_IS_ACTIVE=""   # `systemctl is-active UNIT` output
RESET_FAILED_CALLS=0
START_CALLS=0

findmnt() {
    if [[ "$*" == *"-M"* ]]; then
        [[ -n "$FINDMNT_M_SOURCE" ]] && printf '%s\n' "$FINDMNT_M_SOURCE"
        [[ -n "$FINDMNT_M_SOURCE" ]]
        return
    fi
    return 1
}

systemd-escape() { printf 'stub.mount\n'; }

systemctl() {
    case "$1" in
        cat)          (( SYSTEMCTL_CAT_OK )) ;;
        is-active)    printf '%s\n' "$SYSTEMCTL_IS_ACTIVE"
                      [[ "$SYSTEMCTL_IS_ACTIVE" == "active" ]] ;;
        reset-failed) RESET_FAILED_CALLS=$((RESET_FAILED_CALLS + 1)); return 0 ;;
        start)        START_CALLS=$((START_CALLS + 1)); return 0 ;;
        *)            return 1 ;;
    esac
}

logger() { :; }
date() { printf '2026-01-01 00:00:00'; }

reset_stubs() {
    FINDMNT_M_SOURCE=""
    SYSTEMCTL_CAT_OK=1
    SYSTEMCTL_IS_ACTIVE=""
    RESET_FAILED_CALLS=0
    START_CALLS=0
    mount_calls=0
    umount_calls=0
    found=0 requested=0 waited=0 blocked=0
}

# shellcheck disable=SC1090
source "$SCRIPT"

# Run handle_entry directly in the current shell (not via `$(...)`, which
# would fork a subshell and silently drop the stub counters it increments)
# while still capturing its log output into $LAST_OUTPUT.
run_entry() {
    local tmp
    tmp="$(mktemp)"
    handle_entry "$@" >"$tmp" 2>&1
    LAST_OUTPUT="$(cat "$tmp")"
    rm -f "$tmp"
}

# --- 1. Discovery / classification -----------------------------------------

assert_eq "ignores a local path source" "" "$(extract_endpoint "/dev/sda1")"
assert_eq "ignores a hostname-only source" "" "$(extract_endpoint "nas.example.com:/export")"
assert_eq "recognizes an IPv4 CIFS source" "203.0.113.10" "$(extract_endpoint "//203.0.113.10/data")"
assert_eq "recognizes an IPv4 NFS source" "203.0.113.20" "$(extract_endpoint "203.0.113.20:/volume1/media")"
assert_eq "recognizes a bracketed IPv6 source" "[2001:db8::10]" "$(extract_endpoint "[2001:db8::10]:/export")"
assert_eq "extracts the full IP rather than a truncated prefix" \
    "203.0.113.241" "$(extract_endpoint "203.0.113.241:/x")"

reset_stubs
handle_entry "/dev/sda1" "/mnt/local" "ext4" >/dev/null 2>&1
assert_eq "a non-IP-backed entry is not counted as discovered" "0" "$found"
assert_eq "a non-IP-backed entry never touches findmnt/systemctl" "0" "$START_CALLS"

# --- 2. Already-mounted handling --------------------------------------------

reset_stubs
FINDMNT_M_SOURCE="203.0.113.10:/volume1/media"
run_entry "203.0.113.10:/volume1/media" "/mnt/media" "nfs"; out="$LAST_OUTPUT"
assert_eq "already mounted from the expected source: no start requested" "0" "$START_CALLS"
assert_match "already mounted from the expected source logs OK" "OK:" "$out"

reset_stubs
FINDMNT_M_SOURCE="198.51.100.5:/volume1/media"
run_entry "203.0.113.10:/volume1/media" "/mnt/media" "nfs"; out="$LAST_OUTPUT"
assert_eq "mounted from an unexpected source: no start requested" "0" "$START_CALLS"
assert_match "mounted from an unexpected source logs BLOCKED" "BLOCKED:" "$out"

# Regression test for the exact bug class this design avoids: a shorter
# configured address must never be treated as matching a longer mounted
# address it happens to be a substring of.
reset_stubs
FINDMNT_M_SOURCE="203.0.113.241:/volume1/media"
run_entry "203.0.113.24:/volume1/media" "/mnt/media" "nfs"; out="$LAST_OUTPUT"
assert_match "a prefix IP is not a substring false-positive match" "BLOCKED:" "$out"

# Regression tests for full source identity: comparing only the server
# endpoint (as an earlier version of this script did) would wrongly treat
# two different shares/exports on the same server as equivalent. The
# comparison must be against the complete source string.

# CIFS: same server + same share -> OK
reset_stubs
FINDMNT_M_SOURCE="//203.0.113.10/media"
run_entry "//203.0.113.10/media" "/mnt/media" "cifs"; out="$LAST_OUTPUT"
assert_match "CIFS: same IP + same share is OK" "OK:" "$out"

# CIFS: same server, different share -> BLOCKED
reset_stubs
FINDMNT_M_SOURCE="//203.0.113.10/backups"
run_entry "//203.0.113.10/media" "/mnt/media" "cifs"; out="$LAST_OUTPUT"
assert_match "CIFS: same IP + different share is BLOCKED" "BLOCKED:" "$out"

# CIFS: different server, same-looking share path -> BLOCKED
reset_stubs
FINDMNT_M_SOURCE="//203.0.113.11/media"
run_entry "//203.0.113.10/media" "/mnt/media" "cifs"; out="$LAST_OUTPUT"
assert_match "CIFS: different IP + same-looking path is BLOCKED" "BLOCKED:" "$out"

# NFS: same server + same export -> OK
reset_stubs
FINDMNT_M_SOURCE="203.0.113.20:/exports/media"
run_entry "203.0.113.20:/exports/media" "/mnt/media" "nfs"; out="$LAST_OUTPUT"
assert_match "NFS: same IP + same export is OK" "OK:" "$out"

# NFS: same server, different export -> BLOCKED
reset_stubs
FINDMNT_M_SOURCE="203.0.113.20:/exports/backups"
run_entry "203.0.113.20:/exports/media" "/mnt/media" "nfs"; out="$LAST_OUTPUT"
assert_match "NFS: same IP + different export is BLOCKED" "BLOCKED:" "$out"

# NFS: different server, same-looking export path -> BLOCKED
reset_stubs
FINDMNT_M_SOURCE="203.0.113.21:/exports/media"
run_entry "203.0.113.20:/exports/media" "/mnt/media" "nfs"; out="$LAST_OUTPUT"
assert_match "NFS: different IP + same export is BLOCKED" "BLOCKED:" "$out"

# An unrelated local filesystem occupying the target -> BLOCKED, not OK.
reset_stubs
FINDMNT_M_SOURCE="/dev/sdb1"
run_entry "203.0.113.20:/exports/media" "/mnt/media" "nfs"; out="$LAST_OUTPUT"
assert_match "an unrelated local filesystem at the target is BLOCKED" "BLOCKED:" "$out"

# --- 3. Missing mount handling -----------------------------------------------

reset_stubs
SYSTEMCTL_IS_ACTIVE="activating"
run_entry "203.0.113.10:/volume1/media" "/mnt/media" "nfs"; out="$LAST_OUTPUT"
assert_eq "an already-activating unit is not reset" "0" "$RESET_FAILED_CALLS"
assert_eq "an already-activating unit is not restarted" "0" "$START_CALLS"
assert_match "an already-activating unit logs WAIT" "WAIT:" "$out"

reset_stubs
SYSTEMCTL_IS_ACTIVE="failed"
run_entry "203.0.113.10:/volume1/media" "/mnt/media" "nfs"; out="$LAST_OUTPUT"
assert_eq "a failed unit has reset-failed called once" "1" "$RESET_FAILED_CALLS"
assert_eq "a failed unit is retried once" "1" "$START_CALLS"
assert_match "a retried unit logs RETRY" "RETRY:" "$out"

reset_stubs
SYSTEMCTL_CAT_OK=0
run_entry "203.0.113.10:/volume1/media" "/mnt/media" "nfs"; out="$LAST_OUTPUT"
assert_eq "a target with no generated unit is never started" "0" "$START_CALLS"
assert_match "a target with no generated unit logs WARN" "WARN:" "$out"

# --- 4. Never shells out to mount/umount ------------------------------------

assert_eq "mount(1) is never invoked by any test above" "0" "$mount_calls"
assert_eq "umount(1) is never invoked by any test above" "0" "$umount_calls"

# Static backstop: mount/umount never appear as the first token of a
# command (start of line, or after a command separator). This is narrower
# than a bare word match on purpose - the script's own comments/log text
# legitimately say things like "mount unit" and "--suffix=mount".
if grep -Eq '(^|[;&|]|\$\()[[:space:]]*(mount|umount)([[:space:]]|$)' "$SCRIPT"; then
    bad "the script source contains no direct mount/umount command invocations"
else
    ok "the script source contains no direct mount/umount command invocations"
fi

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
