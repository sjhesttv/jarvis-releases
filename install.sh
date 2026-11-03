#!/usr/bin/env bash
# JARVIS — DigitalOcean / Ubuntu 24.04 installer.
#
# Installs everything a cloud JARVIS needs and leaves the service OFF until
# `sudo jarvis-setup` has asked you for the few things only you know (a
# password, the Fish Audio key, the Claude login). Nothing secret is passed
# to this script, and nothing secret should ever be put in a droplet's
# user-data: DigitalOcean serves user-data to anything on the droplet that
# can reach 169.254.169.254.
#
# Usage (as root):
#   bash install.sh                               # latest public release
#   bash install.sh --release-url URL             # a specific tarball
#   bash install.sh --from-dir /path/to/checkout  # a local tree (testing)
#
# Idempotent: re-running it upgrades the system packages and reinstalls the
# release, and never touches /etc/jarvis or /var/lib/jarvis.
set -euo pipefail

# Where releases are published: files in a PUBLIC repository (latest/), so a
# fresh droplet can download them with no token (docs/deploy-digitalocean.md).
DEFAULT_RELEASE_BASE="${JARVIS_RELEASE_BASE:-https://raw.githubusercontent.com/sjhesttv/jarvis-releases/main/latest}"
RELEASE_URL="${DEFAULT_RELEASE_BASE}/jarvis.tar.gz"
FROM_DIR=""
# Claude Code: pinned, and updated only by `jarvis-update`, never by itself.
CLAUDE_CODE_VERSION="${JARVIS_CLAUDE_CODE_VERSION:-latest}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-url) RELEASE_URL="$2"; shift 2 ;;
    --from-dir)    FROM_DIR="$2"; shift 2 ;;
    --claude-code-version) CLAUDE_CODE_VERSION="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo bash install.sh)." >&2; exit 1; }
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "This installer targets Ubuntu 24.04 (found ${PRETTY_NAME:-unknown})." >&2
  exit 1
fi

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

PREFIX=/opt/jarvis
STATE=/var/lib/jarvis
CONF=/etc/jarvis
export DEBIAN_FRONTEND=noninteractive
# A fresh droplet runs unattended-upgrades at first boot and holds the dpkg
# lock for minutes; wait for it instead of failing. A config file rather
# than a flag, so `playwright install --with-deps` (its own apt-get) waits too.
echo 'DPkg::Lock::Timeout "900";' > /etc/apt/apt.conf.d/90jarvis-lock-wait

say "System packages"
apt-get update -q
apt-get install -y -q --no-install-recommends \
  ca-certificates curl gnupg git python3 python3-venv python3-pip \
  ufw iptables unattended-upgrades gh debian-keyring \
  debian-archive-keyring apt-transport-https jq
# Security updates install themselves.
dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1 || true

say "Node.js 22 (for the Claude Code CLI)"
if ! command -v node >/dev/null 2>&1 || [[ "$(node -p 'process.versions.node.split(".")[0]')" -lt 20 ]]; then
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --batch --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
  apt-get update -q
  apt-get install -y -q nodejs
fi

say "Caddy (HTTPS reverse proxy, automatic Let's Encrypt)"
if ! command -v caddy >/dev/null 2>&1; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --batch --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -q
  apt-get install -y -q caddy
fi
# Caddy stays on its default welcome page until jarvis-setup writes the
# real Caddyfile.

say "Service user"
if ! id jarvis >/dev/null 2>&1; then
  useradd --system --home-dir "$STATE" --create-home --shell /usr/sbin/nologin jarvis
fi
install -d -m 0750 -o jarvis -g jarvis "$STATE"
install -d -m 0700 -o jarvis -g jarvis "$STATE/data" "$STATE/projects"
install -d -m 0750 -o root -g jarvis "$CONF"
install -d -m 0755 "$PREFIX" "$PREFIX/releases"

