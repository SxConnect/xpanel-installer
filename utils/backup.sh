#!/bin/bash
# backup.sh
# Cria backup dos dados do xPanel e Traefik
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
BACKUP_NAME="xpanel-backup-$(date +'%Y%m%d-%H%M%S').tar.gz"

# === Relatório inicial ===
echo -e "
📅 Iniciando backup em $(date)
📁 Destino: $BACKUP_DIR/$BACKUP_NAME
"

# === Verificar se os diretórios existem ===
if [ ! -d "$XPANEL_DATA" ]; then
    warn "Pasta de dados do xPanel não encontrada: $XPANEL_DATA"
    warn "Certifique-se de que o xPanel foi instalado."
    exit 1
fi

if [ ! -f "$TRAEFIK_ACME" ]; then
    warn "acme.json não encontrado: $TRAEFIK_ACME (SSL não será incluído)"
fi

# === Criar backup ===
log "Compactando dados do xPanel e acme.json..."
tar -czf "$BACKUP_DIR/$BACKUP_NAME" \
    -C /opt/xpanel-config data \
    -C /opt traefik/acme.json 2>/dev/null || \
    tar -czf "$BACKUP_DIR/$BACKUP_NAME" \
        -C /opt/xpanel-config data 2>/dev/null

success "Backup criado: $BACKUP_DIR/$BACKUP_NAME"

# === Mostrar tamanho e próximo passo ===
SIZE=$(du -h "$BACKUP_DIR/$BACKUP_NAME" | cut -f1)
echo -e "
✅ Backup concluído!
📦 Arquivo: $BACKUP_NAME
📏 Tamanho: $SIZE
📍 Caminho: $BACKUP_DIR/

💡 Dica: Copie para outro local:
   scp $BACKUP_DIR/$BACKUP_NAME usuario@outro-servidor:/caminho/
"