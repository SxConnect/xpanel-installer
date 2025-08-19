#!/bin/bash
# setup-firewall.sh
# Configura o UFW com regras seguras para o xPanel
# github.com/SxConnect/xpanel-installer

set -euo pipefail

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funções
log() { echo -e "[$(date +'%H:%M:%S')] $1"; }
warn() { log "${YELLOW}AVISO: $1${NC}"; }
error() { log "${RED}ERRO: $1${NC}" >&2; exit 1; }
success() { log "${GREEN}OK: $1${NC}"; }

# === Verificar se é root ===
if [ "$EUID" -ne 0 ]; then
    error "Este script requer root. Execute com sudo."
fi

# === Verificar se UFW está instalado ===
if ! command -v ufw &> /dev/null; then
    log "Instalando UFW..."
    apt update && apt install ufw -y || error "Falha ao instalar UFW"
    success "UFW instalado"
fi

# === Mostrar estado atual ===
echo -e "
${BLUE}========================================${NC}
       🔥 CONFIGURAÇÃO DO FIREW

