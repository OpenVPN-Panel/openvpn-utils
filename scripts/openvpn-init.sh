#!/bin/bash
set -e

# === CONFIGURATION ===

VPN_DIR="$HOME/openvpn"
EASYRSA_DIR="$VPN_DIR/easy-rsa"
EASYRSA_SERVER_DIR="$VPN_DIR/easy-rsa-server"
CLIENT_CONFIGS_DIR="$VPN_DIR/client-configs"
SERVER_CONF_DIR="/etc/openvpn/server"
VPN_SERVER_CN="server"
CLIENT_NAME="client1"
PROTO="udp"
PORT=1194
KEY_SIZE=2048
CA_EXPIRE=3650
CERT_EXPIRE=825
PUBLIC_IP=$(hostname -I | awk '{print $1}')
OPENVPN_TMP_DIR="/tmp/openvpn-tmp"

mkdir -p $OPENVPN_TMP_DIR || true
trap "rm -rf $OPENVPN_TMP_DIR" EXIT
LOG="setup.log"
exec > >(tee -i "$LOG") 2>&1

# CA Server
# === [1/3] Installing EasyRSA ==

sudo apt update
sudo apt install easy-rsa -y

# === [2/3] Preparing a Public Key Infrastructure Directory ==

mkdir -p $SERVER_CONF_DIR || true
mkdir -p $EASYRSA_DIR || true
ln -s /usr/share/easy-rsa/* "$EASYRSA_DIR"
chmod 700 "$EASYRSA_DIR"
cd "$EASYRSA_DIR"
sudo ./easyrsa init-pki

# === [3/3] Creating a Certificate Authority ===

cat > vars <<EOF
set_var EASYRSA_REQ_COUNTRY    "RU"
set_var EASYRSA_REQ_PROVINCE   "Moscow"
set_var EASYRSA_REQ_CITY       "Moscow"
set_var EASYRSA_REQ_ORG        "LNKR"
set_var EASYRSA_REQ_EMAIL      "admin@test.com"
set_var EASYRSA_REQ_OU         "Community"
set_var EASYRSA_ALGO           "ec"
set_var EASYRSA_DIGEST         "sha512"
EOF

sudo ./easyrsa --batch build-ca nopass

# OpenVPN Server
# === [1/10] Install OpenVPN and Easy-RSA ===

echo "[1/8] Installing OpenVPN and Easy-RSA..."
sudo apt install -y openvpn curl jq iptables-persistent

mkdir -p $EASYRSA_SERVER_DIR || true
ln -s /usr/share/easy-rsa/* $EASYRSA_SERVER_DIR
#sudo chown admin $EASYRSA_SERVER_DIR
chmod 700 $EASYRSA_SERVER_DIR

# === [2/10] Creating a PKI for OpenVPN ===

echo "[2/8] Initializing Easy-RSA at $EASYRSA_DIR..."
cd $EASYRSA_SERVER_DIR

cat > vars <<EOF
set_var EASYRSA_ALGO           "ec"
set_var EASYRSA_DIGEST         "sha512"
EOF

sudo ./easyrsa init-pki

# === [3/10] Creating an OpenVPN Server Certificate Request and Private Key ===

sudo ./easyrsa --batch gen-req $VPN_SERVER_CN nopass
sudo cp $EASYRSA_SERVER_DIR/pki/private/$VPN_SERVER_CN.key $SERVER_CONF_DIR

# === [4/10] Signing the OpenVPN Servers Certificate Request ===

sudo cp $EASYRSA_SERVER_DIR/pki/reqs/$VPN_SERVER_CN.req $OPENVPN_TMP_DIR
cd $EASYRSA_DIR
sudo ./easyrsa import-req $OPENVPN_TMP_DIR/$VPN_SERVER_CN.req $VPN_SERVER_CN
sudo ./easyrsa --batch sign-req server $VPN_SERVER_CN

sudo cp pki/issued/$VPN_SERVER_CN.crt $OPENVPN_TMP_DIR
sudo cp pki/ca.crt $OPENVPN_TMP_DIR

sudo cp $OPENVPN_TMP_DIR/{$VPN_SERVER_CN.crt,ca.crt} $SERVER_CONF_DIR

# === [5/10] Configuring OpenVPN Cryptographic Material ===

cd $EASYRSA_SERVER_DIR
openvpn --genkey --secret ta.key
sudo cp ta.key $SERVER_CONF_DIR

# === [6/10] Generating a Client Certificate and Key Pair ===

mkdir -p $CLIENT_CONFIGS_DIR/keys || true
chmod -R 700 $CLIENT_CONFIGS_DIR
sudo ./easyrsa --batch gen-req $CLIENT_NAME nopass
sudo cp pki/private/$CLIENT_NAME.key $CLIENT_CONFIGS_DIR/keys/

sudo cp pki/reqs/$CLIENT_NAME.req $OPENVPN_TMP_DIR

cd $EASYRSA_DIR
sudo ./easyrsa import-req $OPENVPN_TMP_DIR/$CLIENT_NAME.req $CLIENT_NAME
sudo ./easyrsa --batch sign-req client $CLIENT_NAME

sudo cp pki/issued/$CLIENT_NAME.crt $OPENVPN_TMP_DIR

sudo cp $OPENVPN_TMP_DIR/$CLIENT_NAME.crt $CLIENT_CONFIGS_DIR/keys/

cp $EASYRSA_SERVER_DIR/ta.key $CLIENT_CONFIGS_DIR/keys/
sudo cp $SERVER_CONF_DIR/ca.crt $CLIENT_CONFIGS_DIR/keys/

# === [7/10] Configuring OpenVPN ===
sudo cp /tmp/server.conf $SERVER_CONF_DIR

# === [8/10] Creating the Client Configuration Infrastructure ===
mkdir -p $CLIENT_CONFIGS_DIR/files || true
sudo cp /tmp/base.conf $CLIENT_CONFIGS_DIR/base.conf

sed -i "s/^remote .*/remote $PUBLIC_IP $PORT/" "$CLIENT_CONFIGS_DIR/base.conf"
sed -i "s/^proto .*/proto $PROTO/" "$CLIENT_CONFIGS_DIR/base.conf"

