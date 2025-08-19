#!/bin/bash
# xPanel Uninstaller
# github.com/seuusuario/xpanel-installer
# Remove todos os componentes: xPanel, Traefik, redes, arquivos e comandos

set -euo pipefail

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Funções
log() {
    echo -e "[$(date +'%H:%M:%S')] $1"
}

warn() {
    log "${YELLOW}AVISO: $1${NC}"
}

error() {
    log "${RED}ERRO: $1${NC}" >&2
    exit 1
}

success() {
    log "${GREEN}SUCESSO: $1${NC}"
}

# === Confirmação inicial ===
echo -e "${RED}"
echo "⚠️  ATENÇÃO: Este script irá remover:"
echo "   - Container xPanel"
echo "   - Container Traefik"
echo "   - Rede Docker 'traefik-network'"
echo "   - Volumes e dados do xPanel"
echo "   - Arquivos em /opt/xpanel-config e /opt/traefik"
echo "   - Comandos personalizados do .bashrc"
echo -e "${NC}"

read -p "Deseja continuar? (digite 'sim' para confirmar): " CONFIRM
if [[ "$CONFIRM" != "sim" ]]; then
    error "Desinstalação cancelada pelo usuário."
fi

# === Parar e remover containers ===
log "Parando e removendo containers..."

# Remover xPanel
if docker ps -q --filter "name=xpanel-container" | grep -q .; then
    log "Parando container xpanel-container..."
    docker stop xpanel-container >/dev/null 2>&1 || true
    docker rm xpanel-container >/dev/null 2>&1
    success "Container xpanel-container removido."
else
    warn "Container xpanel-container não encontrado."
fi

# Remover Traefik
if docker ps -q --filter "name=traefik-proxy" | grep -q .; then
    log "Parando container traefik-proxy..."
    docker stop traefik-proxy >/dev/null 2>&1 || true
    docker rm traefik-proxy >/dev/null 2>&1
    success "Container traefik-proxy removido."
else
    warn "Container traefik-proxy não encontrado."
fi

# === Remover rede Docker ===
if docker network ls --filter "name=traefik-network" -q | grep -q .; then
    log "Removendo rede traefik-network..."
    docker network rm traefik-network >/dev/null 2>&1
    success "Rede traefik-network removida."
else
    warn "Rede traefik-network não encontrada."
fi

# === Perguntar se deseja remover volumes ===
read -p "Remover volumes e dados do xPanel? (isso apagará usuários, configurações, etc) (s/n): " -n1 -r; echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    log "Removendo volumes locais..."
    docker volume prune -f
    success "Volumes locais removidos."
else
    warn "Volumes locais mantidos."
fi

# === Remover pastas ===
log "Removendo arquivos do sistema..."

# Remover xpanel-config
if [ -d "/opt/xpanel-config" ]; then
    rm -rf /opt/xpanel-config
    success "Pasta /opt/xpanel-config removida."
else
    warn "Pasta /opt/xpanel-config não encontrada."
fi

# Remover traefik
if [ -d "/opt/traefik" ]; then
    rm -rf /opt/traefik
    success "Pasta /opt/traefik removida."
else
    warn "Pasta /opt/traefik não encontrada."
fi

# Remover logs do instalador
if [ -d "/opt/xpanel-installer" ]; then
    rm -rf /opt/xpanel-installer
    success "Pasta /opt/xpanel-installer removida."
else
    warn "Pasta /opt/xpanel-installer não encontrada."
fi

# === Limpar comandos do .bashrc ===
if grep -q "xpanel-" /root/.bashrc; then
    sed -i '/xpanel-/d' /root/.bashrc
    success "Comandos personalizados removidos do .bashrc"
else
    warn "Nenhum comando xpanel- encontrado no .bashrc"
fi

# === Reiniciar shell (opcional) ===
warn "Reinicie o terminal para aplicar as mudanças."

# === Relatório Final ===
echo -e "
${GREEN}========================================${NC}
       ✅ DESINSTALAÇÃO CONCLUÍDA
${GREEN}========================================${NC}
Todos os componentes do xPanel e Traefik foram removidos.
O sistema está limpo.

Próximos passos:
- Reinicie o terminal
- A VPS está pronta para uma nova instalação

Se precisar reinstalar:
  bash <(curl -sSL https://raw.githubusercontent.com/seuusuario/xpanel-installer/main/utils/install.sh)
"
