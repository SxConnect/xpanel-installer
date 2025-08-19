#!/bin/bash
# install.sh - Instalador principal do xPanel (modo seguro)
# Executado ap√≥s o bootstrap clonar o reposit√≥rio
# github.com/SxConnect/xpanel-installer

set -euo pipefail

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Diret√≥rios
SCRIPT_DIR="/opt/xpanel-installer"
LOG_FILE="$SCRIPT_DIR/install.log"
TRAEFIK_DIR="/opt/traefik"
CONFIG_DIR="/opt/xpanel-config"
BACKUP_DIR="/opt/backups"

# Fun√ß√µes
log() { echo -e "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
error() { log "${RED}ERRO: $1${NC}" >&2; echo -e "${RED}‚ùå Instala√ß√£o falhou.${NC}"; exit 1; }
success() { log "${GREEN}SUCESSO: $1${NC}"; }
warn() { log "${YELLOW}AVISO: $1${NC}"; }

# === 0. Preparar ambiente ===
mkdir -p "$SCRIPT_DIR" "$BACKUP_DIR"
touch "$LOG_FILE"
log "Iniciando instalador do xPanel (modo seguro)"

# === 1. Root check ===
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo bash install.sh"
fi

# === 2. Verificar sistema (scripts locais) ===
log "Verificando requisitos do sistema..."
bash "$SCRIPT_DIR/utils/check-system.sh"

# === 3. Configurar firewall ===
log "Configurando firewall..."
bash "$SCRIPT_DIR/utils/setup-firewall.sh"

# === 4. Atualizar sistema ===
apt update && apt upgrade -y

# === 5. Docker ===
if ! command -v docker &> /dev/null; then
    log "Instalando Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker --now
    success "Docker instalado."
else
    warn "Docker j√° instalado"
fi

# === 6. Criar rede Traefik ===
docker network create traefik-network 2>/dev/null || true
success "Rede traefik-network criada."

# === 7. Instalar Traefik ===
log "Configurando Traefik como proxy reverso..."

mkdir -p "$TRAEFIK_DIR" "$TRAEFIK_DIR/config"

# Copiar configura√ß√£o local (seguro, sem curl)
cp "$SCRIPT_DIR/traefik/docker-compose.yml" "$TRAEFIK_DIR/docker-compose.yml"
cp "$SCRIPT_DIR/traefik/acme.json" "$TRAEFIK_DIR/acme.json" 2>/dev/null || echo '{}' > "$TRAEFIK_DIR/acme.json"
chmod 600 "$TRAEFIK_DIR/acme.json"
cp "$SCRIPT_DIR/traefik/config/dynamic.yml" "$TRAEFIK_DIR/config/dynamic.yml"

# Subir Traefik
cd "$TRAEFIK_DIR"
docker compose up -d || error "Falha ao iniciar Traefik"
success "Traefik est√° rodando com SSL autom√°tico!"

# === 8. Perguntar IP ou Dom√≠nio ===
read -p "Acessar via IP ou Dom√≠nio? [ip/dominio]: " ACCESS_TYPE
if [[ "$ACCESS_TYPE" == "dominio" ]]; then
    read -p "Dom√≠nio ou subdom√≠nio (ex: painel.seusite.com): " DOMAIN
else
    IP=$(curl -s ifconfig.me)
    DOMAIN="$IP"
fi

# === 9. Credenciais do xPanel ===
log "Configurando usu√°rio admin..."

while true; do
    read -p "Usu√°rio admin: " ADMIN_USER
    ADMIN_USER=$(echo "$ADMIN_USER" | xargs)
    [ -n "$ADMIN_USER" ] && break || warn "Usu√°rio n√£o pode ser vazio."
done

while true; do
    read -s -p "Senha admin: " ADMIN_PASS; echo
    [ ${#ADMIN_PASS} -ge 6 ] || { warn "Senha m√≠nima: 6 caracteres."; continue; }
    read -s -p "Confirme a senha: " ADMIN_PASS_CONFIRM; echo
    [ "$ADMIN_PASS" = "$ADMIN_PASS_CONFIRM" ] && break || warn "Senhas n√£o coincidem."
done

# === 10. Instalar xPanel ===
log "Instalando xPanel..."

rm -rf "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR"
cp -r "$SCRIPT_DIR/xpanel-config/." "$CONFIG_DIR/"

# Criar .env
cat > "$CONFIG_DIR/.env" << EOF
ADMIN_USER=$ADMIN_USER
ADMIN_PASS=$ADMIN_PASS
DOMAIN=$DOMAIN
EOF
chmod 600 "$CONFIG_DIR/.env"
success ".env criado e protegido"

# Subir xPanel
cd "$CONFIG_DIR"
docker compose up -d || error "Falha ao iniciar xPanel"
success "xPanel est√° rodando atr√°s do Traefik!"

# === 11. Configurar backup autom√°tico ===
echo -e "\n${GREEN}Ì†ΩÌ≥¶ Deseja configurar backup autom√°tico?${NC}"
echo "1) Desativado"
echo "2) Di√°rio (√†s 2h da manh√£)"
echo "3) Semanal (domingo, 2h)"
echo "4) A cada X horas (personalizado)"

read -p "Escolha (1-4): " BACKUP_FREQ
CRON_TIME=""

case $BACKUP_FREQ in
    1) warn "Backup autom√°tico desativado."; ;;
    2) CRON_TIME="0 2 * * *"; ;;
    3) CRON_TIME="0 2 * * 0"; ;;
    4)
        read -p "A cada quantas horas? (ex: 6, 12): " HOURS
        if [[ "$HOURS" =~ ^[0-9]+$ ]] && [ "$HOURS" -ge 1 ]; then
            CRON_TIME="0 */$HOURS * * *"
        else
            warn "Horas inv√°lidas. Backup n√£o configurado."
        fi
        ;;
    *) warn "Op√ß√£o inv√°lida. Backup n√£o configurado."; ;;
