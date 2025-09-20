#!/bin/bash
set -e

SERVER_CONF="/etc/openvpn/server/server.conf"

if [ ! -f "$SERVER_CONF" ]; then
  echo "[INIT] No server.conf found, running setup.sh..."
  envsubst < /tmp/server.conf.template > /tmp/server.conf
  envsubst < /tmp/base.conf.template > /tmp/base.conf
  /usr/local/bin/setup.sh
fi

if [ ! -d "$SCRIPTS_DIR" ] || [ -z "$(ls -A $SCRIPTS_DIR)" ]; then
  echo "[INIT] Copying management scripts into volume..."
  cp -r /usr/local/share/openvpn-scripts/* "$SCRIPTS_DIR/"
  chmod +x "$SCRIPTS_DIR"/*.sh
fi

echo "[START] Launching OpenVPN..."
cd /etc/openvpn/server
exec openvpn --config "$SERVER_CONF"
