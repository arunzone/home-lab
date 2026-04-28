#!/bin/bash

#Setup Traefik certificates
mkdir -p traefik/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout traefik/certs/local.key -out traefik/certs/local.crt \
  -subj "/CN=*.home.arpa"

# Setup Traefik dashboard credential
if ! command -v htpasswd &> /dev/null; then
    echo "htpasswd not found, installing apache2-utils..."
    apt update && apt install apache2-utils -y
else
    echo "htpasswd already installed, skipping apache2-utils installation"
fi
# Check if TRAEFIK_ADMIN_PASSWORD is set
if [ -z "$TRAEFIK_ADMIN_PASSWORD" ]; then
    echo "Error: TRAEFIK_ADMIN_PASSWORD environment variable is not set"
    echo "Please set the password and try again:"
    echo "export TRAEFIK_ADMIN_PASSWORD=\"your_secure_password\""
    exit 1
fi

TRAEFIK_AUTH=$(htpasswd -nb admin "$TRAEFIK_ADMIN_PASSWORD" | sed -e 's/\$/\$\$/g')

# Update TRAEFIK_BASIC_AUTH in .env file
if grep -q "^TRAEFIK_BASIC_AUTH=" .env; then
    # Replace existing TRAEFIK_BASIC_AUTH
    echo "Updating existing TRAEFIK_BASIC_AUTH in .env file..."
    sed -i.bak "s|^TRAEFIK_BASIC_AUTH=.*|TRAEFIK_BASIC_AUTH=$TRAEFIK_AUTH|" .env
    echo "TRAEFIK_BASIC_AUTH updated successfully!"
else
    # Append TRAEFIK_BASIC_AUTH if it doesn't exist
    echo "Adding TRAEFIK_BASIC_AUTH to .env file..."
    echo "TRAEFIK_BASIC_AUTH=$TRAEFIK_AUTH" >> .env
    echo "TRAEFIK_BASIC_AUTH added successfully!"
fi