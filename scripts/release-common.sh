#!/usr/bin/env bash
# Shared helpers. Checksums detect corruption; they are not signatures.
set -Eeuo pipefail
RELEASE_REPO=${NEXTERM_RELEASE_REPO:-stancufm/nexterm-ssh-legacy}
release_fetch() {
    local tag=$1 asset=$2 dest=$3 base
    [[ $tag =~ ^v[0-9][0-9A-Za-z.+_-]*$ ]] || { echo 'Invalid release tag' >&2; return 1; }
    [[ $RELEASE_REPO =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo 'Invalid repository' >&2; return 1; }
    base="https://github.com/$RELEASE_REPO/releases/download/$tag"
    curl -fLsS --retry 2 --proto '=https' --tlsv1.2 "$base/SHA256SUMS.txt" -o "$dest/SHA256SUMS.txt"
    curl -fLsS --retry 2 --proto '=https' --tlsv1.2 "$base/$asset" -o "$dest/$asset"
    local expected actual
    expected=$(awk -v f="$asset" '$2==f {print $1; n++} END {if(n!=1) exit 1}' "$dest/SHA256SUMS.txt") || { echo "Missing or duplicate checksum for $asset" >&2; return 1; }
    [[ $expected =~ ^[0-9a-fA-F]{64}$ ]] || { echo 'Invalid checksum' >&2; return 1; }
    actual=$(sha256sum "$dest/$asset" | awk '{print $1}')
    [[ $(printf %s "$actual" | tr "[:upper:]" "[:lower:]") == $(printf %s "$expected" | tr "[:upper:]" "[:lower:]") ]] || { echo "Checksum mismatch for $asset" >&2; return 1; }
    echo "Verified $asset SHA-256 $actual"
}
