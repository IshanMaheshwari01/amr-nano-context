#!/usr/bin/env bash
# One-time setup on Ubuntu. Run with: bash scripts/00_setup_ubuntu.sh
set -euo pipefail

echo "==> System packages"
sudo apt-get update
sudo apt-get install -y curl wget git unzip pigz default-jre-headless python3-pip

echo "==> Docker"
if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER"
    echo "!! Log out and back in (or run 'newgrp docker') before continuing."
fi

echo "==> Nextflow"
if ! command -v nextflow >/dev/null 2>&1; then
    curl -fsSL https://get.nextflow.io | bash
    sudo mv nextflow /usr/local/bin/
fi
nextflow -version

echo "==> Helper tools for data prep (conda-free, via pip/apt where possible)"
pip3 install --user --break-system-packages pandas pytest ruff || pip3 install --user pandas pytest ruff

echo "==> SRA/ENA download helper"
# ENA serves plain FTP/HTTP, so no toolkit is needed - see scripts/01_get_data.sh

echo
echo "Setup done. Check:  docker run --rm hello-world"