say "JARVIS release"
STAMP="$(date -u +%Y%m%d%H%M%S)"
DEST="$PREFIX/releases/$STAMP"
mkdir -p "$DEST"
if [[ -n "$FROM_DIR" ]]; then
  # A local tree: copy what git would ship (no node_modules, no data).
  tar -C "$FROM_DIR" --exclude=.git --exclude=node_modules --exclude=data \
      --exclude=.env --exclude='*.pem' --exclude=__pycache__ -cf - . \
    | tar -C "$DEST" -xf -
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL "$RELEASE_URL" -o "$TMP/jarvis.tar.gz"
  # The checksum is published beside the tarball by the release workflow.
  if curl -fsSL "${RELEASE_URL}.sha256" -o "$TMP/jarvis.tar.gz.sha256"; then
    (cd "$TMP" && echo "$(cut -d' ' -f1 jarvis.tar.gz.sha256)  jarvis.tar.gz" | sha256sum -c -)
  else
    echo "No published checksum at ${RELEASE_URL}.sha256 — refusing an unverified release." >&2
    exit 1
  fi
  tar -C "$DEST" --strip-components=1 -xzf "$TMP/jarvis.tar.gz"
fi
echo "$RELEASE_URL" > "$CONF/release-url"

say "Python environment (locked, hash-checked)"
python3 -m venv "$PREFIX/venv"
"$PREFIX/venv/bin/pip" install -q --upgrade pip
"$PREFIX/venv/bin/pip" install -q --require-hashes -r "$DEST/deploy/requirements.lock"

say "Headless Chromium (read_page / look_at_page)"
export PLAYWRIGHT_BROWSERS_PATH="$PREFIX/ms-playwright"
"$PREFIX/venv/bin/python" -m playwright install --with-deps chromium >/dev/null

say "Frontend"
if [[ ! -f "$DEST/frontend/dist/index.html" ]]; then
  # Release tarballs ship it prebuilt; a local tree may not.
  (cd "$DEST/frontend" && npm ci --no-audit --no-fund && npm run build)
  rm -rf "$DEST/frontend/node_modules"
fi

say "Claude Code CLI ($CLAUDE_CODE_VERSION)"
npm install -g --no-audit --no-fund "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" >/dev/null
claude --version

say "Switching to the new release"
ln -sfn "$DEST" "$PREFIX/current"
chown -R root:root "$DEST"
chmod -R a+rX "$DEST"
# Keep the three newest releases for rollback.
ls -1dt "$PREFIX"/releases/*/ 2>/dev/null | tail -n +4 | xargs -r rm -rf

say "Commands and services"
install -m 0755 "$DEST/deploy/jarvis-setup"    /usr/local/sbin/jarvis-setup
install -m 0755 "$DEST/deploy/jarvis-update"   /usr/local/sbin/jarvis-update
install -m 0755 "$DEST/deploy/jarvis-firewall" /usr/local/sbin/jarvis-firewall
install -m 0644 "$DEST/deploy/systemd/jarvis.service"        /etc/systemd/system/jarvis.service
install -m 0644 "$DEST/deploy/systemd/jarvis-egress.service" /etc/systemd/system/jarvis-egress.service
install -m 0755 "$DEST/deploy/profile.d/jarvis.sh" /etc/profile.d/jarvis.sh
systemctl daemon-reload
systemctl enable jarvis-egress.service >/dev/null 2>&1
systemctl start jarvis-egress.service

say "Firewall: SSH, HTTP, HTTPS only"
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null

if systemctl is-enabled jarvis.service >/dev/null 2>&1; then
  say "Restarting JARVIS (already configured)"
  systemctl restart jarvis.service
  echo "Done. JARVIS is running the new release."
else
  cat <<'EOF'

  ─────────────────────────────────────────────────────────────
   JARVIS is installed. One step left — run:

       sudo jarvis-setup

   It asks for a password, your Fish Audio key and your Claude
   login, then starts everything and prints the address to open.
  ─────────────────────────────────────────────────────────────
EOF
fi
