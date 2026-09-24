#!/usr/bin/env bash
# Behavioral tests for pve-ip-mount-gate that don't require a live Proxmox
# host or NAS. findmnt/timeout/pct are overridden as shell functions (which
# bash prefers over anything on PATH); STATE_DIR/RUNTIME_DIR/MOUNT_DB/
# PENDING_FILE/LOCK_FILE are redirected into a throwaway temp directory
# before any function that touches disk is called, so nothing here reads
# or writes real system state.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/pve-ip-mount-gate"

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
        bad "$desc (expected to find [$pattern] in: $haystack)"
    fi
}

assert_true() {
    local desc="$1"; shift
    if "$@"; then ok "$desc"; else bad "$desc"; fi
}

assert_false() {
    local desc="$1"; shift
    if "$@"; then bad "$desc"; else ok "$desc"; fi
}

# --- Guard rails: this project must never shell out to mount/umount. ------
mount_calls=0
umount_calls=0
mount()  { mount_calls=$((mount_calls + 1)); return 1; }
umount() { umount_calls=$((umount_calls + 1)); return 1; }

# --- findmnt stub ------------------------------------------------------------
# FSTAB_FIXTURE / CUSTOM_LIVE_FIXTURE: newline-separated "TARGET SOURCE
# FSTYPE" rows, standing in for `findmnt --fstab ...` and the plain live
# mount table query, respectively.
# FINDMNT_ACTUAL[target]: live SOURCE for an exact -M mountpoint lookup;
# unset/empty means "not mounted".
FSTAB_FIXTURE=""
CUSTOM_LIVE_FIXTURE=""
declare -A FINDMNT_ACTUAL

findmnt() {
    local args=" $* "
    if [[ "$args" == *" -M "* ]]; then
        local target="" prev=""
        for a in "$@"; do
            [[ "$prev" == "-M" ]] && target="$a"
            prev="$a"
        done
        local src="${FINDMNT_ACTUAL[$target]:-}"
        [[ -n "$src" ]] && printf '%s\n' "$src"
        [[ -n "$src" ]]
        return
    fi
    if [[ "$args" == *" --fstab "* ]]; then
        [[ -n "$FSTAB_FIXTURE" ]] && printf '%s\n' "$FSTAB_FIXTURE"
        return 0
    fi
    [[ -n "$CUSTOM_LIVE_FIXTURE" ]] && printf '%s\n' "$CUSTOM_LIVE_FIXTURE"
    return 0
}

# --- timeout stub (stands in for the bounded `stat` I/O check) -------------
# TIMEOUT_FAIL_TARGETS: space-separated targets whose responsiveness check
# should fail.
TIMEOUT_FAIL_TARGETS=""
timeout() {
    local target="${*: -1}"
    local t
    for t in $TIMEOUT_FAIL_TARGETS; do
        [[ "$t" == "$target" ]] && return 1
    done
    return 0
}

# --- pct stub: a minimal in-memory fake Proxmox CT inventory ---------------
declare -A PCT_KNOWN PCT_ONBOOT PCT_TAGS PCT_HOSTNAME PCT_MPS PCT_STATUS
PCT_START_CALLS=0
PCT_SET_TAGS_CALLS=0
PCT_SET_ONBOOT_CALLS=0
PCT_START_RESULT=0

# pct_define CTID ONBOOT TAGS HOSTNAME STATUS "mp0-line;mp1-line"
pct_define() {
    local id="$1"
    PCT_KNOWN[$id]=1
    PCT_ONBOOT[$id]="$2"
    PCT_TAGS[$id]="$3"
    PCT_HOSTNAME[$id]="$4"
    PCT_STATUS[$id]="$5"
    PCT_MPS[$id]="${6:-}"
}

render_pct_config() {
    local id="$1"
    [[ -n "${PCT_KNOWN[$id]:-}" ]] || return 1
    printf 'onboot: %s\n' "${PCT_ONBOOT[$id]}"
    printf 'hostname: %s\n' "${PCT_HOSTNAME[$id]}"
    [[ -n "${PCT_TAGS[$id]:-}" ]] && printf 'tags: %s\n' "${PCT_TAGS[$id]}"
    if [[ -n "${PCT_MPS[$id]:-}" ]]; then
        local IFS=';' line
        for line in ${PCT_MPS[$id]}; do
            printf '%s\n' "$line"
        done
    fi
}

