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
PUBLIC_IP=$(curl -s ifconfig.me)
OPENVPN_TMP_DIR="/tmp/openvpn-tmp"

# CA Server
# === [1/3] Installing EasyRSA ==

sudo apt update
sudo apt install easy-rsa -y

# === [2/3] Preparing a Public Key Infrastructure Directory ==

mkdir $OPENVPN_TMP_DIR
sudo chown admin:admin -R $OPENVPN_TMP_DIR

mkdir -p "$EASYRSA_DIR"
ln -s /usr/share/easy-rsa/* "$EASYRSA_DIR"
chmod 700 "$EASYRSA_DIR"
cd "$EASYRSA_DIR"
./easyrsa init-pki

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

./easyrsa build-ca nopass

# OpenVPN Server
# === [1/8] Install OpenVPN and Easy-RSA ===

echo "[1/8] Installing OpenVPN and Easy-RSA..."
sudo apt install -y openvpn curl jq

mkdir -p $EASYRSA_SERVER_DIR
ln -s /usr/share/easy-rsa/* $EASYRSA_SERVER_DIR
sudo chown admin $EASYRSA_SERVER_DIR
chmod 700 $EASYRSA_SERVER_DIR

# === [2/8] Creating a PKI for OpenVPN ===


echo "[2/8] Initializing Easy-RSA at $EASYRSA_DIR..."
cd $EASYRSA_SERVER_DIR

cat > vars <<EOF
set_var EASYRSA_ALGO           "ec"
set_var EASYRSA_DIGEST         "sha512"
EOF

./easyrsa init-pki

# === [3/8] Creating an OpenVPN Server Certificate Request and Private Key ===

./easyrsa gen-req "$VPN_SERVER_CN" nopass
sudo cp $EASYRSA_SERVER_DIR/pki/private/$VPN_SERVER_CN.key $SERVER_CONF_DIR

# === [4/8] Signing the OpenVPN Servers Certificate Request ===

sudo cp $EASYRSA_SERVER_DIR/pki/reqs/$VPN_SERVER_CN.req $OPENVPN_TMP_DIR
cd $EASYRSA_DIR
sudo ./easyrsa import-req $OPENVPN_TMP_DIR/$VPN_SERVER_CN.req $VPN_SERVER_CN

# === [5/8] Configuring OpenVPN Cryptographic Material ===

cd $EASYRSA_SERVER_DIR
openvpn --genkey --secret ta.key
sudo cp ta.key $SERVER_CONF_DIR

# === [6/8] Generating a Client Certificate and Key Pair ===

mkdir -p $CLIENT_CONFIGS_DIR/keys
chmod -R 700 $CLIENT_CONFIGS_DIR
cd $EASYRSA_SERVER_DIR
./easyrsa gen-req $CLIENT_NAME nopass
cp pki/private/$CLIENT_NAME.key $CLIENT_CONFIGS_DIR/keys/

sudo cp pki/reqs/$CLIENT_NAME.req $OPENVPN_TMP_DIR

cd $EASYRSA_DIR
./easyrsa import-req $OPENVPN_TMP_DIR/$CLIENT_NAME.req $CLIENT_NAME
./easyrsa sign-req client $CLIENT_NAME

sudo cp pki/issued
