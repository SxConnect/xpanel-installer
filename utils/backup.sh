#!/bin/bash
# backup.sh
# Faz backup dos dados do xPanel e do certificado SSL
# github.com/SxConnect/xpanel-installer

set -euo pipefail

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Diretórios
BACKUP_DIR="/opt/backups"
XPANEL_DATA="/opt/xpanel-config/data"
TRAEFIK_ACME="/opt/traefik/acme.json"
LOG_FILE="/opt/xpanel-installer/backup.log"

# Funções
log() { echo -e "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
error() { log "${RED}ERRO: $1${NC}" >&2; exit 1; }
success() { log "${GREEN}OK: $1${NC}"; }
warn() { log "${YELLOW}AVISO: $1${NC}"; }

# === Verificar root ===
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo bash backup.sh"
fi

# === Criar diretório de backup ===
mkdir -p "$BACKUP_DIR"

# === Nome do backup ===
BACKUP_NAME="xpanel-backup-$(date +'%Y%m%d-%H%M%S').tar.gz"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

# === Verificar se há dados para salvar ===
if [ ! -d "$XPANEL_DATA" ] && [ ! -f "$TRAEFIK_ACME" ]; then
    error "Nenhum dado encontrado para backup em $XPANEL_DATA ou $TRAEFIK_ACME"
fi

# === Criar backup ===
log "Iniciando backup..."
tar -czf "$BACKUP_PATH" \
    -C /opt/xpanel-config data 2>/dev/null || true

if [ -f "$TRAEFIK_ACME" ] && [ -s "$TRAEFIK_ACME" ]; then
    tar -rzf "$BACKUP_PATH" \
        -C /opt traefik/acme.json 2>/dev/null || true
fi

# === Verificar se o backup foi criado ===
if [ -f "$BACKUP_PATH" ]; then
    SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
    success "Backup criado com sucesso: $BACKUP_PATH ($SIZE)"
    echo -e "
📦 Backup concluído!
   Arquivo: $BACKUP_NAME
   Tamanho: $SIZE
   Local: $BACKUP_DIR

💡 Dica: Copie para outro local com:
   scp $BACKUP_PATH usuario@servidor:/caminho/
"
else
    error "Falha ao criar o arquivo de backup"
fi