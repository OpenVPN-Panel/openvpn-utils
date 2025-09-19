#!/bin/bash
set -e

SERVER_CONF="/etc/openvpn/server/server.conf"

if [ ! -f "$SERVER_CONF" ]; then
  echo "[INIT] No server.conf found, running setup.sh..."
  /usr/local/bin/setup.sh
fi

echo "[START] Launching OpenVPN..."
cd /etc/openvpn/server
exec openvpn --config "$SERVER_CONF"
