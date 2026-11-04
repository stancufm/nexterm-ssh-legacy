#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/assets" "$tmp/out"
printf 'verified test payload\n' > "$tmp/assets/nexterm-engine-linux-x64.tar.gz"
(cd "$tmp/assets" && sha256sum nexterm-engine-linux-x64.tar.gz > SHA256SUMS.txt)
cat > "$tmp/bin/curl" <<'SH'
#!/usr/bin/env bash
set -e
while (($#)); do case "$1" in https://*) u=$1 ;; -o) shift; o=$1 ;; esac; shift; done
cp "$TEST_ASSETS/${u##*/}" "$o"
SH
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH" TEST_ASSETS="$tmp/assets"
source "$root/scripts/release-common.sh"
release_fetch v1.2.2-nsg.17 nexterm-engine-linux-x64.tar.gz "$tmp/out"
printf 'tampered\n' >> "$tmp/assets/nexterm-engine-linux-x64.tar.gz"
if (release_fetch v1.2.2-nsg.17 nexterm-engine-linux-x64.tar.gz "$tmp/out"); then echo 'Tampered archive was accepted' >&2; exit 1; fi
cp "$tmp/assets/SHA256SUMS.txt" "$tmp/assets/checksum-original"
cat "$tmp/assets/checksum-original" >> "$tmp/assets/SHA256SUMS.txt"
if (release_fetch v1.2.2-nsg.17 nexterm-engine-linux-x64.tar.gz "$tmp/out"); then echo 'Duplicate checksum was accepted' >&2; exit 1; fi
if (release_fetch 'v1/../../bad' nexterm-engine-linux-x64.tar.gz "$tmp/out"); then echo 'Invalid tag was accepted' >&2; exit 1; fi
echo 'PASS: release integrity checks'
