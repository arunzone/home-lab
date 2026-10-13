#!/usr/bin/env bash
# Converge LXC samba-server to the state declared in container.env
# (and smb.conf, when that file exists next to this script).
#
#   ./apply.sh --check   report drift, change nothing (exit 0 = in sync, 2 = drift)
#   ./apply.sh           create if missing, fix drift, start, verify (exit 1 on failure)
#
# Runs on the Proxmox host. Run from any other machine, it ships itself over
# SSH to $PVE_HOST (default: the "lab" alias) and runs there.
# Creating the container from scratch needs LXC_PASSWORD (root password) in the env.
set -euo pipefail

MODE=apply
case "${1:-}" in
  --check) MODE=check ;;
  "") ;;
  *) echo "usage: $0 [--check]" >&2; exit 64 ;;
esac

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------- remote mode
if ! command -v pct >/dev/null 2>&1; then
  PVE_HOST="${PVE_HOST:-lab}"
  stage="$(umask 077; mktemp -d)"
  trap 'rm -rf "$stage"' EXIT
  cp "$DIR/apply.sh" "$DIR/container.env" "$stage/"
  if [ -f "$DIR/smb.conf" ]; then cp "$DIR/smb.conf" "$stage/"; fi
  if [ -n "${LXC_PASSWORD:-}" ]; then (umask 077; printf '%s' "$LXC_PASSWORD" > "$stage/.lxc_password"); fi
  echo ">> $MODE on $PVE_HOST"
  # shellcheck disable=SC2029 # $1 is validated above (empty or --check)
  COPYFILE_DISABLE=1 tar -C "$stage" -cf - . | ssh "$PVE_HOST" \
    "d=\$(mktemp -d) && tar -C \"\$d\" -xf - && bash \"\$d/apply.sh\" ${1:-} </dev/null; rc=\$?; rm -rf \"\$d\"; exit \$rc"
  exit $?
fi

# ------------------------------------------------------------------ host mode
# shellcheck source=container.env
source "$DIR/container.env"
if [ -f "$DIR/.lxc_password" ]; then LXC_PASSWORD="$(cat "$DIR/.lxc_password")"; fi

DRIFT=0
NEEDS_RESTART=0
FAILED=0
NET0="name=$IFACE,bridge=$BRIDGE,firewall=$FIREWALL,gw=$GW,hwaddr=$HWADDR,ip=$IP,type=veth"

say()   { printf '%-7s %s\n' "$1" "$2"; }
die()   { say ERROR "$1" >&2; exit 1; }
cfg()   { pct config "$CTID" | sed -n "s/^$1: //p"; }
norm()  { tr ',' '\n' <<<"$1" | sort | paste -sd, -; }   # Proxmox may reorder options
in_ct() { pct exec "$CTID" -- sh -c "$1"; }
apply() { [ "$MODE" = apply ]; }

# 1. Existence ------------------------------------------------------------------
if ! pct status "$CTID" >/dev/null 2>&1; then
  say DRIFT "CT $CTID does not exist -> create"
  if ! apply; then exit 2; fi
  [ -n "${LXC_PASSWORD:-}" ] || die "LXC_PASSWORD must be set to create the container"
  TEMPLATE="$(find /var/lib/vz/template/cache -maxdepth 1 -name "*${TEMPLATE_MATCH}*" -printf "%f\n" | sort -V | tail -n1)"
  [ -n "$TEMPLATE" ] || die "no template matching '$TEMPLATE_MATCH' (run: pveam update && pveam download local <template>)"
  pct create "$CTID" "local:vztmpl/$TEMPLATE" \
    --hostname "$CT_HOSTNAME" --password "$LXC_PASSWORD" --unprivileged "$UNPRIVILEGED" \
    --cores "${CORES:-1}" --memory "${MEMORY:-512}" --swap "${SWAP:-512}" \
    --rootfs "$ROOTFS_STORAGE:$ROOTFS_GB" --net0 "$NET0" --mp0 "$MP0" --onboot "$ONBOOT"
  say FIXED "created CT $CTID from $TEMPLATE"
fi

LOCK="$(cfg lock)"
[ -z "$LOCK" ] || die "CT $CTID is locked ($LOCK); resolve that first"