# --- Create make_config.sh script for client .ovpn generation ---
cat > "$CLIENT_CONFIGS_DIR/make_config.sh" <<EOF
#!/bin/bash

KEY_DIR="$CLIENT_CONFIGS_DIR/keys"
OUTPUT_DIR="$CLIENT_CONFIGS_DIR/files"
BASE_CONFIG="$CLIENT_CONFIGS_DIR/base.conf"

if [ -z "\$1" ]; then
  echo "Usage: \$0 <client-name>"
  exit 1
fi

cat \$BASE_CONFIG \\
  <(echo -e '<ca>') \\
  \$KEY_DIR/ca.crt \\
  <(echo -e '</ca>\\n<cert>') \\
  \$KEY_DIR/\$1.crt \\
  <(echo -e '</cert>\\n<key>') \\
  \$KEY_DIR/\$1.key \\
  <(echo -e '</key>\\n<tls-crypt>') \\
  \$KEY_DIR/ta.key \\
  <(echo -e '</tls-crypt>') \\
  > \$OUTPUT_DIR/\$1.ovpn
EOF

chmod 700 "$CLIENT_CONFIGS_DIR/make_config.sh"

# === [9/10] Generating Client Configurations ===
cd $CLIENT_CONFIGS_DIR
./make_config.sh $CLIENT_NAME

ls $CLIENT_CONFIGS_DIR/files

# === [10/10] Adjusting the OpenVPN Server Networking Configuration ===

grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p >/dev/null 2>&1

DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}')
sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$DEFAULT_IFACE" -j MASQUERADE

sudo netfilter-persistent save
