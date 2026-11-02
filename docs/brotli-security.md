# Brotli CVE-2026-111497 release controls

The server image uses the Node 26.13.0 base already pinned by digest. This version
contains the Node security update for CVE-2026-111497. The engine and aggregate
images require Alpine brotli-libs >= 1.1.1-r0. Native archive/package builds
check the installed distro package before copying linked libraries: Debian 12
requires 1.0.9-2+deb12u1, Debian 13 requires 1.1.0-2+deb13u1, and Alpine
requires brotli-libs >= 1.1.1-r0. Other distributions fail closed for release
packaging until their security backport can be verified explicitly.

Build without stale cache, inspect loaded shared libraries and package origin,
and validate SSH, legacy SSH, SFTP and control-plane compatibility before
publishing or deployment. An existing standalone engine archive bundles its own
libraries: updating the host package does not update the bundled copies. Server
and engine images must be released and deployed together using immutable digests.
The security-build workflow builds isolated candidates and does not publish or
update live systems. The project's release workflow must only be run after its
registry namespace and credentials are confirmed; its current Docker workflow
contains upstream nexterm/* image names.

References: https://nodejs.org/en/blog/vulnerability/october-2026-security-releases
and https://security-tracker.debian.org/tracker/CVE-2026-111497
