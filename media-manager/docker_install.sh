# Add Docker's official GPG key:
apt update
apt install ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt update

# Install Docker
apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Wait for Docker daemon to be ready
echo "Waiting for Docker daemon to be ready..."
for i in {1..10}; do
    if docker info &> /dev/null; then
        echo "Docker daemon is ready"
        break
    fi
    echo "Waiting for Docker... ($i/10)"
    sleep 1
done

# Function to verify Docker installation
verify_docker() {
    if systemctl status docker &> /dev/null; then
        echo "Docker installation successful!"
        echo "Docker version: $(docker --version)"
        return 0
    else
        echo "ERROR: Docker installation failed or service is not running"
        return 1
    fi
}

# Function to start Docker service
start_docker() {
    echo "Attempting to start Docker service..."
    systemctl start docker
    if systemctl status docker &> /dev/null; then
        echo "Docker service started successfully"
        echo "Docker version: $(docker --version)"
        return 0
    else
        echo "ERROR: Failed to start Docker service"
        return 1
    fi
}

# Function to verify Docker Compose
verify_docker_compose() {
    if docker compose &> /dev/null; then
        echo "Docker Compose is available"
        echo "Docker Compose version: $(docker compose version)"
        return 0
    else
        echo "ERROR: Docker Compose is not available"
        return 1
    fi
}

# Main verification logic
if ! verify_docker; then
    if ! start_docker; then
        echo "Please check the installation manually"
        exit 1
    fi
fi

# Verify Docker Compose
if ! verify_docker_compose; then
    exit 1
fi