pct() {
    case "$1" in
        list)
            printf 'VMID STATUS NAME\n'
            local id
            for id in "${!PCT_KNOWN[@]}"; do
                printf '%s %s ct%s\n' "$id" "${PCT_STATUS[$id]:-stopped}" "$id"
            done
            ;;
        config)
            render_pct_config "$2"
            ;;
        status)
            [[ -n "${PCT_KNOWN[$2]:-}" ]] || return 1
            printf 'status: %s\n' "${PCT_STATUS[$2]:-stopped}"
            ;;
        start)
            PCT_START_CALLS=$((PCT_START_CALLS + 1))
            [[ -n "${PCT_KNOWN[$2]:-}" ]] || return 1
            PCT_STATUS[$2]="running"
            return "$PCT_START_RESULT"
            ;;
        set)
            local id="$2"; shift 2
            while (( $# )); do
                case "$1" in
                    --tags)
                        PCT_TAGS[$id]="$2"
                        PCT_SET_TAGS_CALLS=$((PCT_SET_TAGS_CALLS + 1))
                        shift 2 ;;
                    --onboot)
                        PCT_ONBOOT[$id]="$2"
                        PCT_SET_ONBOOT_CALLS=$((PCT_SET_ONBOOT_CALLS + 1))
                        shift 2 ;;
                    --delete)
                        [[ "$2" == "tags" ]] && PCT_TAGS[$id]=""
                        shift 2 ;;
                    *) shift ;;
                esac
            done
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

reset_stubs() {
    FSTAB_FIXTURE=""
    CUSTOM_LIVE_FIXTURE=""
    FINDMNT_ACTUAL=()
    TIMEOUT_FAIL_TARGETS=""
    PCT_KNOWN=(); PCT_ONBOOT=(); PCT_TAGS=(); PCT_HOSTNAME=(); PCT_MPS=(); PCT_STATUS=()
    PCT_START_CALLS=0
    PCT_SET_TAGS_CALLS=0
    PCT_SET_ONBOOT_CALLS=0
    PCT_START_RESULT=0
    mount_calls=0
    umount_calls=0
}

# shellcheck disable=SC1090
source "$SCRIPT"

# Redirect all persistent/runtime state into a throwaway temp directory -
# never the real /etc/pve-ip-mount-gate or /run/pve-ip-mount-gate.
TESTROOT="$(mktemp -d)"
trap 'rm -rf "$TESTROOT"' EXIT
STATE_DIR="$TESTROOT/state"
RUNTIME_DIR="$TESTROOT/run"
MOUNT_DB="$STATE_DIR/mounts.db"
PENDING_FILE="$RUNTIME_DIR/pending"
LOCK_FILE="$RUNTIME_DIR/lock"

reset_runtime_dirs() {
    rm -rf "$STATE_DIR" "$RUNTIME_DIR"
}

# Run a function directly in the current shell (not via `$(...)`, which
# would fork a subshell and drop any stub-array mutations it makes) while
# still capturing its output into $LAST_OUTPUT.
run_capture() {
    local tmp
    tmp="$(mktemp)"
    "$@" >"$tmp" 2>&1
    LAST_OUTPUT="$(cat "$tmp")"
    rm -f "$tmp"
}

write_mount_db() {
    # write_mount_db "line1" "line2" ...
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$@" > "$MOUNT_DB"
}

# ============================================================================
# 1. extract_ip - classification only
# ============================================================================

assert_eq "extract_ip finds an IPv4 address in a CIFS source" \
    "203.0.113.10" "$(extract_ip "//203.0.113.10/media")"
assert_eq "extract_ip finds an IPv4 address in an NFS source" \
    "203.0.113.20" "$(extract_ip "203.0.113.20:/exports/media")"
assert_eq "extract_ip returns nothing for a hostname-only source" \
    "" "$(extract_ip "example-host:/export")"
assert_eq "extract_ip returns nothing for a local path" \
    "" "$(extract_ip "/dev/sda1")"

# ============================================================================
# 2. emit_remote_mount - record shape and local-path exclusion
# ============================================================================

reset_stubs
assert_eq "a plain absolute local path is not emitted" \
    "" "$(emit_remote_mount "/mnt/local" "/dev/sda1" "full" "mounted:ext4")"

