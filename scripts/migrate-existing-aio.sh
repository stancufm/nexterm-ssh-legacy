#!/usr/bin/env bash
# Migrate an existing Nexterm AIO Docker container to this Nexterm SSH Legacy build.
# Run from a checked-out, tagged release of this repository as root:
#   ./scripts/migrate-existing-aio.sh --apply

set -Eeuo pipefail

CONTAINER="nexterm"
APPLY=0
WAIT_SECONDS=20

usage() {
    cat <<'EOF'
Usage: ./scripts/migrate-existing-aio.sh --apply [options]

Builds this checkout locally, migrates the existing Nexterm AIO container while
preserving its data volume and environment, and keeps a timestamped rollback image.

Options:
  --apply                 Required: replace the existing container after a successful build.
  --container NAME        Existing container name (default: nexterm).
  --wait SECONDS          Startup validation wait (default: 20).
  -h, --help              Show this help.

The script never deletes the data volume. During the migration it keeps the
original container intact under a temporary rollback name. If the replacement
does not start, does not answer HTTP, or the script is interrupted, the
original container is automatically restored with its original name, network
attachments, ports, and environment.
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

while (($#)); do
    case "$1" in
        --apply) APPLY=1 ;;
        --container)
            shift
            (($#)) || die "--container requires a value"
            CONTAINER="$1"
            ;;
        --wait)
            shift
            (($#)) || die "--wait requires a value"
            WAIT_SECONDS="$1"
            ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

(( APPLY )) || die "Refusing to replace a container without --apply. Run --help for details."
[[ $EUID -eq 0 ]] || die "Run this script as root (for example: sudo -i)."
command -v docker >/dev/null || die "Docker is not installed or not in PATH."
docker info >/dev/null 2>&1 || die "Docker daemon is not available."

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_DIR/Dockerfile.engine" ]] || die "Run from a Nexterm SSH Legacy checkout."

VERSION="$(sed -nE 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$REPO_DIR/package.json" | head -n1)"
[[ -n "$VERSION" ]] || die "Could not determine the release version from package.json."
docker inspect "$CONTAINER" >/dev/null 2>&1 || die "Container '$CONTAINER' does not exist. Restore it before migrating."

OLD_IMAGE="$(docker inspect "$CONTAINER" --format '{{.Config.Image}}')"
RESTART_POLICY="$(docker inspect "$CONTAINER" --format '{{.HostConfig.RestartPolicy.Name}}')"
[[ -n "$RESTART_POLICY" && "$RESTART_POLICY" != "no" ]] || RESTART_POLICY="unless-stopped"
NETWORK_MODE="$(docker inspect "$CONTAINER" --format '{{.HostConfig.NetworkMode}}')"
mapfile -t EXISTING_NETWORKS < <(docker inspect "$CONTAINER" --format '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}')
MOUNT_INFO="$(docker inspect "$CONTAINER" --format '{{range .Mounts}}{{if eq .Destination "/app/data"}}{{printf "%s|%s|%s" .Type .Name .Source}}{{end}}{{end}}')"
[[ -n "$MOUNT_INFO" ]] || die "Could not find the /app/data mount on '$CONTAINER'."

IFS='|' read -r MOUNT_TYPE MOUNT_NAME MOUNT_SOURCE <<< "$MOUNT_INFO"
if [[ "$MOUNT_TYPE" == "volume" ]]; then
    DATA_MOUNT="${MOUNT_NAME}:/app/data"
else
    DATA_MOUNT="${MOUNT_SOURCE}:/app/data"
fi

HOST_PORT="$(docker port "$CONTAINER" 6989/tcp 2>/dev/null | head -n1 | sed -nE 's/.*:([0-9]+)$/\1/p')"
if [[ "$NETWORK_MODE" != "host" && -z "$HOST_PORT" ]]; then
    die "Could not determine the published port for 6989/tcp. Use a standard AIO container or adapt the script."
fi

mapfile -t CURRENT_ENVS < <(docker inspect "$CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}')
RUN_ENVS=()
ENCRYPTION_KEY=""
for item in "${CURRENT_ENVS[@]}"; do
    # Docker can return an empty environment entry. Passing it through as
    # `--env ""` makes `docker run` reject the replacement container.
    [[ -n "$item" ]] || continue
    if [[ "$item" == ENCRYPTION_KEY=* ]]; then
        ENCRYPTION_KEY="${item#ENCRYPTION_KEY=}"
    else
        RUN_ENVS+=(--env "$item")
    fi
done

if [[ -z "$ENCRYPTION_KEY" ]]; then
    for env_file in /opt/nexterm/nexterm.env /opt/nexterm/.env; do
        [[ -r "$env_file" ]] || continue
        candidate="$(sed -nE 's/^[[:space:]]*ENCRYPTION_KEY[[:space:]]*=[[:space:]]*//p' "$env_file" | head -n1)"
        candidate="${candidate#\"}"
        candidate="${candidate%\"}"
        candidate="${candidate#\'}"
        candidate="${candidate%\'}"
        if [[ -n "$candidate" ]]; then
            ENCRYPTION_KEY="$candidate"
            break
        fi
    done
fi
[[ -n "$ENCRYPTION_KEY" ]] || die "ENCRYPTION_KEY is missing from the container and /opt/nexterm configuration files."

echo "Building Nexterm SSH Legacy $VERSION before changing '$CONTAINER'..."
docker build --build-arg "VERSION=$VERSION" -f "$REPO_DIR/Dockerfile.engine" -t "nexterm-nsg-engine:$VERSION" "$REPO_DIR"
docker build --build-arg "VERSION=$VERSION" -f "$REPO_DIR/Dockerfile.server" -t "nexterm-nsg-server:$VERSION" "$REPO_DIR"
docker build \
    --build-arg "ENGINE_IMAGE=nexterm-nsg-engine:$VERSION" \
    --build-arg "SERVER_IMAGE=nexterm-nsg-server:$VERSION" \
    -t "nexterm-nsg:$VERSION" "$REPO_DIR"

# The control plane requires an exact server/engine version match. Verify the
# engine metadata before the old container is stopped, so a failed build can
# never replace a working deployment.
ENGINE_VERSION="$(docker run --rm --entrypoint /usr/local/bin/nexterm-engine "nexterm-nsg-engine:$VERSION" --help | sed -nE 's/^Nexterm Engine v([^[:space:]]+).*/\1/p' | head -n1)"
[[ "$ENGINE_VERSION" == "$VERSION" ]] || die "Built engine version '$ENGINE_VERSION' does not match server version '$VERSION'."

TIMESTAMP="$(date +%Y%m%d%H%M%S)"
ROLLBACK_TAG="nexterm:rollback-pre-${VERSION}-${TIMESTAMP}"
ROLLBACK_CONTAINER="${CONTAINER}-rollback-${TIMESTAMP}"
docker tag "$OLD_IMAGE" "$ROLLBACK_TAG"

run_container() {
    local image="$1"
    local primary_network=""
    local -a args=(--name "$CONTAINER" --restart "$RESTART_POLICY" --volume "$DATA_MOUNT")
    args+=("${RUN_ENVS[@]}" --env "ENCRYPTION_KEY=$ENCRYPTION_KEY")
    if [[ "$NETWORK_MODE" == "host" ]]; then
        args+=(--network host)
    else
        args+=(--publish "${HOST_PORT}:6989")
        if [[ "$NETWORK_MODE" != "default" && "$NETWORK_MODE" != "bridge" ]]; then
            primary_network="$NETWORK_MODE"
            args+=(--network "$primary_network")
        fi
    fi
    docker run -d "${args[@]}" "$image"

    # AIO containers are often additionally attached to the Nginx Proxy Manager
    # network so reverse proxies can reach the hostname "nexterm". Docker run
    # only accepts one primary network, therefore reattach every other network.
    for network in "${EXISTING_NETWORKS[@]}"; do
        # Docker's template output can contain a trailing empty entry. Passing
        # that to `docker network connect` produces "network name or ID is
        # empty" and would unnecessarily trigger the rollback path.
        [[ -n "$network" ]] || continue
        [[ "$network" == "bridge" || "$network" == "default" || "$network" == "$primary_network" ]] && continue
        docker network connect "$network" "$CONTAINER"
    done
}

ORIGINAL_STOPPED=0
BACKUP_CREATED=0
RESTORING=0

rollback() {
    (( RESTORING )) && return
    RESTORING=1
    trap - ERR INT TERM
    echo "Replacement failed; restoring the original container..." >&2
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    if (( BACKUP_CREATED )); then
        docker rename "$ROLLBACK_CONTAINER" "$CONTAINER"
        docker start "$CONTAINER" >/dev/null
        echo "Original container restored. Inspect: docker logs --tail 80 $CONTAINER" >&2
    elif (( ORIGINAL_STOPPED )); then
        docker start "$CONTAINER" >/dev/null || true
        echo "Original container restarted. Inspect: docker logs --tail 80 $CONTAINER" >&2
    fi
}

on_failure() {
    local status=$?
    rollback
    exit "$status"
}

trap on_failure ERR INT TERM

echo "Replacing '$CONTAINER'; original container retained as '$ROLLBACK_CONTAINER' until validation succeeds."
docker stop "$CONTAINER" >/dev/null
ORIGINAL_STOPPED=1
docker rename "$CONTAINER" "$ROLLBACK_CONTAINER"
BACKUP_CREATED=1
run_container "nexterm-nsg:$VERSION" >/dev/null

sleep "$WAIT_SECONDS"
if ! docker inspect "$CONTAINER" --format '{{.State.Running}}' | grep -qx true; then
    echo "ERROR: Replacement container did not stay running." >&2
    rollback
    exit 1
fi

if [[ "$NETWORK_MODE" != "host" ]] && ! curl --fail --silent --show-error "http://127.0.0.1:${HOST_PORT}/" >/dev/null; then
    echo "ERROR: Replacement container did not pass its local HTTP health check." >&2
    rollback
    exit 1
fi

trap - ERR INT TERM
echo "Migration completed: nexterm-nsg:$VERSION"
echo "Rollback container retained (stopped): $ROLLBACK_CONTAINER"
echo "Rollback image retained: $ROLLBACK_TAG"
docker logs --tail 40 "$CONTAINER"
