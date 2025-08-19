#!/bin/bash
# uninstall.sh
# Desinstala o xPanel, Traefik e todos os componentes
# github.com/SxConnect/xpanel-installer

set -euo pipefail

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Funções
log() { echo -e "[$(date +'%H:%M:%S')] $1"; }
warn() { log "${YELLOW}AVISO: $1${NC}"; }
error() { log "${RED}ERRO: $1${NC}" >&2; exit 1; }
success() { log "${GREEN}SUCESSO: $1${NC}"; }

# === Confirmação inicial ===
echo -e "${RED}"
echo "⚠️  ATENÇÃO: Este script irá remover:"
echo "   - Container xPanel"
echo "   - Container Traefik"
echo "   - Rede Docker 'traefik-network'"
echo "   - Dados em /opt/xpanel-config/data"
echo "   - Certificados SSL em /opt/traefik/acme.json"
echo "   - Backups em /opt/backups"
echo "   - Scripts em /opt/xpanel-installer"
echo "   - Comandos do .bashrc"
echo -e "${NC}"

read -p "Deseja continuar? (digite 'sim' para confirmar): " CONFIRM
if [[ "$CONFIRM" != "sim" ]]; then
    error "Desinstalação cancelada pelo usuário."
fi

# === Parar e remover containers ===
log "Parando e removendo containers..."

if docker ps -q --filter "name=xpanel-container" | grep -q .; then
    docker stop xpanel-container >/dev/null 2>&1 || true
    docker rm xpanel-container >/dev/null 2>&1
    success "Container xpanel-container removido."
else
    warn "Container xpanel-container não encontrado."
fi

if docker ps -q --filter "name=traefik-proxy" | grep -q .; then
    docker stop traefik-proxy >/dev/null 2>&1 || true
    docker rm traefik-proxy >/dev/null 2>&1
    success "Container traefik-proxy removido."
else
    warn "Container traefik-proxy não encontrado."
fi

# === Remover rede ===
if docker network ls --filter "name=traefik-network" -q | grep -q .; then
    docker network rm traefik-network >/dev/null 2>&1
    success "Rede traefik-network removida."
else
    warn "Rede traefik-network não encontrada."
fi

# === Remover pastas ===
log "Removendo pastas do sistema..."

for dir in "/opt/xpanel-config" "/opt/traefik" "/opt/xpanel-installer" "/opt/backups"; do
    if [ -d "$dir" ]; then
        rm -rf "$dir"
        success "Pasta $dir removida."
    else
        warn "Pasta $dir não encontrada."
    fi
done

# === Limpar .bashrc ===
if grep -q "xpanel-" /root/.bashrc; then
    sed -i '/xpanel-/d' /root/.bashrc
    success "Comandos do xPanel removidos do .bashrc"
else
    warn "Nenhum comando do xPanel encontrado no .bashrc"
fi

# === Relatório final ===
echo -e "
${GREEN}========================================${NC}
       ✅ DESINSTALAÇÃO CONCLUÍDA
${GREEN}========================================${NC}
Todos os componentes do xPanel foram removidos.

O sistema está limpo e pronto para uma nova instalação.

Se precisar reinstalar:
  bash <(curl -sSL https://xpanel.sh)
"