assert_eq "a source with no IP is not emitted" \
    "" "$(emit_remote_mount "/mnt/x" "example-host:/export" "full" "fstab:nfs")"

assert_eq "a full-kind CIFS record is emitted with all 4 fields" \
    "/mnt/media|//203.0.113.10/media|full|fstab:cifs" \
    "$(emit_remote_mount "/mnt/media" "//203.0.113.10/media" "full" "fstab:cifs")"

assert_eq "trailing slash on target is stripped" \
    "/mnt/media|//203.0.113.10/media|full|fstab:cifs" \
    "$(emit_remote_mount "/mnt/media/" "//203.0.113.10/media" "full" "fstab:cifs")"

# ============================================================================
# 3. carry_forward_custom_record - legacy schema migration
# ============================================================================

reset_stubs
assert_eq "a current-schema mounted: record passes through unchanged" \
    "/mnt/custom|203.0.113.30:/export|full|mounted:nfs4" \
    "$(carry_forward_custom_record "/mnt/custom|203.0.113.30:/export|full|mounted:nfs4")"

assert_eq "a current-schema fstab: record is not carried forward (rediscovered fresh)" \
    "" "$(carry_forward_custom_record "/mnt/media|//203.0.113.10/media|full|fstab:cifs")"

run_capture carry_forward_custom_record "/mnt/legacy|203.0.113.40|mounted:cifs"
assert_match "a legacy 3-field mounted: record is migrated to endpoint kind" \
    "/mnt/legacy|203.0.113.40|endpoint|mounted:cifs" "$LAST_OUTPUT"
assert_match "the migration is logged" "migrating legacy mount record" "$LAST_OUTPUT"

reset_stubs
assert_eq "a legacy 3-field fstab-origin record is dropped, not migrated" \
    "" "$(carry_forward_custom_record "/mnt/media|203.0.113.10|fstab:nfs")"

run_capture carry_forward_custom_record "/mnt/weird|garbage|mounted:cifs|extra|fields"
assert_match "an unparseable mounted: record logs a WARN instead of silently vanishing" \
    "WARN:" "$LAST_OUTPUT"

# ============================================================================
# 4. mount_ready_map - the core source-identity safety fix
# ============================================================================

# --- CIFS: same server + same share -> ready candidate ---
reset_stubs
write_mount_db "/mnt/media|//203.0.113.10/media|full|fstab:cifs"
FINDMNT_ACTUAL["/mnt/media"]="//203.0.113.10/media"
run_capture mount_ready_map
assert_match "CIFS same server + same share is READY" "/mnt/media|1|" "$LAST_OUTPUT"

# --- CIFS: same server, different share -> unexpected-source ---
reset_stubs
write_mount_db "/mnt/media|//203.0.113.10/media|full|fstab:cifs"
FINDMNT_ACTUAL["/mnt/media"]="//203.0.113.10/backups"
run_capture mount_ready_map
assert_match "CIFS same server + different share is unexpected-source" \
    "/mnt/media|0|unexpected-source" "$LAST_OUTPUT"

# --- CIFS: different server -> unexpected-source ---
reset_stubs
write_mount_db "/mnt/media|//203.0.113.10/media|full|fstab:cifs"
FINDMNT_ACTUAL["/mnt/media"]="//203.0.113.11/media"
run_capture mount_ready_map
assert_match "CIFS different server is unexpected-source" \
    "/mnt/media|0|unexpected-source" "$LAST_OUTPUT"

# --- NFS: same server + same export -> ready candidate ---
reset_stubs
write_mount_db "/mnt/media|203.0.113.20:/exports/media|full|fstab:nfs4"
FINDMNT_ACTUAL["/mnt/media"]="203.0.113.20:/exports/media"
run_capture mount_ready_map
assert_match "NFS same server + same export is READY" "/mnt/media|1|" "$LAST_OUTPUT"

# --- NFS: same server, different export -> unexpected-source ---
reset_stubs
write_mount_db "/mnt/media|203.0.113.20:/exports/media|full|fstab:nfs4"
FINDMNT_ACTUAL["/mnt/media"]="203.0.113.20:/exports/backups"
run_capture mount_ready_map
assert_match "NFS same server + different export is unexpected-source" \
    "/mnt/media|0|unexpected-source" "$LAST_OUTPUT"

