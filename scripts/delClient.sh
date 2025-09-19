#!/bin/bash

clientName=${1}
adminDir=/home/admin/openvpn
caDir="$adminDir/easy-rsa"
openvpnServerDir="/etc/openvpn/server"

if [ -z "$clientName" ]; then
  echo "Error: Please specify the client name."
  exit 1
fi

matches=$(sudo find "$adminDir" -name "${clientName}*")

if [[ -n "$matches" ]]; then
    echo "The following files were found:"
    echo "$matches"
    echo

    read -p "Are you sure you want to delete these files and revoke the certificate? [y/N]: " confirm

    if [[ "${confirm,,}" == "y" ]]; then

        cd "$caDir" || { echo "Failed to change directory to $caDir"; exit 1; }

        echo "Revoking client certificate..."
        sudo ./easyrsa revoke "$clientName"

        echo "Generating Certificate Revocation List (CRL)..."
        sudo ./easyrsa gen-crl

        sudo cp "$caDir/pki/crl.pem" "$openvpnServerDir/"
        sudo chmod 644 "$openvpnServerDir/crl.pem"

        echo "Deleting client-related files..."
        sudo find "$adminDir" -name "${clientName}*" -exec rm -f {} \;

        echo "Restarting OpenVPN server..."
        sudo systemctl restart openvpn-server@server.service

        echo "Files deleted and certificate revoked successfully."

    else
        echo "Deletion cancelled."
    fi
else
    echo "No files found matching '${clientName}*'. Nothing to delete."
fi
