#!/usr/bin/env bash
# Upgrade a host-networked standalone Nexterm AIO container with data rollback.
set -Eeuo pipefail
umask 077
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/release-common.sh"
tag=${1:-}; name=${2:-nexterm}
[[ -n $tag && $name =~ ^[a-zA-Z0-9_.-]+$ && $EUID == 0 ]] || { echo "Usage: $0 vTAG [container]; run as root" >&2; exit 2; }
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { echo 'Only Linux x86_64 is supported' >&2; exit 1; }
backup=$(mktemp -d /var/backups/nexterm-standalone.XXXXXXXX); tmp=$(mktemp -d /var/tmp/nexterm-standalone.XXXXXXXX)
chmod 700 "$backup" "$tmp"
docker inspect "$name" > "$backup/container-inspect.json"
# Refuse unsupported settings instead of silently losing them on replacement.
python3 - "$backup/container-inspect.json" "$backup/container.env" "$backup/mount" "$backup/restart" <<'PY'
import json,os,sys
x=json.load(open(sys.argv[1]))[0]; h=x['HostConfig']; c=x['Config']; mounts=x['Mounts']
assert x['State']['Running'] and h['NetworkMode']=='host', 'Requires running host-network container'
assert len(mounts)==1 and mounts[0]['Destination']=='/app/data' and mounts[0]['Type']=='volume' and mounts[0]['RW'], 'Requires a single writable named /app/data volume'
assert not c.get('User') and not h.get('Privileged') and not h.get('ReadonlyRootfs')
for k in ('CapAdd','CapDrop','Devices','SecurityOpt','ExtraHosts','Dns','DnsSearch','PortBindings','PublishAllPorts','Sysctls','Memory','NanoCpus','PidsLimit','PidMode','UsernsMode','AutoRemove'):
 assert not h.get(k), 'Unsupported container setting: '+k
assert not c.get('Labels'), 'Container labels require a supported Compose upgrade'
with open(sys.argv[2],'w') as f:
 for e in c.get('Env',[]):
  if not e.startswith('PATH='): f.write(e+'\n')
os.chmod(sys.argv[2],0o600)
open(sys.argv[3],'w').write(mounts[0]['Name']+'\n'+mounts[0]['Source']+'\n')
open(sys.argv[4],'w').write(h['RestartPolicy']['Name'] or 'no')
PY
mapfile -t mount < "$backup/mount"; restart=$(cat "$backup/restart"); source_path=${mount[1]}
[[ $source_path == /var/lib/docker/volumes/*/_data && -d $source_path && ! -L $source_path ]] || { echo 'Unsafe volume path' >&2; exit 1; }
release_fetch "$tag" nexterm-aio-linux-amd64.tar.gz "$tmp"
tar -xOzf "$tmp/nexterm-aio-linux-amd64.tar.gz" manifest.json > "$tmp/manifest.json"
python3 - "$tmp/manifest.json" <<'PY' > "$tmp/tags"
import json,sys
m=json.load(open(sys.argv[1])); assert len(m)==1 and m[0].get('RepoTags')
for t in m[0]['RepoTags']:
 if not isinstance(t,str) or '\n' in t: raise SystemExit('Invalid image tag')
 print(t)
PY
while IFS= read -r t; do if old=$(docker image inspect "$t" --format '{{.Id}}' 2>/dev/null); then printf '%s %s\n' "$old" "$t" >> "$tmp/old-tags"; fi; done < "$tmp/tags"
if ! docker load -i "$tmp/nexterm-aio-linux-amd64.tar.gz"; then
 if [[ -f $tmp/old-tags ]]; then while read -r old t; do docker tag "$old" "$t"; done < "$tmp/old-tags"; fi
 exit 1
fi
image=$(head -1 "$tmp/tags"); image_id=$(docker image inspect "$image" --format '{{.Id}}')
if [[ -f $tmp/old-tags ]]; then while read -r old t; do docker tag "$old" "$t"; done < "$tmp/old-tags"; fi
version=$(docker run --rm --network none --entrypoint node "$image_id" -p "require('/app/package.json').version")
engine=$(docker run --rm --network none --entrypoint /usr/local/bin/nexterm-engine "$image_id" --help | sed -nE 's/^Nexterm Engine v([^[:space:]]+).*/\1/p' | head -1)
[[ $version == "${tag#v}" && $engine == "$version" ]] || { echo 'Image version mismatch' >&2; exit 1; }
candidate="${name}-candidate-$$"; oldname="${name}-rollback-$(date -u +%Y%m%dT%H%M%SZ)-$$"
docker create --name "$candidate" --network host --restart "$restart" --mount "type=volume,src=${mount[0]},dst=/app/data" --env-file "$backup/container.env" "$image_id" >/dev/null
stopped=0; renamed=0; saved=0
rollback(){
 local rc=$?; trap - EXIT
 if (( rc != 0 )); then
  docker rm -f "$candidate" >/dev/null 2>&1 || true
  if (( renamed )); then
   if (( saved )); then find "$source_path" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +; tar -C "$source_path" -xpf "$backup/data.tar"; fi
   docker rename "$oldname" "$name"; docker start "$name" >/dev/null || echo 'ROLLBACK FAILED: manual recovery required' >&2
  elif (( stopped )); then docker start "$name" >/dev/null || true; fi
 fi
 rm -rf "$tmp"; exit "$rc"
}
trap rollback EXIT
docker stop "$name" >/dev/null; stopped=1
tar -C "$source_path" -cpf "$backup/data.tar" .; tar -tf "$backup/data.tar" >/dev/null; saved=1
docker rename "$name" "$oldname"; renamed=1
docker start "$candidate" >/dev/null
ready=0
for i in $(seq 1 30); do
 if docker exec "$candidate" node -e 'fetch("http://127.0.0.1:6989/api/service/version").then(r=>r.json()).then(x=>process.exit(JSON.stringify(x).includes(process.argv[1])?0:1)).catch(()=>process.exit(1))' "$version" >/dev/null 2>&1; then ready=1; break; fi
 sleep 2
done
[[ $ready == 1 ]] || { echo 'Replacement health check failed' >&2; exit 1; }
accepted=0
for i in $(seq 1 30); do
 if docker logs "$candidate" 2>&1 | grep -F "Server accepted engine (server version: $version)" >/dev/null; then accepted=1; break; fi
 sleep 2
done
[[ $accepted == 1 ]] || { echo 'Local engine not accepted by controller' >&2; exit 1; }
docker rename "$candidate" "$name"
renamed=0; stopped=0
trap - EXIT
rm -rf "$tmp"
echo "Installed $tag; previous container: $oldname; data backup: $backup/data.tar"