# --- NFS: different server -> unexpected-source ---
reset_stubs
write_mount_db "/mnt/media|203.0.113.20:/exports/media|full|fstab:nfs4"
FINDMNT_ACTUAL["/mnt/media"]="203.0.113.21:/exports/media"
run_capture mount_ready_map
assert_match "NFS different server is unexpected-source" \
    "/mnt/media|0|unexpected-source" "$LAST_OUTPUT"

# --- unrelated local filesystem on target -> unexpected-source ---
reset_stubs
write_mount_db "/mnt/media|203.0.113.20:/exports/media|full|fstab:nfs4"
FINDMNT_ACTUAL["/mnt/media"]="/dev/sdb1"
run_capture mount_ready_map
assert_match "an unrelated local filesystem at the target is unexpected-source" \
    "/mnt/media|0|unexpected-source" "$LAST_OUTPUT"

# --- target not mounted -> not-mounted ---
reset_stubs
write_mount_db "/mnt/media|203.0.113.20:/exports/media|full|fstab:nfs4"
run_capture mount_ready_map
assert_match "a missing target is not-mounted" "/mnt/media|0|not-mounted" "$LAST_OUTPUT"

# --- unresponsive mount -> not-responding (source matches, stat fails) ---
reset_stubs
write_mount_db "/mnt/media|203.0.113.20:/exports/media|full|fstab:nfs4"
FINDMNT_ACTUAL["/mnt/media"]="203.0.113.20:/exports/media"
TIMEOUT_FAIL_TARGETS="/mnt/media"
run_capture mount_ready_map
assert_match "a correctly-sourced but unresponsive mount is not-responding" \
    "/mnt/media|0|not-responding" "$LAST_OUTPUT"

# --- endpoint kind: same server -> ready candidate ---
reset_stubs
write_mount_db "/mnt/storage|203.0.113.50|endpoint|pve:cifs:example"
FINDMNT_ACTUAL["/mnt/storage"]="//203.0.113.50/someshare"
run_capture mount_ready_map
assert_match "endpoint-kind same server address is READY" "/mnt/storage|1|" "$LAST_OUTPUT"

# --- endpoint kind: different server -> unexpected-source ---
reset_stubs
write_mount_db "/mnt/storage|203.0.113.50|endpoint|pve:cifs:example"
FINDMNT_ACTUAL["/mnt/storage"]="//203.0.113.51/someshare"
run_capture mount_ready_map
assert_match "endpoint-kind different server is unexpected-source" \
    "/mnt/storage|0|unexpected-source" "$LAST_OUTPUT"

# --- regression: a shorter configured endpoint must not match a longer
# one it's a prefix of (the original substring-match bug). ---
reset_stubs
write_mount_db "/mnt/storage|203.0.113.24|endpoint|pve:cifs:example"
FINDMNT_ACTUAL["/mnt/storage"]="//203.0.113.241/someshare"
run_capture mount_ready_map
assert_match "203.0.113.24 does not match 203.0.113.241 as a substring" \
    "/mnt/storage|0|unexpected-source" "$LAST_OUTPUT"

# ============================================================================
# 5. storage.cfg parsing: full vs. endpoint reconstruction
# ============================================================================

STORAGE_CFG_DIR="$(mktemp -d)"
trap 'rm -rf "$TESTROOT" "$STORAGE_CFG_DIR"' EXIT

