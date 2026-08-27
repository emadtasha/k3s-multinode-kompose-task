#!/usr/bin/env bash
# Run this ON the target VM (Ubuntu/Debian). Installs nginx and configures UFW.
set -euo pipefail

echo ">>> Installing nginx..."
sudo apt-get update -y
sudo apt-get install -y nginx

echo ">>> Confirming nginx is running..."
sudo systemctl enable nginx
sudo systemctl start nginx
curl -sI http://localhost | head -5

echo ">>> Installing/enabling UFW..."
sudo apt-get install -y ufw

# Always allow SSH first so you don't lock yourself out before enabling UFW
sudo ufw allow OpenSSH

echo ">>> Allowing HTTP (80) from anywhere..."
sudo ufw allow 80/tcp

echo ">>> Enabling UFW..."
sudo ufw --force enable

echo ">>> Current UFW status:"
sudo ufw status verbose

echo ""
echo ">>> Base setup complete. nginx installed, UFW enabled with SSH + HTTP allowed."
echo ">>> Next: run the conflict step separately with YOUR specific public IP:"
echo "    sudo ufw insert 1 deny from <YOUR_PUBLIC_IP> to any port 80"
