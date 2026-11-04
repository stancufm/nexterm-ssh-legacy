#!/usr/bin/env bash
# Upgrade the native systemd engine; configuration and registration remain untouched.
set -Eeuo pipefail
umask 077
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/release-common.sh"
tag=${1:-}; service=${2:-nexterm-engine.service}; root=${NEXTERM_ENGINE_DIR:-/opt/nexterm-engine}
[[ -n $tag ]] || { echo "Usage: $0 vTAG [systemd-service]" >&2; exit 2; }
[[ $EUID == 0 ]] || { echo 'Run as root' >&2; exit 1; }
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { echo 'Only Linux x86_64 is supported' >&2; exit 1; }
[[ $root == /* && $root != / && ! -L $root && -d $root ]] || { echo 'Invalid engine directory' >&2; exit 1; }
systemctl is-active --quiet "$service" || { echo 'Engine service is not active; refusing upgrade' >&2; exit 1; }
base=$(dirname -- "$root"); tmp=$(mktemp -d "$base/.nexterm-update.XXXXXXXX"); backup="${root}.rollback-$(date -u +%Y%m%dT%H%M%SZ)-$$"; moved=0; installed=0
cleanup() {
  local rc=$?
  trap - EXIT
  if (( rc != 0 && moved )); then
    echo 'Upgrade failed; restoring previous engine' >&2
    systemctl stop "$service" || true
    if (( installed )); then mv -- "$root" "$tmp/failed" || true; fi
    mv -- "$backup" "$root" && systemctl start "$service" || echo 'ROLLBACK FAILED: manual recovery required' >&2
  fi
  rm -rf -- "$tmp"
  exit "$rc"
}
trap cleanup EXIT
release_fetch "$tag" nexterm-engine-linux-x64.tar.gz "$tmp"
# Reject paths and links that can escape the staging directory.
python3 - "$tmp/nexterm-engine-linux-x64.tar.gz" <<'PY'
import pathlib,sys,tarfile
with tarfile.open(sys.argv[1], 'r:gz') as tar:
 for item in tar:
  p=pathlib.PurePosixPath(item.name)
  if p.is_absolute() or '..' in p.parts or not p.parts or p.parts[0] != 'nexterm-engine-linux-x64': raise SystemExit('Unsafe archive path')
  if not (item.isfile() or item.isdir() or item.issym()): raise SystemExit('Unsupported archive entry')
  if item.issym():
   link=pathlib.PurePosixPath(item.linkname)
   if link.is_absolute() or '..' in link.parts: raise SystemExit('Unsafe archive link')
PY
tar -xzf "$tmp/nexterm-engine-linux-x64.tar.gz" -C "$tmp"
candidate="$tmp/nexterm-engine-linux-x64"
[[ -x $candidate/nexterm-engine ]] || { echo 'Engine executable missing' >&2; exit 1; }
version=$("$candidate/nexterm-engine" --help | sed -nE 's/^Nexterm Engine v([^[:space:]]+).*/\1/p' | head -1)
[[ $version == "${tag#v}" ]] || { echo "Engine version mismatch: $version" >&2; exit 1; }
systemctl stop "$service"
mv -- "$root" "$backup"; moved=1
mv -- "$candidate" "$root"; installed=1
chown -R root:root "$root"
started=$(date --iso-8601=seconds)
systemctl start "$service"
accepted=0
for i in $(seq 1 30); do
  systemctl is-active --quiet "$service" || { echo 'Engine service failed to start' >&2; exit 1; }
  if journalctl -u "$service" --since "$started" -o cat --no-pager | grep -F "Server accepted engine (server version: $version)" >/dev/null; then accepted=1; break; fi
  sleep 2
done
[[ $accepted == 1 ]] || { echo 'Controller did not accept engine at the requested version' >&2; exit 1; }
echo "Installed $tag; rollback directory: $backup"
echo 'Controller accepted the engine at the requested version.'
moved=0