# 2. Proxmox config ---------------------------------------------------------------
reconcile() {   # key, desired value, restart-needed (0/1)
  local key="$1" want="$2" restart="$3" have
  have="$(cfg "$key")"
  if [ "$(norm "$have")" = "$(norm "$want")" ]; then say OK "$key"; return; fi
  say DRIFT "$key: '${have:-<unset>}' -> '$want'"
  DRIFT=1
  if apply; then
    pct set "$CTID" "-$key" "$want"
    say FIXED "$key"
    if [ "$restart" = 1 ]; then NEEDS_RESTART=1; fi
  fi
}
reconcile hostname "$CT_HOSTNAME" 1
reconcile onboot   "$ONBOOT"      0
reconcile net0     "$NET0"        1
reconcile mp0      "$MP0"         1
if [ -n "$CORES"  ]; then reconcile cores  "$CORES"  0; fi
if [ -n "$MEMORY" ]; then reconcile memory "$MEMORY" 0; fi
if [ -n "$SWAP"   ]; then reconcile swap   "$SWAP"   0; fi

# 3. Running state ------------------------------------------------------------------
STATUS="$(pct status "$CTID" | awk '{print $2}')"
if [ "$STATUS" != running ]; then
  say DRIFT "status: $STATUS -> running"
  DRIFT=1
  if apply; then pct start "$CTID"; say FIXED "started"; fi
elif [ "$NEEDS_RESTART" = 1 ] && apply; then
  pct reboot "$CTID"; say FIXED "rebooted to apply hostname/network/mount changes"
fi

if [ "$(pct status "$CTID" | awk '{print $2}')" != running ]; then
  say SKIP "container not running; inside checks skipped"
  if apply; then exit 1; else exit 2; fi
fi
for _ in $(seq 1 30); do in_ct true >/dev/null 2>&1 && break; sleep 1; done

# 4. Inside the container -------------------------------------------------------------
if in_ct 'command -v smbd' >/dev/null 2>&1; then
  say OK "samba installed"
else
  say DRIFT "samba package missing -> install"
  DRIFT=1
  if apply; then
    in_ct 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq samba'
    say FIXED "samba installed"
  fi
fi

if [ -f "$DIR/smb.conf" ]; then
  if [ "$(in_ct 'cat /etc/samba/smb.conf' 2>/dev/null || true)" = "$(cat "$DIR/smb.conf")" ]; then
    say OK "smb.conf"
  else
    say DRIFT "smb.conf differs from repo -> push"
    DRIFT=1
    if apply; then
      pct push "$CTID" "$DIR/smb.conf" /etc/samba/smb.conf.new
      in_ct 'testparm -s /etc/samba/smb.conf.new >/dev/null 2>&1' \
        || { in_ct 'rm -f /etc/samba/smb.conf.new'; die "repo smb.conf fails testparm; live config untouched"; }
      in_ct 'mv /etc/samba/smb.conf.new /etc/samba/smb.conf && systemctl reload-or-restart smbd'
      say FIXED "smb.conf"
    fi
  fi
else
  say SKIP "smb.conf not in repo (import it to manage shares)"
fi

if in_ct 'systemctl is-enabled -q smbd && systemctl is-active -q smbd' >/dev/null 2>&1; then
  say OK "smbd enabled and active"
else
  say DRIFT "smbd not enabled/active -> enable --now"
  DRIFT=1
  if apply; then in_ct 'systemctl enable --now smbd'; say FIXED "smbd"; fi
fi

# 5. Verify -------------------------------------------------------------------------------
sleep 2
if in_ct "ss -tln | grep -q ':445 '"; then say OK "smbd listening on 445"; else say FAIL "nothing listening on 445"; FAILED=1; fi
if ping -c 2 -W 2 "${IP%/*}" >/dev/null 2>&1; then
  say OK "${IP%/*} reachable from host"
else
  say FAIL "${IP%/*} unreachable from host; $BRIDGE may not be on the LAN (try BRIDGE=vmbr0 IFACE=eth0)"
  FAILED=1
fi

if [ "$MODE" = check ]; then
  if [ "$DRIFT" = 1 ]; then say RESULT "drift found; run ./apply.sh to fix"; exit 2; fi
  say RESULT "in sync"; exit 0
fi
if [ "$FAILED" = 1 ]; then say RESULT "applied, but verification failed"; exit 1; fi
say RESULT "converged"
