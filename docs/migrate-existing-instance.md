# Migrating an existing Nexterm AIO instance

This script migrates a Docker-based Nexterm AIO instance to Nexterm SSH Legacy while retaining the existing `/app/data` volume, encryption key, published port, restart policy, environment, and Docker networks. This includes a shared Nginx Proxy Manager network, so proxy hosts that forward to `nexterm:6989` continue to work.

It builds the release locally before changing the running container. A timestamped rollback image is retained, and the script automatically restores it if the replacement fails its startup check. It never removes the data volume.

## Run it

Log in with an account that has `sudo`, then start a root shell separately:

```bash
sudo -i
```

Clone the release and run the script from that checkout:

```bash
host=github.com
project=stancufm/nexterm-ssh-legacy.git
remote="https://$host/$project"
src=$(mktemp -d /opt/nexterm-nsg.XXXXXX)

GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch v1.2.2-nsg.5 "$remote" "$src"
cd "$src"
./scripts/migrate-existing-aio.sh --apply
```

After a successful migration, open **Settings → Engines** and confirm that the local engine is connected and reports the matching release version.

## Roll back manually

The script prints the rollback image tag. To use it, retain the same data volume and encryption configuration, then recreate the container from that tag. In most cases automatic rollback means this manual procedure is unnecessary.
