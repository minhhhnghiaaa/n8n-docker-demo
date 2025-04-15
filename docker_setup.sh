#!/bin/bash

# Exit if any command fails
set -e

echo "🔄 Updating package list..."
sudo apt update
sudo apt upgrade -y

echo "📦 Installing required packages..."
sudo apt install apt-transport-https ca-certificates curl software-properties-common lsb-release gnupg -y

echo "🔑 Adding Docker's official GPG key..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "➕ Adding Docker's APT repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "🔄 Updating package list again (with Docker repo)..."
sudo apt update

echo "🐳 Installing Docker Engine..."
sudo apt install docker-ce docker-ce-cli containerd.io -y

echo "👤 Adding current user to docker group..."
sudo usermod -aG docker $USER

echo "⚙️ Activating new group (you may need to log out and back in)..."
newgrp docker

echo "✅ Docker version:"
docker --version

# ---------------------
# GitHub CLI Setup
# ---------------------

echo "🔑 Adding GitHub CLI GPG key..."
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
&& sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg

echo "➕ Adding GitHub CLI APT repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

echo "🔄 Updating package list again (with GitHub CLI repo)..."
sudo apt update

echo "📦 Installing GitHub CLI (gh)..."
sudo apt install gh -y

echo "✅ GitHub CLI version:"
gh --version

# ---------------------
# Docker Compose Setup
# ---------------------

DOCKER_COMPOSE_VERSION="2.24.6"
