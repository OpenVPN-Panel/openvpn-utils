#!/bin/bash
set -e

CLIENT_NAME="$1"

if [ -z "$CLIENT_NAME" ]; then
  echo "Error: Please specify a client name. Usage: ./addClient.sh client-name"
  exit 1
fi

# === Configuration paths ===
VPN_DIR="$HOME/openvpn"
EASYRSA_SERVER_DIR="$VPN_DIR/easy-rsa-server"
EASYRSA_CA_DIR="$VPN_DIR/easy-rsa"
CLIENT_CONFIGS_DIR="$VPN_DIR/client-configs"
KEYS_DIR="$CLIENT_CONFIGS_DIR/keys"
FILES_DIR="$CLIENT_CONFIGS_DIR/files"

# === Check required directories ===
for dir in "$EASYRSA_SERVER_DIR" "$EASYRSA_CA_DIR" "$CLIENT_CONFIGS_DIR"; do
  if [ ! -d "$dir" ]; then
    echo "Error: Directory not found: $dir"
    exit 1
  fi
done

# === Check if make_config.sh script exists and is executable ===
if [ ! -x "$CLIENT_CONFIGS_DIR/make_config.sh" ]; then
  echo "Error: make_config.sh script not found or not executable"
  exit 1
fi

# === Remove client if it already exists ===
if [ -f "$KEYS_DIR/$CLIENT_NAME.key" ] || [ -f "$KEYS_DIR/$CLIENT_NAME.crt" ]; then
  echo "Client $CLIENT_NAME already exists. Exiting..."
#  bash "$VPN_DIR/delClient.sh" "$CLIENT_NAME"
  exit 1
fi

# === Set ownership of PKI directories ===
sudo chown -R "$(whoami)":"$(whoami)" "$EASYRSA_SERVER_DIR"
sudo chown -R "$(whoami)":"$(whoami)" "$EASYRSA_CA_DIR"

# === [1] Generate client certificate request ===
cd "$EASYRSA_SERVER_DIR"
./easyrsa --batch gen-req "$CLIENT_NAME" nopass
cp "pki/private/$CLIENT_NAME.key" "$KEYS_DIR/"

# === [2] Import request to CA and sign client certificate ===
cd "$EASYRSA_CA_DIR"
./easyrsa import-req "$EASYRSA_SERVER_DIR/pki/reqs/$CLIENT_NAME.req" "$CLIENT_NAME"
./easyrsa --batch sign-req client "$CLIENT_NAME"
cp "pki/issued/$CLIENT_NAME.crt" "$KEYS_DIR/"

# === [3] Generate the client .ovpn configuration file ===
cd "$CLIENT_CONFIGS_DIR"
bash ./make_config.sh "$CLIENT_NAME"

# === [4] Output result path ===
echo "Client configuration file created at:"
echo "$FILES_DIR/$CLIENT_NAME.ovpn"
