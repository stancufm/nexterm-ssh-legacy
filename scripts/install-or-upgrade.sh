#!/usr/bin/env bash
# Install or upgrade Nexterm SSH Legacy from a tagged public release.
set -Eeuo pipefail

VERSION="v1.2.2-nsg.7"
CONTAINER="nexterm"
PORT="6989"
NETWORK="bridge"

die() { echo "ERROR: $*" >&2; exit 1; }
while (($#)); do
  case "$1" in
    --version) shift; VERSION="$1" ;;
    --container) shift; CONTAINER="$1" ;;
    --port) shift; PORT="$1" ;;
    --network) shift; NETWORK="$1" ;;
    -h|--help) echo "Usage: $0 [--version TAG] [--container NAME] [--port PORT] [--network NETWORK]"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

[[ $EUID -eq 0 ]] || die "Run as root (sudo -i first)."
command -v docker >/dev/null || die "Docker must be installed before running this script."
command -v git >/dev/null || die "Git must be installed before running this script."
command -v openssl >/dev/null || die "OpenSSL must be installed before running this script."

host=github.com
project=stancufm/nexterm-ssh-legacy.git
source_dir="$(mktemp -d /opt/nexterm-nsg.XXXXXX)"
GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$VERSION" "https://$host/$project" "$source_dir"

if docker inspect "$CONTAINER" >/dev/null 2>&1; then
  exec bash "$source_dir/scripts/migrate-existing-aio.sh" --apply --container "$CONTAINER"
fi

release="$(sed -nE 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$source_dir/package.json" | head -n1)"
[[ -n "$release" ]] || die "Could not read release version."

docker build -f "$source_dir/Dockerfile.engine" -t "nexterm-nsg-engine:$release" "$source_dir"
docker build --build-arg "VERSION=$release" -f "$source_dir/Dockerfile.server" -t "nexterm-nsg-server:$release" "$source_dir"
docker build --build-arg "ENGINE_IMAGE=nexterm-nsg-engine:$release" --build-arg "SERVER_IMAGE=nexterm-nsg-server:$release" -t "nexterm-nsg:$release" "$source_dir"

install_dir=/opt/nexterm
install -d -m 700 "$install_dir"
key_file="$install_dir/nexterm.env"
umask 077
key="$(openssl rand -hex 32)"
printf 'ENCRYPTION_KEY=%s\n' "$key" > "$key_file"

args=(--name "$CONTAINER" --restart unless-stopped -e "ENCRYPTION_KEY=$key" -v "${CONTAINER}_data:/app/data")
if [[ "$NETWORK" == "host" ]]; then args+=(--network host); else args+=(--network "$NETWORK" -p "${PORT}:6989"); fi
docker run -d "${args[@]}" "nexterm-nsg:$release"
sleep 15
curl -fsS "http://127.0.0.1:${PORT}/" >/dev/null || die "Container started but HTTP validation failed."
echo "Installed Nexterm SSH Legacy $release. Encryption key saved in $key_file (mode 600)."
