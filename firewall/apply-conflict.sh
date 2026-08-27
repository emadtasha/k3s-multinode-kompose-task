#!/usr/bin/env bash
# Applies the Defense-in-Depth conflict: denies YOUR IP on port 80 at the OS
# level, while the cloud Security Group and UFW's general rule both still
# allow port 80 from everywhere else.
#
# Usage: ./apply-conflict.sh <YOUR_PUBLIC_IP>
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <YOUR_PUBLIC_IP>"
  echo "Find your public IP with: curl -s ifconfig.me"
  exit 1
fi

MY_IP="$1"

echo ">>> Current UFW rules before change:"
sudo ufw status numbered

echo ">>> Inserting DENY rule for ${MY_IP} on port 80, at position 1 (highest priority)..."
sudo ufw insert 1 deny from "${MY_IP}" to any port 80

echo ">>> Reloading UFW..."
sudo ufw reload

echo ">>> Current UFW rules after change:"
sudo ufw status numbered

echo ""
echo ">>> Result: the Security Group still allows 0.0.0.0/0 on port 80 (cloud"
echo ">>> perimeter has no idea about this), but UFW now blocks YOUR specific"
echo ">>> IP at the OS level. Test from your own browser/curl -> should fail."
echo ">>> Test from any other IP/device -> should still succeed."
