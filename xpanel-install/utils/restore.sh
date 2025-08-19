#!/bin/bash
# restore.sh
# Restaura o xPanel a partir de um backup
# github.com/SxConnect/xpanel-installer

set -euo pipefail

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Diretórios
BACKUP_DIR="/opt/backups"
XPANEL_DATA="/opt/xpanel-config/data"
TRAEFIK_ACME="/opt/traefik/acme.json"
LOG_FILE="/opt/xpanel-installer/restore.log"

# Funções
log() { echo -e "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
error() { log "${RED}ERRO: $1${NC}" >&2; exit 1; }
success() { log "${GREEN}OK: $1${NC}"; }
warn() { log "${YELLOW}AVISO: $1${NC}"; }

# === Verificar root ===
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo bash restore.sh"
fi

# === Verificar se há backups ===
if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR"/*.tar.gz 2>/dev/null)" ]; then
    error "Nenhum backup encontrado em $BACKUP_DIR"
fi

# === Listar backups ===
echo -e "
${BLUE}📦 Backups disponíveis:${NC}
"
for file in "$BACKUP_DIR"/*.tar.gz; do
    if [[ -f "$file" ]]; then
        SIZE=$(du -h "$file" | cut -f1)
        DATE=$(stat -c '%y' "$file" | cut -d' ' -f1)
        echo "  📅 $DATE | 📦 $(basename "$file") | 📏 $SIZE"
    fi
done

echo
read -p "Digite o nome do backup para restaurar: " BACKUP_NAME
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

if [ ! -f "$BACKUP_PATH" ]; then
    error "Backup '$BACKUP_NAME' não encontrado"
fi

# === Confirmação crítica ===
echo -e "\n${RED}⚠️  ATENÇÃO: Isso substituirá:${NC}"
echo "   - Dados do xPanel: $XPANEL_DATA"
echo "   - Certificado SSL: $TRAEFIK_ACME"
read -p "Deseja continuar? (digite 'restaurar' para confirmar): " CONFIRM
if [[ "$CONFIRM" != "restaurar" ]]; then
    error "Restauração cancelada."
fi

# === Parar containers ===
log "Parando containers..."
docker stop xpanel-container traefik-proxy 2>/dev/null || true

# === Fazer backup atual (antes de restaurar) ===
TIMESTAMP=$(date +'%Y%m%d-%H%M%S')
PRE_RESTORE="/opt/backups/backup-before-restore-$TIMESTAMP"
mkdir -p "$PRE_RESTORE"

if [ -d "$XPANEL_DATA" ]; then
    cp -r "$XPANEL_DATA" "$PRE_RESTORE/data" 2>/dev/null && success "Backup atual do xPanel salvo"
fi

if [ -f "$TRAEFIK_ACME" ]; then
    cp "$TRAEFIK_ACME" "$PRE_RESTORE/acme.json" 2>/dev/null && success "Backup atual do acme.json salvo"
fi

# === Extrair backup ===
log "Restaurando $BACKUP_NAME..."
TEMP_DIR="/tmp/xpanel-restore"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

tar -xzf "$BACKUP_PATH" -C "$TEMP_DIR" || error "Falha ao extrair backup"

# Restaurar dados do xPanel
if [ -d "$TEMP_DIR/data" ]; then
    rm -rf "$XPANEL_DATA"
    mv "$TEMP_DIR/data" "$XPANEL_DATA"
    success "Dados do xPanel restaurados"
else
    warn "Nenhum dado do xPanel no backup"
fi

# Restaurar acme.json
if [ -f "$TEMP_DIR/acme.json" ]; then
    mkdir -p "$(dirname "$TRAEFIK_ACME")"
    mv "$TEMP_DIR/acme.json" "$TRAEFIK_ACME"
    chmod 600 "$TRAEFIK_ACME"
    success "Certificado SSL restaurado"
fi

# Limpar
rm -rf "$TEMP_DIR"

# === Reiniciar serviços ===
log "Reiniciando containers..."
cd /opt/traefik && docker compose up -d
cd /opt/xpanel-config && docker compose up -d

# === Sucesso ===
echo -e "
${GREEN}✅ RESTAURAÇÃO CONCLUÍDA!${NC}
O sistema foi restaurado do backup: $BACKUP_NAME

💡 Próximos passos:
- Acesse: https://seupainel.com.br
- O backup anterior foi salvo em: $PRE_RESTORE
"