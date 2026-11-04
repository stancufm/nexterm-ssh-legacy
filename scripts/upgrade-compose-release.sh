#!/usr/bin/env bash
# Replace a Compose-managed service using a verified AIO release image.
set -Eeuo pipefail
umask 077
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/release-common.sh"
tag=${1:-}; compose=${2:-}; service=${3:-}
[[ -n $tag && -f $compose && -n $service ]] || { echo "Usage: $0 vTAG /absolute/path/compose.yml service" >&2; exit 2; }
[[ $EUID == 0 && $compose == /* && $service =~ ^[a-zA-Z0-9_.-]+$ ]] || { echo 'Run as root with absolute Compose path and valid service name' >&2; exit 1; }
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { echo 'Only Linux x86_64 is supported' >&2; exit 1; }
dir=$(dirname -- "$compose"); override="${compose}.nexterm-release.yml"
backup=$(mktemp -d /var/backups/nexterm-release.XXXXXXXX); tmp=$(mktemp -d /var/tmp/nexterm-release.XXXXXXXX)
chmod 700 "$backup" "$tmp"
compose_cmd=(docker compose -f "$compose")
if [[ -f $override ]]; then cp -p "$override" "$backup/override.before"; compose_cmd+=(-f "$override"); fi
id=$("${compose_cmd[@]}" ps -q "$service")
[[ -n $id && $(docker inspect "$id" --format '{{.State.Running}}') == true ]] || { echo 'Expected one running service container' >&2; exit 1; }
[[ $(printf '%s\n' "$id" | wc -l) == 1 ]] || { echo 'Scaled services are unsupported' >&2; exit 1; }
docker inspect "$id" > "$backup/container-inspect.json"
oldimage=$(docker inspect "$id" --format '{{.Image}}')
docker image tag "$oldimage" "nexterm-release-rollback:$(basename "$backup")"
mount=$(docker inspect "$id" --format '{{range .Mounts}}{{if eq .Destination "/app/data"}}{{.Source}}{{end}}{{end}}')
[[ -z $mount || ( $mount == /* && -d $mount && ! -L $mount ) ]] || { echo 'Unsupported data mount' >&2; exit 1; }
release_fetch "$tag" nexterm-aio-linux-amd64.tar.gz "$tmp"
# docker load can overwrite an existing local tag. Capture and restore any
# such tag immediately, so loading a release never changes another service.
tar -xOzf "$tmp/nexterm-aio-linux-amd64.tar.gz" manifest.json > "$tmp/manifest.json"
python3 - "$tmp/manifest.json" <<'PYCODE' > "$tmp/tags"
import json,sys
m=json.load(open(sys.argv[1])); assert len(m)==1 and m[0].get('RepoTags')
for tag in m[0]['RepoTags']:
 if not isinstance(tag,str) or '\n' in tag: raise SystemExit('Invalid image tag')
 print(tag)
PYCODE
while IFS= read -r t; do if old=$(docker image inspect "$t" --format '{{.Id}}' 2>/dev/null); then printf '%s %s\n' "$old" "$t" >> "$tmp/old-tags"; fi; done < "$tmp/tags"
if ! docker load -i "$tmp/nexterm-aio-linux-amd64.tar.gz"; then
 if [[ -f $tmp/old-tags ]]; then while read -r old t; do docker tag "$old" "$t"; done < "$tmp/old-tags"; fi
 exit 1
fi
image=$(head -1 "$tmp/tags")
image_id=$(docker image inspect "$image" --format '{{.Id}}')
if [[ -f $tmp/old-tags ]]; then while read -r old t; do docker tag "$old" "$t"; done < "$tmp/old-tags"; fi
image="$image_id"
version=$(docker run --rm --network none --entrypoint node "$image" -p "require('/app/package.json').version")
[[ $version == "${tag#v}" ]] || { echo "Image version mismatch: $version" >&2; exit 1; }
engine=$(docker run --rm --network none --entrypoint /usr/local/bin/nexterm-engine "$image" --help | sed -nE 's/^Nexterm Engine v([^[:space:]]+).*/\1/p' | head -1)
[[ $engine == "$version" ]] || { echo 'Image engine version mismatch' >&2; exit 1; }
newtag="nexterm-release:${version}"
docker tag "$image" "$newtag"
changed=0; stopped=0; saved=0
rollback() {
 local rc=$?
 trap - EXIT
 if (( rc != 0 && stopped )); then
   echo 'Upgrade failed; restoring previous service and data' >&2
   docker compose -f "$compose" -f "$override" stop "$service" >/dev/null 2>&1 || true
   if (( saved )); then find "$mount" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +; tar -C "$mount" -xpf "$backup/data.tar"; fi
   if [[ -f $backup/override.before ]]; then cp -p "$backup/override.before" "$override"; else rm -f "$override"; fi
   "${compose_cmd[@]}" up -d --no-build --no-deps "$service" || echo 'ROLLBACK FAILED: manual recovery required' >&2
 fi
 rm -rf "$tmp"
 exit "$rc"
}
trap rollback EXIT
"${compose_cmd[@]}" stop "$service"; stopped=1
if [[ -n $mount ]]; then tar -C "$mount" -cpf "$backup/data.tar" .; tar -tf "$backup/data.tar" >/dev/null; saved=1; fi
printf 'services:\n  %s:\n    image: %s\n' "$service" "$newtag" > "$override"
docker compose -f "$compose" -f "$override" up -d --no-build --no-deps "$service"
newid=$(docker compose -f "$compose" -f "$override" ps -q "$service")
[[ $(docker inspect "$newid" --format '{{.State.Running}}') == true ]] || { echo 'Replacement is not running' >&2; exit 1; }
# AIO has an HTTP API; engine-only services need controller-level acceptance.
if [[ -n $mount ]]; then
  ready=0
  for i in $(seq 1 30); do
    if docker exec "$newid" node -e 'fetch("http://127.0.0.1:6989/api/service/version").then(r=>r.json()).then(x=>process.exit(JSON.stringify(x).includes(process.argv[1])?0:1)).catch(()=>process.exit(1))' "$version" >/dev/null 2>&1; then ready=1; break; fi
    sleep 2
  done
  [[ $ready == 1 ]] || { echo 'Controller version health check failed' >&2; exit 1; }
else
  accepted=0
  for i in $(seq 1 30); do
    [[ $(docker inspect "$newid" --format '{{.State.Running}}') == true ]] || exit 1
    if docker logs "$newid" 2>&1 | grep -F "Server accepted engine (server version: $version)" >/dev/null; then accepted=1; break; fi
    sleep 2
  done
  [[ $accepted == 1 ]] || { echo 'Controller did not accept engine at the requested version' >&2; exit 1; }
fi
stopped=0
echo "Installed $tag; backup: $backup"
echo "Use both Compose files for subsequent operations: -f $compose -f $override"
if [[ -z $mount ]]; then echo 'Controller accepted the engine at the requested version.'; fi