esac

# Aplicar cron
if [ -n "$CRON_TIME" ]; then
    BACKUP_SCRIPT="/opt/xpanel-installer/utils/backup.sh"
    (crontab -l 2>/dev/null; echo "$CRON_TIME $BACKUP_SCRIPT") | crontab -
    success "Backup autom√°tico configurado: $CRON_TIME"
fi

# === 12. Comandos √∫teis ===
cat >> /root/.bashrc << 'EOF'

# Comandos xPanel (gerados pelo instalador)
xpanel-logs() { docker logs -f xpanel-container; }
xpanel-restart() { cd /opt/xpanel-config && docker compose restart; }
xpanel-update() { cd /opt/xpanel-config && git pull && docker compose up -d; }
xpanel-backup() { sudo /opt/xpanel-installer/utils/backup.sh; }
xpanel-restore() { sudo /opt/xpanel-installer/utils/restore.sh; }
xpanel-status() { /opt/xpanel-installer/utils/status.sh; }
xpanel-uninstall() { 
    read -p "Desinstalar tudo? (s/n): " -n1 -r; echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        cd /opt/xpanel-config && docker compose down
        rm -rf /opt/xpanel-config /opt/traefik /opt/xpanel-installer /opt/backups 2>/dev/null || true
        sed -i '/xpanel-/d' /root/.bashrc 2>/dev/null || true
        echo "‚úÖ xPanel removido."
    fi
}
EOF

# === 13. Relat√≥rio Final ===
echo -e "
${GREEN}========================================${NC}
       ‚úÖ INSTALA√á√ÉO CONCLU√çDA!
${GREEN}========================================${NC}
O xPanel foi instalado com seguran√ßa via reposit√≥rio clonado.

Ì†ΩÌ¥ç Acesso:
  Ì†ΩÌ¥ó https://$DOMAIN
  Ì†ΩÌ±§ $ADMIN_USER
  Ì†ΩÌ¥ê Senha definida por voc√™

Ì†ΩÌª†Ô∏è Comandos: xpanel-logs, xpanel-update, xpanel-backup

Ì†ΩÌ≥¶ Backup autom√°tico: $( [ -n "$CRON_TIME" ] && echo "SIM ($CRON_TIME)" || echo "N√ÉO" )

Ì†ΩÌ≥Ñ Log: $LOG_FILE
Ì†ΩÌ∫Ä Sistema pronto!
"