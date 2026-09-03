[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]
[![Release][release-shield]][release-url]

<br />
<p align="center">
  <a href="https://github.com/gnmyt/Nexterm">
    <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://i.imgur.com/WhNYRgX.png">
        <img alt="Nexterm Banner" src="https://i.imgur.com/TBMT7dt.png">
    </picture>
  </a>
</p>

## 🤔 What is Nexterm?

Nexterm is an open-source server management software that allows you to:

-   Connect remotely via SSH, VNC and RDP
-   Manage files through SFTP
-   Deploy applications via Docker
-   Manage Proxmox LXC and QEMU containers
-   Secure access with two-factor authentication and OIDC SSO
-   Separate users and servers into Organizations

## NSG SSH Legacy fork

This repository is a maintained fork of Nexterm for networks that manage both
modern infrastructure and long-lived appliances. It retains Nexterm's current
defaults while adding a narrowly-scoped compatibility option for devices that
cannot negotiate current SSH cryptography.

### Why this fork exists

Some network appliances, serial-console servers, firewalls and legacy Linux
systems only offer algorithms that current SSH clients deliberately disable:
older key-exchange methods, SHA-1 based host-key signatures, legacy ciphers or
small Diffie-Hellman groups. Standard Nexterm correctly rejects those
connections. The result was that operators had to leave Nexterm and use a
separate, less auditable client for those devices.

The fork makes compatibility **per server and opt-in**. Modern SSH servers keep
the upstream-secure algorithm set. For a legacy target, enable **Legacy SSH
Compatibility** in that server's settings. The same choice is used consistently
for interactive SSH, SFTP, automated commands and monitoring.

Legacy cryptography reduces transport security. Use it only on trusted internal
networks, restrict it to the affected targets, and replace or upgrade the
device whenever possible. Telnet is also unencrypted; use it only where the
network path is trusted.

### Additional functionality

- Telnet entries can attach an existing password identity. Automatic login is
  deliberately opt-in: configure the exact username and password prompts
  emitted by the device, then Nexterm sends each saved value only after its
  matching prompt appears. With no configured prompts or no identity, Telnet
  remains a manual terminal session.
- The safe migration script preserves existing data, the encryption key,
  environment, published port, restart policy and attached Docker networks.
  This includes networks shared with Nginx Proxy Manager.
- The unified installer either creates a new instance or upgrades an existing
  one, retaining a timestamped rollback image on upgrades.

See [CHANGELOG.md](CHANGELOG.md) for release-by-release details and
[installation and upgrade instructions](docs/install-or-upgrade.md).

## 📷 Screenshots

<table>
  <tr>
    <td><img src="docs/public/assets/showoff/servers.png" alt="Servers" /></td>
    <td><img src="docs/public/assets/showoff/connections.png" alt="Connections" /></td>
    <td><img src="docs/public/assets/showoff/sftp.png" alt="SFTP" /></td>
  </tr>
  <tr>
    <td><img src="docs/public/assets/showoff/snippets.png" alt="Snippets" /></td>
    <td><img src="docs/public/assets/showoff/monitoring.png" alt="Monitoring" /></td>
    <td><img src="docs/public/assets/showoff/recordings.png" alt="Recordings" /></td>
  </tr>
</table>

## 🚀 Install

