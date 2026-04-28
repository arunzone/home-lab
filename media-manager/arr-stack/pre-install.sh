#!/bin/bash

#Setup Traefik certificates
mkdir -p traefik/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout traefik/certs/local.key -out traefik/certs/local.crt \
  -subj "/CN=*.home.arpa"

# Setup Traefik dashboard credential
apt update && apt install apache2-utils -y
TRAEFIK_AUTH=$(htpasswd -nb admin "_H5+=%dW@eK" | sed -e 's/\$/\$\$/g')

# Update TRAEFIK_BASIC_AUTH in .env file
if grep -q "^TRAEFIK_BASIC_AUTH=" .env; then
    # Replace existing TRAEFIK_BASIC_AUTH
    sed -i.bak "s|^TRAEFIK_BASIC_AUTH=.*|TRAEFIK_BASIC_AUTH=$TRAEFIK_AUTH|" .env
else
    # Append TRAEFIK_BASIC_AUTH if it doesn't exist
    echo "TRAEFIK_BASIC_AUTH=$TRAEFIK_AUTH" >> .env
fi