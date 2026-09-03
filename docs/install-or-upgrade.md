# One-command install or upgrade

Docker, Git and OpenSSL must be installed. Run `sudo -i` first, then download and run the bootstrap script:

```bash
host=raw.githubusercontent.com
path=stancufm/nexterm-ssh-legacy/v1.2.2-nsg.10/scripts/install-or-upgrade.sh
curl -fsS "https://$host/$path" -o /tmp/nexterm-nsg.sh
bash /tmp/nexterm-nsg.sh
```

For a new server behind Nginx Proxy Manager, pass the shared Docker network, for example `bash /tmp/nexterm-nsg.sh --network npm_default`. For an existing instance, the script preserves its volume, encryption key, environment and attached Docker networks automatically.
