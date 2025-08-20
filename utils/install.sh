#!/bin/bash
# install.sh - Instalador principal do xPanel (modo seguro)
# Executado após o bootstrap clonar o repositório
# github.com/SxConnect/xpanel-installer

set -euo pipefail

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Diretórios
SCRIPT_DIR="/opt/xpanel-installer"
LOG_FILE="$SCRIPT_DIR/install.log"
TRAEFIK_DIR="/opt/traefik"
CONFIG_DIR="/opt/xpanel-config"
BACKUP_DIR="/opt/backups"

# Funções
log() { echo -e "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
error() { log "${RED}ERRO: $1${NC}" >&2; echo -e "${RED}❌ Instalação falhou.${NC}"; exit 1; }
success() { log "${GREEN}SUCESSO: $1${NC}"; }
warn() { log "${YELLOW}AVISO: $1${NC}"; }

# === 0. Preparar ambiente ===
mkdir -p "$BACKUP_DIR"
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
    warn "Docker já instalado"
fi

# Verificar se Docker Compose está disponível
if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
    log "Instalando Docker Compose Plugin..."
    apt install -y docker-compose-plugin
    success "Docker Compose Plugin instalado."
fi

# === 6. Criar rede Traefik ===
docker network create traefik-network 2>/dev/null || true
success "Rede traefik-network criada."

# === 7. Instalar Traefik ===
log "Configurando Traefik como proxy reverso..."

mkdir -p "$TRAEFIK_DIR" "$TRAEFIK_DIR/config"

# Copiar configuração real do repositório
if [ ! -f "$SCRIPT_DIR/traefik/docker-compose.yml" ]; then
    error "docker-compose.yml do Traefik não encontrado no repositório"
fi

cp "$SCRIPT_DIR/traefik/docker-compose.yml" "$TRAEFIK_DIR/docker-compose.yml"
cp "$SCRIPT_DIR/traefik/acme.json" "$TRAEFIK_DIR/acme.json" 2>/dev/null || echo '{}' > "$TRAEFIK_DIR/acme.json"
chmod 600 "$TRAEFIK_DIR/acme.json"
cp "$SCRIPT_DIR/traefik/config/dynamic.yml" "$TRAEFIK_DIR/config/dynamic.yml" 2>/dev/null || {
    warn "dynamic.yml não encontrado, criando vazio"
    touch "$TRAEFIK_DIR/config/dynamic.yml"
}

# Subir Traefik
cd "$TRAEFIK_DIR"
docker compose up -d || error "Falha ao iniciar Traefik"
success "Traefik está rodando com SSL automático!"

# === 8. Perguntar IP ou Domínio ===
echo -e "\n${YELLOW}Como você quer acessar o painel?${NC}"
read -p "Acessar via [I]P ou [D]omínio? (i/d): " ACCESS_TYPE
ACCESS_TYPE=${ACCESS_TYPE,,}

if [[ "$ACCESS_TYPE" == "d" ]]; then
    while true; do
        read -p "Digite seu domínio ou subdomínio (ex: painel.seusite.com): " DOMAIN
        DOMAIN=$(echo "$DOMAIN" | xargs | tr '[:upper:]' '[:lower:]')
        if [[ "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            warn "Formato de domínio inválido. Tente novamente."
        fi
    done
else
    log "Detectando IP público..."
    IP=$(curl -s --max-time 10 ifconfig.me 2>/dev/null || curl -s --max-time 10 ipinfo.io/ip 2>/dev/null || echo "127.0.0.1")
    DOMAIN="$IP"
    log "IP detectado: $IP"
fi

# === 9. Credenciais do xPanel ===
log "Configurando usuário admin..."

while true; do
    read -p "Usuário admin: " ADMIN_USER
    ADMIN_USER=$(echo "$ADMIN_USER" | xargs)
    if [ -n "$ADMIN_USER" ] && [[ "$ADMIN_USER" =~ ^[a-zA-Z0-9_]+$ ]]; then
        break
    else
        warn "Usuário deve conter apenas letras, números e underscore."
    fi
done

while true; do
    echo -n "Senha admin (mín. 6 caracteres): "
    read -s ADMIN_PASS
    echo
    if [ ${#ADMIN_PASS} -ge 6 ]; then
        echo -n "Confirme a senha: "
        read -s ADMIN_PASS_CONFIRM
        echo
        if [ "$ADMIN_PASS" = "$ADMIN_PASS_CONFIRM" ]; then
            break
        else
            warn "Senhas não coincidem. Tente novamente."
        fi
    else
        warn "Senha muito curta. Mínimo 6 caracteres."
    fi
done

# === 10. Instalar xPanel ===
log "Instalando xPanel..."

# Verificar se o diretório xpanel-config existe no repositório
if [ ! -d "$SCRIPT_DIR/xpanel-config" ]; then
    error "Diretório xpanel-config não encontrado no repositório"
fi

# Remover instalação anterior
rm -rf "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR"

# Copiar a configuração real do painel
cp -r "$SCRIPT_DIR/xpanel-config/." "$CONFIG_DIR/"

# Criar .env com as variáveis
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
success "xPanel está rodando atrás do Traefik!"

# === 11. Configurar backup automático ===
echo -e "\n${GREEN}📦 Deseja configurar backup automático?${NC}"
echo "1) Desativado"
echo "2) Diário (às 2h da manhã)"
echo "3) Semanal (domingo, 2h)"
echo "4) A cada X horas (personalizado)"

read -p "Escolha (1-4): " BACKUP_FREQ
CRON_TIME=""

case $BACKUP_FREQ in
    1) warn "Backup automático desativado."; ;;
    2) CRON_TIME="0 2 * * *"; ;;
    3) CRON_TIME="0 2 * * 0"; ;;
    4)
        read -p "A cada quantas horas? (ex: 6, 12): " HOURS
        if [[ "$HOURS" =~ ^[0-9]+$ ]] && [ "$HOURS" -ge 1 ] && [ "$HOURS" -le 24 ]; then
            CRON_TIME="0 */$HOURS * * *"
        else
            warn "Horas inválidas (1-24). Backup não configurado."
        fi
        ;;
    *) warn "Opção inválida. Backup não configurado."; ;;
