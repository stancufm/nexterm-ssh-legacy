#!/bin/sh
# Guard release artifacts against CVE-2026-111497, including distro backports.
set -eu
. /etc/os-release
case "$ID:$VERSION_ID" in
    alpine:*)
        apk info -e 'brotli-libs>=1.1.1-r0' >/dev/null || {
            echo 'Brotli security fix is missing from Alpine brotli-libs' >&2; exit 1; }
        ;;
    debian:12|debian:13)
        installed=$(dpkg-query -W -f='${Version}' libbrotli1)
        case "$VERSION_ID" in 12) minimum='1.0.9-2+deb12u1' ;; 13) minimum='1.1.0-2+deb13u1' ;; esac
        dpkg --compare-versions "$installed" ge "$minimum" || {
            echo "Brotli security fix is missing: libbrotli1 $installed < $minimum" >&2; exit 1; }
        ;;
    *) echo "Unsupported Brotli security verification platform: $ID $VERSION_ID" >&2; exit 1 ;;
esac
printf 'Brotli security package verified for %s %s\n' "$ID" "$VERSION_ID"
