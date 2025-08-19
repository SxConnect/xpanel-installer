#!/bin/bash
# check-system.sh
# Verifica se o sistema atende aos requisitos para rodar o xPanel
# github.com/SxConnect/xpanel-installer

set -euo pipefail

# Cores
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "[$(date +'%H:%M:%S')] $1"
}

error() {
    log "${RED}ERRO: $1${NC}" >&2
    exit 1
}

warn() {
    log "${YELLOW}AVISO: $1${NC}"
}

success() {
    log "${GREEN}OK: $1${NC}"
}

# === 1. Verificar SO ===
if ! command -v lsb_release &> /dev/null; then
    error "Comando 'lsb_release' não encontrado. Requerido: Ubuntu"
fi

OS=$(lsb_release -is)
if [[ "$OS" != "Ubuntu" ]]; then
    error "Sistema não suportado: $OS. Requerido: Ubuntu"
fi

VERSION=$(lsb_release -rs)
if ! [[ "$VERSION" =~ ^(20.04|22.04|24.04)$ ]]; then
    error "Versão do Ubuntu $VERSION não suportada. Use 20.04, 22.04 ou 24.04"
fi
success "Sistema: Ubuntu $VERSION (compatível)"

# === 2. Arquitetura ===
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
    error "Arquitetura $ARCH não suportada. Requerida: x86_64"
fi
success "Arquitetura: $ARCH (compatível)"

# === 3. Recursos ===
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
DISK_GB=$(df / --output=size --block-size=G | tail -1 | tr -d 'G')
CPU_CORES=$(nproc)

log "Recursos detectados: RAM=${RAM_GB}GB, Disco=${DISK_GB}GB, CPU=${CPU_CORES} core(s)"

if [ "$RAM_GB" -lt 2 ]; then
    warn "RAM baixa ($RAM_GB GB). Recomendado: 2GB+"
fi

if [ "$DISK_GB" -lt 20 ]; then
    error "Espaço em disco insuficiente: $DISK_GB GB. Mínimo recomendado: 20GB"
fi

if [ "$CPU_CORES" -lt 1 ]; then
    error "CPU com menos de 1 core. Requerido: pelo menos 1 core"
fi

success "Recursos mínimos verificados"

# === 4. Conectividade ===
log "Testando conectividade com a internet..."
if ! curl -s --connect-timeout 10 http://github.com > /dev/null; then
    error "Sem conexão com a internet"
fi
success "Conectividade OK"

# === 5. Portas 80 e 443 livres ===
if command -v ss &> /dev/null; then
    PORTS=$(ss -tuln | grep -E ':(80|443)\s' | awk '{print $5}' | cut -d: -f2 | sort -u | tr '\n' ',' | sed 's/,$//')
elif command -v netstat &> /dev/null; then
    PORTS=$(netstat -tuln | grep -E ':(80|443)\s' | awk '{print $4}' | cut -d: -f2 | sort -u | tr '\n' ',' | sed 's/,$//')
else
    PORTS=""
fi

if [[ -n "$PORTS" ]]; then
    error "Portas críticas ocupadas: $PORTS. Feche nginx, apache ou outro serviço"
fi
success "Portas 80 e 443 estão livres"

# === Tudo OK ===
success "✅ Sistema verificado: pronto para instalação"

exit 0