esac

# Aplicar cron
if [ -n "$CRON_TIME" ]; then
    BACKUP_SCRIPT="/opt/xpanel-installer/utils/backup.sh"
    if [ -f "$BACKUP_SCRIPT" ]; then
        (crontab -l 2>/dev/null; echo "$CRON_TIME $BACKUP_SCRIPT") | crontab -
        success "Backup automático configurado: $CRON_TIME"
    else
        warn "Script de backup não encontrado, cron não configurado"
    fi
fi

# === 12. Comandos úteis ===
cat >> /root/.bashrc << 'EOF'

# Comandos xPanel (gerados pelo instalador)
xpanel-logs() { docker logs -f xpanel-container; }
xpanel-restart() { cd /opt/xpanel-config && docker compose restart; }
xpanel-update() { cd /opt/xpanel-config && git pull && docker compose up -d; }
xpanel-backup() { sudo /opt/xpanel-installer/utils/backup.sh; }
xpanel-restore() { sudo /opt/xpanel-installer/utils/restore.sh; }
xpanel-status() { /opt/xpanel-installer/utils/status.sh; }
xpanel-uninstall() { 
    echo "⚠️  CUIDADO: Isso irá remover TUDO do xPanel!"
    read -p "Desinstalar completamente? Digite 'CONFIRMAR': " -r
    if [[ $REPLY == "CONFIRMAR" ]]; then
        cd /opt/xpanel-config && docker compose down 2>/dev/null || true
        cd /opt/traefik && docker compose down 2>/dev/null || true
        rm -rf /opt/xpanel-config /opt/traefik /opt/xpanel-installer /opt/backups 2>/dev/null || true
        sed -i '/# Comandos xPanel/,/^$/d' /root/.bashrc 2>/dev/null || true
        echo "✅ xPanel completamente removido!"
    else
        echo "❌ Cancelado."
    fi
}
EOF

# === 13. Relatório Final ===
echo -e "
${GREEN}========================================${NC}
       ✅ INSTALAÇÃO CONCLUÍDA!
${GREEN}========================================${NC}
🔍 Informações de Acesso:
  🔗 URL: https://$DOMAIN
  👤 Usuário: $ADMIN_USER
  🔐 Senha: [definida por você]

🛠️ Comandos Úteis:
  xpanel-logs      - Ver logs do container
  xpanel-restart   - Reiniciar serviços  
  xpanel-status    - Ver status
  xpanel-uninstall - Remover tudo

📦 Backup automático: $( [ -n "$CRON_TIME" ] && echo "✅ SIM ($CRON_TIME)" || echo "❌ NÃO" )
📄 Log completo: $LOG_FILE

🎯 Acesse: https://$DOMAIN
${GREEN}🚀 Sistema pronto para uso!${NC}
"

# Recarregar .bashrc para disponibilizar comandos
source /root/.bashrc 2>/dev/null || true
log "Instalação finalizada com sucesso!"