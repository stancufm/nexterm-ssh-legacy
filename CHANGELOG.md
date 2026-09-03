# Changelog

## v1.2.2-nsg.9

- Makes upgrades transactional: the previous container is kept intact under a rollback name until the replacement passes its HTTP health check.
- Automatically restores the original container if the upgrade fails or is interrupted, preserving its exact Docker configuration and network attachments.
- Prevents a fresh installation from overwriting the path to existing orphaned Nexterm data when a container was removed unexpectedly.

## v1.2.2-nsg.8

- Documented the NSG SSH Legacy fork, its security model and deployment path.
- Added a reproducible install-or-upgrade entry point for Docker deployments.

## v1.2.2-nsg.6

- Added Telnet servers with optional automatic username/password login using existing saved identities.

## v1.2.2-nsg.5

- Migration now preserves every Docker network attached to the previous container, including Nginx Proxy Manager networks.

## v1.2.2-nsg.4

- Added the safe existing-AIO migration script with automatic rollback.

## v1.2.2-nsg.3

- Aligned server and engine release versions.

## v1.2.2-nsg.2

- Applied legacy SSH crypto settings to automated command and monitoring paths.

## v1.2.2-nsg.1

- Added opt-in legacy SSH cryptographic compatibility for interactive sessions and SFTP.
