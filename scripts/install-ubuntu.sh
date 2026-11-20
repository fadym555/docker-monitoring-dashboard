#!/usr/bin/env bash
# Bootstrap a fresh Ubuntu 22.04 / 24.04 server (for example an AWS EC2 instance)
# and start the monitoring stack.
#
# Usage:  sudo bash scripts/install-ubuntu.sh [domain]
# Without a domain, the dashboard is served at <public-ip>.sslip.io with a real
# Let's Encrypt certificate.
set -euo pipefail

DOMAIN=${1:-}
REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo." >&2
  exit 1
fi

echo "==> Installing Docker Engine"
apt-get update -y
apt-get install -y ca-certificates curl jq openssl ufw
if ! command -v docker >/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    >/etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

echo "==> Enabling Docker engine metrics"
mkdir -p /etc/docker
[[ -f /etc/docker/daemon.json ]] || echo '{}' >/etc/docker/daemon.json
jq -s '.[0] * .[1]' /etc/docker/daemon.json "$REPO_DIR/docker/daemon.json" >/etc/docker/daemon.json.new
mv /etc/docker/daemon.json.new /etc/docker/daemon.json
systemctl enable docker
systemctl restart docker

echo "==> Firewall: allow only SSH, HTTP and HTTPS"
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "==> Writing .env"
cd "$REPO_DIR"
if [[ ! -f .env ]]; then
  cp .env.example .env
  sed -i "s/^GRAFANA_ADMIN_PASSWORD=.*/GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 16)/" .env
  chmod 600 .env
fi
if [[ -z $DOMAIN ]] && grep -q '^DOMAIN=localhost$' .env; then
  ip=$(curl -fsS https://checkip.amazonaws.com)
  DOMAIN="${ip//./-}.sslip.io"
fi
if [[ -n $DOMAIN ]]; then
  sed -i "s/^DOMAIN=.*/DOMAIN=$DOMAIN/" .env
fi

echo "==> Starting the stack"
docker compose up -d --wait --wait-timeout 300

domain=$(grep '^DOMAIN=' .env | cut -d= -f2)
cat <<EOF

Done.
  Dashboard:    https://$domain
  Admin login:  ssh -L 3000:127.0.0.1:3000 <user>@<server>, then open http://localhost:3000
                (user and password are in $REPO_DIR/.env)
EOF
