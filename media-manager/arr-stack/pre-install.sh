#!/bin/bash

set -euo pipefail

# Setup SSL certificates
mkdir -p traefik/certs
if [ ! -f "traefik/certs/local.crt" ]; then
    echo "Generating SSL certificate..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout traefik/certs/local.key -out traefik/certs/local.crt \
        -subj "/CN=*.home.arpa"
    echo "SSL certificate generated!"
else
    echo "SSL certificate exists, skipping"
fi

# Setup authentication
if ! command -v htpasswd &> /dev/null; then
    echo "Installing apache2-utils..."
    apt update && apt install apache2-utils -y
fi

if [ -z "${TRAEFIK_ADMIN_PASSWORD:-}" ]; then
    echo "Error: TRAEFIK_ADMIN_PASSWORD not set"
    echo "Set it with: export TRAEFIK_ADMIN_PASSWORD=\"your_password\""
    exit 1
fi

echo "Generating authentication hash..."
TRAEFIK_AUTH=$(htpasswd -nb admin "$TRAEFIK_ADMIN_PASSWORD" | sed -e 's/\$/\$\$/g')

if grep -q "^TRAEFIK_BASIC_AUTH=" .env; then
    echo "Updating TRAEFIK_BASIC_AUTH in .env..."
    sed -i.bak "s|^TRAEFIK_BASIC_AUTH=.*|TRAEFIK_BASIC_AUTH=$TRAEFIK_AUTH|" .env
else
    echo "Adding TRAEFIK_BASIC_AUTH to .env..."
    echo "TRAEFIK_BASIC_AUTH=$TRAEFIK_AUTH" >> .env
fi

echo "Setup completed!"