You can install Nexterm by clicking [here](https://docs.nexterm.dev/installation).

### Migrate an existing Docker AIO instance

For an existing Nexterm AIO installation that already contains data, use the
[safe migration script](docs/migrate-existing-instance.md). It preserves the
data volume and encryption key, validates the replacement, and retains a
rollback image.

For a new installation or an automated upgrade, use the [install-or-upgrade
script](docs/install-or-upgrade.md).

## 💻 Development

### Prerequisites

-   Node.js 18+
-   Yarn
-   FlatBuffers compiler (`flatc`)
-   Docker (optional)

Install FlatBuffers:

| Platform | Command |
|----------|---------|
| macOS | `brew install flatbuffers` |
| Ubuntu / Debian | `sudo apt install flatbuffers-compiler` |
| Windows | `winget install Google.FlatBuffers` |

### Local Setup

#### Clone the repository

```sh
git clone https://github.com/gnmyt/Nexterm.git
cd Nexterm
```

#### Configure environment

Create a local environment file:

```sh
cp .env.example .env
```

Make sure `ENCRYPTION_KEY` is set in `.env`.

You can generate a secure key using:

| Platform | Command |
|----------|---------|
| macOS / Linux | `openssl rand -hex 32` |

#### Install dependencies

```sh
yarn install
cd client && yarn install
cd ..
```

#### Generate FlatBuffers schemas

```sh
yarn schema:generate
```

This step is required before starting the development server.

#### Start development mode

```sh
yarn dev
```

#### Start an engine

The development server does not automatically start an engine. To connect to servers, an engine must be running separately:

```sh
yarn dev:engine
```

If using local engine registration, set `LOCAL_ENGINE_TOKEN` in the server environment and use the same value as `REGISTRATION_TOKEN` for the engine.

## 🔧 Configuration

### Docker Images

| Image            | Description                                              |
|------------------|----------------------------------------------------------|
| `nexterm/aio`    | All-In-One — server, client, and engine bundled together |
| `nexterm/server` | Server + web client only (requires external engine)      |
| `nexterm/engine` | Engine only                                              |

The server listens on port 6989 by default. You can modify this behavior using environment variables:

- `SERVER_PORT`: Server listening port (default: 6989)
- `CONTROL_PLANE_PORT`: TCP port for engine communication (default: 7800)
- `NODE_ENV`: Runtime environment (development/production)
- `ENCRYPTION_KEY`: Encryption key for passwords, SSH keys and passphrases. Supports Docker secrets via
  /run/secrets/encryption_key`
- `AI_SYSTEM_PROMPT`: Extra instructions appended to the AI assistant's system prompt (example: Always explain destructive commands before running them.)
- `LOG_LEVEL`: Logging level for application and engine (system/info/verbose/debug/warn/error, default: system)
- `TRUST_PROXY`: Number of reverse proxies in front of Nexterm, so logs and audits show the real client IP instead of the
  proxy's (default: disabled). Use `1` for a single Nginx/Traefik, or pass trusted addresses (`10.10.10.10,192.168.0.0/16`).
  Only enable this if your proxy sets `X-Forwarded-For`, otherwise clients can spoof their IP.

## 🛡️ Security

-   Two-factor authentication
-   Session management
-   Password encryption
-   Docker container isolation
-   Oauth 2.0 OpenID Connect SSO

## 🤝 Contributing

Contributions are welcome! Please feel free to:

1. Fork the project
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 🔗 Useful Links

-   [Documentation](https://docs.nexterm.dev)
-   [Discord](https://dc.gnmyt.dev)
-   [Report a bug](https://github.com/gnmyt/Nexterm/issues)
-   [Request a feature](https://github.com/gnmyt/Nexterm/issues)

## 💜 Powered by

[![JetBrains logo](https://resources.jetbrains.com/storage/products/company/brand/logos/jetbrains.svg)](https://jb.gg/OpenSource)

## 📄 License

Distributed under the MIT license. See `LICENSE` for more information.

[contributors-shield]: https://img.shields.io/github/contributors/gnmyt/Nexterm.svg?style=for-the-badge
[contributors-url]: https://github.com/gnmyt/Nexterm/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/gnmyt/Nexterm.svg?style=for-the-badge
[forks-url]: https://github.com/gnmyt/Nexterm/network/members
[stars-shield]: https://img.shields.io/github/stars/gnmyt/Nexterm.svg?style=for-the-badge
[stars-url]: https://github.com/gnmyt/Nexterm/stargazers
[issues-shield]: https://img.shields.io/github/issues/gnmyt/Nexterm.svg?style=for-the-badge
[issues-url]: https://github.com/gnmyt/Nexterm/issues
[license-shield]: https://img.shields.io/github/license/gnmyt/Nexterm.svg?style=for-the-badge
[license-url]: https://github.com/gnmyt/Nexterm/blob/master/LICENSE
[release-shield]: https://img.shields.io/github/v/release/gnmyt/Nexterm.svg?style=for-the-badge
[release-url]: https://github.com/gnmyt/Nexterm/releases/latest
