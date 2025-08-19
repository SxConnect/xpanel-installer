#!/bin/bash
# bootstrap - Ponto de entrada seguro para o instalador do xPanel
# github.com/SxConnect/xpanel-installer

set -euo pipefail

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "[$(date +'%H:%M:%S')] $1"
}

error() {
    log "${RED}ERRO: $1${NC}" >&2
    exit 1
}

success() {
    log "${GREEN}SUCESSO: $1${NC}"
}

# === 0. Início ===
log "🔐 xPanel Installer Seguro (bootstrap)"
log "📦 Clonando repositório oficial..."

# === 1. Definir diretórios ===
REPO="https://github.com/SxConnect/xpanel-installer.git"
INSTALL_DIR="/opt/xpanel-installer"

# === 2. Remover instalação anterior (se existir) ===
if [ -d "$INSTALL_DIR" ]; then
    log "Removendo instalação anterior..."
    rm -rf "$INSTALL_DIR"
fi

# === 3. Clonar repositório ===
mkdir -p "$INSTALL_DIR"
git clone "$REPO" "$INSTALL_DIR" || error "Falha ao clonar o repositório"

success "Repositório clonado em $INSTALL_DIR"

# === 4. Entrar na pasta e executar install.sh ===
cd "$INSTALL_DIR/utils"

log "🚀 Iniciando instalador principal..."
exec "./install.sh"