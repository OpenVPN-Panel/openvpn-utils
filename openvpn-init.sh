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
# === [1/8] Install OpenVPN and Easy-RSA ===

echo "[1/8] Installing OpenVPN and Easy-RSA..."
sudo apt install -y openvpn curl jq iptables-persistent

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

sudo ./easyrsa init-pki

# === [3/8] Creating an OpenVPN Server Certificate Request and Private Key ===

sudo ./easyrsa --batch gen-req $VPN_SERVER_CN nopass
sudo cp $EASYRSA_SERVER_DIR/pki/private/$VPN_SERVER_CN.key $SERVER_CONF_DIR

# === [4/8] Signing the OpenVPN Servers Certificate Request ===

sudo cp $EASYRSA_SERVER_DIR/pki/reqs/$VPN_SERVER_CN.req $OPENVPN_TMP_DIR
cd $EASYRSA_DIR
sudo ./easyrsa import-req $OPENVPN_TMP_DIR/$VPN_SERVER_CN.req $VPN_SERVER_CN
sudo ./easyrsa --batch sign-req server $VPN_SERVER_CN

sudo cp pki/issued/$VPN_SERVER_CN.crt $OPENVPN_TMP_DIR
sudo cp pki/ca.crt $OPENVPN_TMP_DIR

sudo cp $OPENVPN_TMP_DIR/{$VPN_SERVER_CN.crt,ca.crt} $SERVER_CONF_DIR


# === [5/8] Configuring OpenVPN Cryptographic Material ===

cd $EASYRSA_SERVER_DIR
openvpn --genkey --secret ta.key
sudo cp ta.key $SERVER_CONF_DIR

# === [6/8] Generating a Client Certificate and Key Pair ===

mkdir -p $CLIENT_CONFIGS_DIR/keys
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
sudo chown admin.admin $CLIENT_CONFIGS_DIR/keys/*

# === [7/8] Configuring OpenVPN ===
sudo cp /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz $SERVER_CONF_DIR
sudo gunzip $SERVER_CONF_DIR/server.conf.gz

SERVER_CONF=$SERVER_CONF_DIR/server.conf

# 1. Comment out existing tls-auth line and add tls-crypt line after it
sudo sed -i '/^tls-auth / s/^/;/' "$SERVER_CONF"
sudo sed -i '/^;tls-auth /a tls-crypt ta.key' "$SERVER_CONF"

# 2. Comment out existing cipher AES-256-CBC and add cipher AES-256-GCM after it
sudo sed -i '/^cipher AES-256-CBC/ s/^/;/' "$SERVER_CONF"
sudo sed -i '/^;cipher AES-256-CBC/ a cipher AES-256-GCM' "$SERVER_CONF"

# 3. Add auth SHA256 after cipher line (if there is no auth, add after cipher)
if ! grep -q '^auth SHA256' "$SERVER_CONF"; then
  sudo sed -i '/^cipher AES-256-GCM/ a auth SHA256' "$SERVER_CONF"
fi

# 4. Comment out dh line and add "dh none"
sudo sed -i '/^dh / s/^/;/' "$SERVER_CONF"
if ! grep -q '^dh none' "$SERVER_CONF"; then
  sudo sed -i '/^;dh /a dh none' "$SERVER_CONF"
fi

# 5. Uncomment user nobody и group nogroup
sudo sed -i 's/^;user nobody/user nobody/' "$SERVER_CONF"
sudo sed -i 's/^;group nogroup/group nogroup/' "$SERVER_CONF"

# 6. Uncomment push "redirect-gateway def1 bypass-dhcp"
sudo sed -i 's/^;push "redirect-gateway def1 bypass-dhcp"/push "redirect-gateway def1 bypass-dhcp"/' "$SERVER_CONF"

sudo sed -i 's/^;push "dhcp-option DNS 208.67.222.222"/push "dhcp-option DNS 208.67.222.222"/' "$SERVER_CONF"
sudo sed -i 's/^;push "dhcp-option DNS 208.67.220.220"/push "dhcp-option DNS 208.67.220.220"/' "$SERVER_CONF"

# === [9/8] Firewall Configuration ===
# -

# === [10/8] Starting OpenVPN ===

sudo systemctl enable openvpn-server@server.service
sudo systemctl restart openvpn-server@server.service || echo "OpenVPN restart failed, but t we continue"
sudo systemctl status openvpn-server@server.service --no-pager 2>&1 || true

sleep 2

# === [11/8] Creating the Client Configuration Infrastructure ===
mkdir -p $CLIENT_CONFIGS_DIR/files
cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf $CLIENT_CONFIGS_DIR/base.conf

sed -i "s/^remote .*/remote $PUBLIC_IP $PORT/" "$CLIENT_CONFIGS_DIR/base.conf"
sed -i "s/^proto .*/proto $PROTO/" "$CLIENT_CONFIGS_DIR/base.conf"

sed -i 's/^ca /#ca /' "$CLIENT_CONFIGS_DIR/base.conf"
sed -i 's/^cert /#cert /' "$CLIENT_CONFIGS_DIR/base.conf"
sed -i 's/^key /#key /' "$CLIENT_CONFIGS_DIR/base.conf"

echo "cipher AES-256-GCM" >> "$CLIENT_CONFIGS_DIR/base.conf"
echo "auth SHA256" >> "$CLIENT_CONFIGS_DIR/base.conf"
echo "key-direction 1" >> "$CLIENT_CONFIGS_DIR/base.conf"

sed -i '/^key-direction 1/a disable-dco' "$CLIENT_CONFIGS_DIR/base.conf"

# Add commented DNS resolver scripts for Linux clients (resolvconf and systemd-resolved)
cat >> "$CLIENT_CONFIGS_DIR/base.conf" <<'EOF'

# DNS resolver scripts for Linux clients

; script-security 2
; up /etc/openvpn/update-resolv-conf
; down /etc/openvpn/update-resolv-conf

; script-security 2
; up /etc/openvpn/update-systemd-resolved
; down /etc/openvpn/update-systemd-resolved
; down-pre
; dhcp-option DOMAIN-ROUTE .
EOF

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


# === [12/8] Generating Client Configurations ===
cd $CLIENT_CONFIGS_DIR
./make_config.sh $CLIENT_NAME

ls $CLIENT_CONFIGS_DIR/files

# === [8/8] Adjusting the OpenVPN Server Networking Configuration ===

grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p >/dev/null 2>&1

sudo systemctl restart openvpn-server@server.service
sudo systemctl status openvpn-server@server.service --no-pager 2>&1


sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
sudo netfilter-persistent save
