# Upgrading from release artifacts

The release updater downloads the selected tag's Linux x86_64 image or native engine and its SHA256SUMS.txt over HTTPS, then checks SHA-256 and checks the embedded version before stopping the old service. SHA-256 detects corruption; the checksum is published alongside the binaries and is not an independent signature. Trust the repository and GitHub release publishing process. Use explicitly reviewed tags, including prereleases when appropriate. No implicit latest-release lookup or automatic scheduler is used.

All components of a deployment must use exactly matching versions. Coordinate the controller and remote engines: update the controller first, then immediately update its engines. Existing connections and monitoring are interrupted during the upgrade; the native and Compose-engine scripts require the new controller to accept the engine or they roll it back. Rolling one component back alone to a mismatched version will prevent it connecting; roll the coordinated deployment back together if needed.

From a trusted checkout that contains the updater scripts, as root on each host:

```bash
# Compose-managed controller or containerized engine. Always pass absolute path.
bash scripts/upgrade-compose-release.sh v1.2.2-nsg.17 /opt/nexterm-nsg/compose.yml nexterm
bash scripts/upgrade-compose-release.sh v1.2.2-nsg.17 /opt/nexterm-shadow-nsg-engine/compose.yml engine

# Standalone Docker AIO: supported only for a host-networked container with one
# writable named /app/data volume and the standard options checked by the script.
bash scripts/upgrade-standalone-release.sh v1.2.2-nsg.17 nexterm

# Native engine controlled by systemd; existing config, tokens, and certs remain.
bash scripts/upgrade-native-engine-release.sh v1.2.2-nsg.17 nexterm-engine.service
```

The native updater retains the previous installation directory and requires the service to report that the matching controller accepted it. The Compose updater saves its old image, configuration, and a consistent offline copy of `/app/data` when present; it writes `<compose.yml>.nexterm-release.yml`. Include both `-f <compose.yml> -f <compose.yml>.nexterm-release.yml` for future Compose commands, including after reboot. If the service is an engine without `/app/data`, the updater verifies that the controller accepts it; other services without `/app/data` are unsupported.

The standalone updater rejects nonstandard container settings rather than silently dropping them. It retains the old stopped container and a consistent offline data copy. Each updater automatically restores its prior component and data if replacement or validation fails. Backup directories are root-only and may include secrets. Do not run multiple upgrades of the same component concurrently. If a restored data snapshot replaces data written after the backup, that newer data is lost; plan a maintenance window.

The artifact filename is currently Linux x86_64 only. The image archive retains its internal CI tag; the updater restores any preexisting tag overwritten by `docker load` and uses the verified image ID for deployment. These scripts do not themselves publish artifacts for future versions: each future GitHub release must include both artifact names and a SHA256SUMS.txt generated from its own validated build.