test_storage_cfg() {
    local body="$1"
    printf '%s\n' "$body" > "$STORAGE_CFG_DIR/storage.cfg"
    # discover_current_mounts hardcodes /etc/pve/storage.cfg; there is no
    # injection point, so exercise the same awk program directly against
    # the fixture file instead of duplicating discover_current_mounts.
    awk '
        function flush() {
            if ((type == "nfs" || type == "cifs") && server != "") {
                p = path
                if (p == "") p = "/mnt/pve/" id
                if (type == "nfs" && xport != "") {
                    src = server ":" xport
                    kind = "full"
                } else if (type == "cifs" && share != "" && subdir == "") {
                    src = "//" server "/" share
                    kind = "full"
                } else {
                    src = server
                    kind = "endpoint"
                }
                print p "|" src "|" kind "|pve:" type ":" id
            }
        }
        /^[^[:space:]][^:]*:[[:space:]]+/ {
            flush()
            line=$0
            type=line; sub(/:.*/, "", type)
            id=line; sub(/^[^:]+:[[:space:]]*/, "", id)
            server=""; path=""; xport=""; share=""; subdir=""
            next
        }
        /^[[:space:]]+server[[:space:]]+/ { server=$0; sub(/^[[:space:]]+server[[:space:]]+/, "", server); next }
        /^[[:space:]]+path[[:space:]]+/   { path=$0;   sub(/^[[:space:]]+path[[:space:]]+/,   "", path);   next }
        /^[[:space:]]+export[[:space:]]+/ { xport=$0;  sub(/^[[:space:]]+export[[:space:]]+/, "", xport); next }
        /^[[:space:]]+share[[:space:]]+/  { share=$0;  sub(/^[[:space:]]+share[[:space:]]+/,  "", share);  next }
        /^[[:space:]]+subdir[[:space:]]+/ { subdir=$0; sub(/^[[:space:]]+subdir[[:space:]]+/, "", subdir); next }
        END { flush() }
    ' "$STORAGE_CFG_DIR/storage.cfg"
}

out="$(test_storage_cfg 'nfs: example-nfs
    export /exports/media
    path /mnt/pve/example-nfs
    server 203.0.113.20
    content backup')"
assert_eq "nfs: storage.cfg with export reconstructs a full source" \
    "/mnt/pve/example-nfs|203.0.113.20:/exports/media|full|pve:nfs:example-nfs" "$out"

out="$(test_storage_cfg 'cifs: example-cifs
    path /mnt/pve/example-cifs
    server 203.0.113.10
    share media
    content backup')"
assert_eq "cifs: storage.cfg with share (no subdir) reconstructs a full source" \
    "/mnt/pve/example-cifs|//203.0.113.10/media|full|pve:cifs:example-cifs" "$out"

out="$(test_storage_cfg 'cifs: example-cifs-sub
    path /mnt/pve/example-cifs-sub
    server 203.0.113.10
    share media
    subdir /movies
    content backup')"
assert_eq "cifs: storage.cfg with a subdir falls back to endpoint-only identity" \
    "/mnt/pve/example-cifs-sub|203.0.113.10|endpoint|pve:cifs:example-cifs-sub" "$out"

# ============================================================================
# 6. ct_external_deps - bind-mount dependency resolution
# ============================================================================

reset_stubs
write_mount_db \
    "/mnt/media|203.0.113.20:/exports/media|full|fstab:nfs4" \
    "/mnt/backups|203.0.113.20:/exports/backups|full|fstab:nfs4"
pct_define 201 "0" "" "test-ct" "stopped" "mp0: /mnt/media/library,mp=/media,ro=1"
assert_eq "a bind mount under a known target resolves to that target" \
    "/mnt/media" "$(ct_external_deps 201)"

pct_define 202 "0" "" "test-ct" "stopped" "mp0: /mnt/other/path,mp=/other"
assert_eq "a bind mount under no known target has no dependencies" \
    "" "$(ct_external_deps 202)"

pct_define 203 "0" "" "test-ct" "stopped" \
    "mp0: /mnt/media/library,mp=/media,ro=1;mp1: /mnt/backups/2024,mp=/backups"
assert_eq "multiple bind mounts resolve to multiple targets" \
    "$(printf '/mnt/backups\n/mnt/media')" "$(ct_external_deps 203)"

# ============================================================================
# 7. Higher-level: enrollment, multi-dependency readiness, pending semantics
# ============================================================================
#
# These exercise enroll_new_cts()/cycle(), which call refresh_mount_db()
# internally and so regenerate MOUNT_DB from discovery on every call -
# writing to MOUNT_DB directly (as sections 4-6 do) would just be
# overwritten. Instead, FSTAB_FIXTURE feeds the findmnt stub so discovery
# reproduces the same dependency records each time, the way a real static
# /etc/fstab would.

