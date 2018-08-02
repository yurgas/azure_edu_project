#!/usr/bin/env bash

# For testing purposes pfx password hardcoded to 12345

declare agServerName="mytesthost.localdomain"
declare vpnClientName="VPNClient1"

[ "$1" == "" ] || agServerName=$1

[[ -d tmp ]] || mkdir tmp

# Generate CA certificate

if ! [[ -f tmp/CAcert.crt ]]; then
  echo "Generating root CA ...\n"
  openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 \
    -subj "/C=RU/L=Saint-Petersburg/O=My Test Org/CN=Test Azure CA" \
    -keyout tmp/CAkey.key \
    -out tmp/CAcert.crt
fi

# Generate application gateway certificate

if ! [[ -f tmp/${agServerName}.pfx ]]; then
  echo "Generating application gateway certificate ...\n"
  openssl req -new -sha256 -nodes -newkey rsa:2048 \
    -keyout tmp/${agServerName}.key \
    -out tmp/${agServerName}.csr \
    -subj "/C=RU/L=Saint-Petersburg/O=My Test Org/CN=${agServerName}"

  openssl x509 -req -in tmp/${agServerName}.csr -days 365 \
    -CA tmp/CAcert.crt -CAkey tmp/CAkey.key \
    -CAcreateserial \
    -out tmp/${agServerName}.crt

  openssl pkcs12 -export -out tmp/${agServerName}.pfx -inkey tmp/${agServerName}.key -in tmp/${agServerName}.crt \
      -password pass:12345

  base64 -i tmp/${agServerName}.pfx -o tmp/${agServerName}.pfx.base64
fi

# Generate vpn certificate
if ! [[ -f tmp/${vpnClientName}.pfx ]]; then
  echo "Generating vpn client certificate ...\n"
  openssl req -new -sha256 -nodes -newkey rsa:2048 \
    -keyout tmp/${vpnClientName}.key \
    -out tmp/${vpnClientName}.csr \
    -subj "/C=RU/L=Saint-Petersburg/O=My Test Org/CN=${vpnClientName}"

  openssl x509 -req -in tmp/${vpnClientName}.csr -days 365 \
    -CA tmp/CAcert.crt -CAkey tmp/CAkey.key \
    -CAcreateserial \
    -out tmp/${vpnClientName}.crt

  openssl pkcs12 -export -out tmp/${vpnClientName}.pfx -inkey tmp/${vpnClientName}.key -in tmp/${vpnClientName}.crt \
      -password pass:12345
fi
