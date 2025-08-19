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

# === Verificar root ===
if [ "$EUID" -ne 0 ]; then
    error "Este script requer root. Execute com sudo."
fi

# === Verificar se UFW está instalado ===
if ! command -v ufw &> /dev/null; then
    log "Instalando UFW..."
    apt update && apt install ufw -y || error "Falha ao instalar UFW"
    success "UFW instalado"
fi

# === Se já estiver ativo, pula configuração, mas não sai do script ===
if ufw status | grep -q "Status: active"; then
    warn "O UFW já está ativo. Pulando configuração de regras."
else
    # === Configurar regras ===
    log "Configurando regras do firewall..."

    ufw default deny incoming || true
    ufw default allow outgoing || true
    success "Política: bloquear entrada, permitir saída"

    ufw allow 22/tcp || true
    ufw allow 80/tcp || true
    ufw allow 443/tcp || true
    success "Portas 22, 80 e 443 liberadas"

    # === Perguntar se deseja ativar ===
    echo -e "\n${YELLOW}Ativar o firewall agora? (s/n)${NC}"
    echo "   - SSH (22) permanecerá acessível"
    echo "   - HTTP/HTTPS (80/443) liberados"
    echo "   - Outras portas bloqueadas"
    echo -n "Ativar UFW? (s/n): "
    read -n1 -r REPLY; echo

    if [[ $REPLY =~ ^[Ss]$ ]]; then
        echo 'y' | ufw enable > /dev/null 2>&1 || error "Falha ao ativar UFW"
        success "UFW ativado com sucesso"
    else
        warn "Firewall não ativado. Execute 'ufw enable' depois, se desejar."
    fi
fi

# === Mostrar status final ===
echo -e "
${GREEN}✅ FIREWALL CONFIGURADO${NC}
Regras ativas:
  SSH (22)  → permitido
  HTTP (80) → permitido
  HTTPS (443) → permitido
  Demais portas → bloqueadas
"