# --- onboot=0 untagged CT is never auto-enrolled ---
reset_stubs
reset_runtime_dirs
FSTAB_FIXTURE="/mnt/media 203.0.113.20:/exports/media nfs4"
pct_define 301 "0" "media" "generic-ct" "stopped" "mp0: /mnt/media/library,mp=/media,ro=1"
run_capture enroll_new_cts
assert_eq "an onboot=0 untagged CT's existing tags are left untouched" "media" "${PCT_TAGS[301]}"
assert_false "an onboot=0 untagged CT is not given the gate tag" \
    bash -c '[[ "$1" == *ipmount-gated* ]]' _ "${PCT_TAGS[301]}"
assert_eq "an onboot=0 untagged CT is not touched via pct set --onboot" "0" "$PCT_SET_ONBOOT_CALLS"

# --- onboot=1 dependent CT IS auto-enrolled ---
reset_stubs
reset_runtime_dirs
FSTAB_FIXTURE="/mnt/media 203.0.113.20:/exports/media nfs4"
pct_define 302 "1" "" "auto-ct" "stopped" "mp0: /mnt/media/library,mp=/media,ro=1"
run_capture enroll_new_cts
assert_match "an onboot=1 dependent CT is tagged ipmount-gated" "ipmount-gated" "${PCT_TAGS[302]}"
assert_eq "an onboot=1 dependent CT has onboot flipped to 0" "0" "${PCT_ONBOOT[302]}"

# --- multiple dependencies: only starts when ALL are ready ---
reset_stubs
reset_runtime_dirs
FSTAB_FIXTURE="$(printf '%s\n%s' \
    "/mnt/media 203.0.113.20:/exports/media nfs4" \
    "/mnt/backups 203.0.113.20:/exports/backups nfs4")"
pct_define 401 "0" "ipmount-gated" "multi-dep-ct" "stopped" \
    "mp0: /mnt/media/library,mp=/media,ro=1;mp1: /mnt/backups/2024,mp=/backups"
ensure_runtime
echo 401 > "$PENDING_FILE"

FINDMNT_ACTUAL["/mnt/media"]="203.0.113.20:/exports/media"
# /mnt/backups intentionally left unmounted.
run_capture cycle
assert_eq "with one of two dependencies unready, the CT is not started" "0" "$PCT_START_CALLS"
assert_eq "the CT stays in the pending set" "401" "$(cat "$PENDING_FILE" 2>/dev/null)"

FINDMNT_ACTUAL["/mnt/backups"]="203.0.113.20:/exports/backups"
run_capture cycle
assert_eq "once both dependencies are ready, the CT is started" "1" "$PCT_START_CALLS"
assert_eq "the CT is removed from the pending set after starting" "" "$(cat "$PENDING_FILE" 2>/dev/null)"

# --- already-running CT is marked complete without being restarted ---
reset_stubs
reset_runtime_dirs
FSTAB_FIXTURE="/mnt/media 203.0.113.20:/exports/media nfs4"
pct_define 402 "0" "ipmount-gated" "already-running-ct" "running" \
    "mp0: /mnt/media/library,mp=/media,ro=1"
ensure_runtime
echo 402 > "$PENDING_FILE"
FINDMNT_ACTUAL["/mnt/media"]="203.0.113.20:/exports/media"
run_capture cycle
assert_eq "an already-running CT is never passed to pct start" "0" "$PCT_START_CALLS"
assert_eq "an already-running CT is removed from the pending set" "" "$(cat "$PENDING_FILE" 2>/dev/null)"

# --- manually-stopped-after-success is not restarted by a later cycle ---
reset_stubs
reset_runtime_dirs
FSTAB_FIXTURE="/mnt/media 203.0.113.20:/exports/media nfs4"
pct_define 403 "0" "ipmount-gated" "stop-after-start-ct" "stopped" \
    "mp0: /mnt/media/library,mp=/media,ro=1"
ensure_runtime
echo 403 > "$PENDING_FILE"
FINDMNT_ACTUAL["/mnt/media"]="203.0.113.20:/exports/media"

run_capture cycle
assert_eq "the CT starts on the first ready cycle" "1" "$PCT_START_CALLS"
assert_eq "the CT leaves the pending set after starting" "" "$(cat "$PENDING_FILE" 2>/dev/null)"

# Operator manually stops it later in the same boot.
PCT_STATUS[403]="stopped"
run_capture cycle
assert_eq "a manual stop after a successful start is not undone by the next cycle" \
    "1" "$PCT_START_CALLS"

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
