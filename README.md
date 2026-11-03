# JARVIS releases

Public release files for the cloud (DigitalOcean) deployment of JARVIS.
Built from the private source repository by its release workflow; do not
edit by hand.

| File | What |
|---|---|
| `install.sh` | Installer for a fresh Ubuntu 24.04 droplet |
| `cloud-init.yaml` | Paste into DigitalOcean's "user data" when creating a droplet |
| `latest/jarvis.tar.gz` | The current release (`latest/VERSION`), checked against `latest/jarvis.tar.gz.sha256` |
| `releases/<tag>/` | Every published version |

## Install

On a new Ubuntu 24.04 droplet (2 vCPU / 4 GB recommended), either paste
`cloud-init.yaml` as the droplet's user data, or as root:

```bash
curl -fsSL https://raw.githubusercontent.com/sjhesttv/jarvis-releases/main/install.sh -o install.sh
```

```bash
sudo bash install.sh
```

Then:

```bash
sudo jarvis-setup
```

JARVIS is licensed for personal, non-commercial use; see `LICENSE` inside the
tarball.
