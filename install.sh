#!/bin/bash
# xPanel Installer Único (modo seguro) - VERSÃO CORRIGIDA
# Instala tudo em um script só — sem dependência de git ou bootstrap
# github.com/SxConnect/xpanel-installer

set -euo pipefail

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Diretórios
LOG_FILE="/opt/xpanel-install.log"
TRAEFIK_DIR="/opt/traefik"
CONFIG_DIR="/opt/xpanel-config"
BACKUP_DIR="/opt/backups"

# Funções
log() { echo -e "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
error() { log "${RED}ERRO: $1${NC}" >&2; exit 1; }
success() { log "${GREEN}SUCESSO: $1${NC}"; }
warn() { log "${YELLOW}AVISO: $1${NC}"; }

# === 0. Preparar ambiente ===
mkdir -p /opt "$BACKUP_DIR"
touch "$LOG_FILE"
log "Iniciando instalador do xPanel (modo seguro)"

# === 1. Root check ===
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo bash install.sh"
fi

# === 2. Atualizar sistema e instalar dependências básicas ===
log "Atualizando sistema e instalando dependências..."
apt update && apt upgrade -y || error "Falha ao atualizar o sistema"
apt install -y curl wget git ca-certificates gnupg lsb-release || error "Falha ao instalar dependências"

# === 3. Verificar se Docker está instalado ===
if ! command -v docker &> /dev/null; then
    log "Instalando Docker..."
    curl -fsSL https://get.docker.com | sh || error "Falha ao instalar Docker"
    systemctl enable docker --now || error "Falha ao iniciar Docker"
    success "Docker instalado."
else
    warn "Docker já instalado"
fi

# === 4. Verificar Docker Compose Plugin ===
if ! command -v docker compose &> /dev/null; then
    log "Instalando Docker Compose Plugin..."
    apt install -y docker-compose-plugin || error "Falha ao instalar Docker Compose"
    success "Docker Compose Plugin instalado."
fi

# === 5. Perguntar IP ou Domínio PRIMEIRO (necessário para Traefik) ===
echo -e "\n${YELLOW}Como você quer acessar o painel?${NC}"
read -p "Acessar via [I]P ou [D]omínio? (i/d): " ACCESS_TYPE
ACCESS_TYPE=${ACCESS_TYPE,,}

if [[ "$ACCESS_TYPE" == "d" ]]; then
    while true; do
        read -p "Digite seu domínio ou subdomínio (ex: painel.seusite.com): " DOMAIN
        DOMAIN=$(echo "$DOMAIN" | xargs | tr '[:upper:]' '[:lower:]')
        if [[ "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            warn "Formato de domínio inválido. Tente novamente."
        fi
    done
    USE_SSL=true
else
    log "Detectando IP público..."
    IP=$(curl -s --max-time 10 ifconfig.me 2>/dev/null || curl -s --max-time 10 ipinfo.io/ip 2>/dev/null || echo "127.0.0.1")
    DOMAIN="$IP"
    USE_SSL=false
    log "IP detectado: $IP"
fi

# === 6. Criar rede Traefik ===
docker network create traefik-network 2>/dev/null || true
success "Rede traefik-network criada."

# === 7. Instalar Traefik ===
log "Configurando Traefik como proxy reverso..."

mkdir -p "$TRAEFIK_DIR" "$TRAEFIK_DIR/config"

# === docker-compose.yml do Traefik (CORRIGIDO) ===
if [ "$USE_SSL" = true ]; then
    # Versão com SSL para domínios
    cat > "$TRAEFIK_DIR/docker-compose.yml" << EOF
version: '3.8'
services:
  traefik:
    image: traefik:v3.0
    container_name: traefik-proxy
    restart: unless-stopped
    command:
      - "--api.dashboard=true"
      - "--api.insecure=false"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=traefik-network"
      - "--providers.file.directory=/etc/traefik/config"
      - "--providers.file.watch=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.email=admin@${DOMAIN}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/etc/traefik/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--log.level=INFO"
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"  # Dashboard do Traefik
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./acme.json:/etc/traefik/acme.json
      - ./config:/etc/traefik/config:ro
    networks:
      - traefik-network
    labels:
      - "traefik.enable=true"
      # Dashboard do Traefik
      - "traefik.http.routers.traefik.rule=Host(\`traefik.${DOMAIN}\`)"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls.certresolver=letsencrypt"
      - "traefik.http.routers.traefik.service=api@internal"
      # Redirecionamento HTTP -> HTTPS
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
      - "traefik.http.routers.redirs.rule=hostregexp(\`{host:.+}\`)"
      - "traefik.http.routers.redirs.entrypoints=web"
      - "traefik.http.routers.redirs.middlewares=redirect-to-https"

networks:
  traefik-network:
    external: true
EOF
else
    # Versão sem SSL para IPs
    cat > "$TRAEFIK_DIR/docker-compose.yml" << EOF
version: '3.8'
services:
  traefik:
    image: traefik:v3.0
    container_name: traefik-proxy
    restart: unless-stopped
    command:
      - "--api.dashboard=true"
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=traefik-network"
      - "--providers.file.directory=/etc/traefik/config"
      - "--providers.file.watch=true"
      - "--entrypoints.web.address=:80"
      - "--log.level=INFO"
    ports:
      - "80:80"
      - "8080:8080"  # Dashboard do Traefik
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./config:/etc/traefik/config:ro
    networks:
      - traefik-network

networks:
  traefik-network:
    external: true
EOF
fi

# === acme.json (para certificados SSL) ===
if [ "$USE_SSL" = true ]; then
    touch "$TRAEFIK_DIR/acme.json"
    chmod 600 "$TRAEFIK_DIR/acme.json"
fi

# === dynamic.yml (configurações extras - CORRIGIDO) ===
cat > "$TRAEFIK_DIR/config/dynamic.yml" << 'EOF'
http:
  middlewares:
    secure-headers:
      headers:
        frameDeny: true
        sslRedirect: true
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000
        customRequestHeaders:
          X-Forwarded-Proto: "https"
    default-headers:
      headers:
        frameDeny: true
        browserXssFilter: true
        contentTypeNosniff: true
        customRequestHeaders:
          X-Forwarded-Proto: "http"

  routers:
    api:
      rule: "Host(`traefik.localhost`)"
      service: "api@internal"
      middlewares:
        - "default-headers"

  services:
    # Serviços definidos automaticamente pelo Docker
EOF

# Subir Traefik
cd "$TRAEFIK_DIR"
docker compose up -d || error "Falha ao iniciar Traefik"
success "Traefik está rodando!"
if [ "$USE_SSL" = true ]; then
    success "SSL automático configurado!"
    log "Dashboard do Traefik: https://traefik.$DOMAIN"
else
    log "Dashboard do Traefik: http://$DOMAIN:8080"
fi

# === 8. Credenciais do xPanel ===
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

# === 9. Instalar xPanel ===
log "Instalando xPanel..."

rm -rf "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR/data"

# === docker-compose.yml do xPanel (CORRIGIDO) ===
if [ "$USE_SSL" = true ]; then
    # Versão com SSL
    cat > "$CONFIG_DIR/docker-compose.yml" << EOF
version: '3.8'
services:
  xpanel:
    # SUBSTITUA pela imagem correta do seu painel
    image: sxconect/xpanel:latest
    container_name: xpanel-container
    restart: unless-stopped
    environment:
      - ADMIN_USER=\${ADMIN_USER}
      - ADMIN_PASS=\${ADMIN_PASS}
      - DOMAIN=\${DOMAIN}
      - SSL_ENABLED=true
    volumes:
      - ./data:/app/data
      - /var/log/xpanel:/app/logs
    networks:
      - traefik-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.xpanel.rule=Host(\`\${DOMAIN}\`)"
      - "traefik.http.routers.xpanel.entrypoints=websecure"
      - "traefik.http.routers.xpanel.tls.certresolver=letsencrypt"
      - "traefik.http.services.xpanel.loadbalancer.server.port=3000"
      - "traefik.http.routers.xpanel.middlewares=secure-headers@file"

networks:
  traefik-network:
    external: true
EOF
else
    # Versão sem SSL (para IP)
    cat > "$CONFIG_DIR/docker-compose.yml" << EOF
version: '3.8'
services:
  xpanel:
    # SUBSTITUA pela imagem correta do seu painel
    image: sxconect/xpanel:latest
    container_name: xpanel-container
    restart: unless-stopped
    environment:
      - ADMIN_USER=\${ADMIN_USER}
      - ADMIN_PASS=\${ADMIN_PASS}
      - DOMAIN=\${DOMAIN}
      - SSL_ENABLED=false
    volumes:
      - ./data:/app/data
      - /var/log/xpanel:/app/logs
    networks:
      - traefik-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.xpanel.rule=Host(\`\${DOMAIN}\`) || PathPrefix(\`/\`)"
      - "traefik.http.routers.xpanel.entrypoints=web"
      - "traefik.http.services.xpanel.loadbalancer.server.port=3000"
      - "traefik.http.routers.xpanel.middlewares=default-headers@file"

networks:
  traefik-network:
    external: true
EOF
fi

# Criar .env
cat > "$CONFIG_DIR/.env" << EOF
ADMIN_USER=$ADMIN_USER
ADMIN_PASS=$ADMIN_PASS
DOMAIN=$DOMAIN
COMPOSE_PROJECT_NAME=xpanel
EOF
chmod 600 "$CONFIG_DIR/.env"
success ".env criado e protegido"

# Criar diretório de logs
mkdir -p /var/log/xpanel

# Subir xPanel
cd "$CONFIG_DIR"
docker compose up -d || error "Falha ao iniciar xPanel"
success "xPanel está rodando atrás do Traefik!"

# === 10. Configurar backup automático ===
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
    BACKUP_SCRIPT="/opt/xpanel-config/backup.sh"
    cat > "$BACKUP_SCRIPT" << 'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/opt/backups/xpanel-backup-$DATE.tar.gz"

# Parar containers temporariamente para backup consistente
cd /opt/xpanel-config
docker compose stop

# Fazer backup
tar -czf "$BACKUP_FILE" \
    -C /opt \
    xpanel-config/data \
    xpanel-config/.env \
    xpanel-config/docker-compose.yml \
    traefik/acme.json \
    traefik/config 2>/dev/null

# Reiniciar containers
docker compose start

# Limpar backups antigos (manter apenas os últimos 7)
find /opt/backups -name "xpanel-backup-*.tar.gz" -mtime +7 -delete 2>/dev/null || true

echo "[$(date)] Backup criado: $BACKUP_FILE"
echo "[$(date)] Backup criado: $BACKUP_FILE" >> /opt/xpanel-install.log
EOF
    chmod +x "$BACKUP_SCRIPT"
    (crontab -l 2>/dev/null; echo "$CRON_TIME $BACKUP_SCRIPT >> /var/log/xpanel-backup.log 2>&1") | crontab -
    success "Backup automático configurado: $CRON_TIME"
fi

# === 11. Comandos úteis no .bashrc (MELHORADOS) ===
cat >> /root/.bashrc << 'EOF'

# Comandos xPanel (gerados pelo instalador)
xpanel-logs() { docker logs -f xpanel-container 2>/dev/null || echo "Container não encontrado"; }
xpanel-traefik-logs() { docker logs -f traefik-proxy 2>/dev/null || echo "Traefik não encontrado"; }
xpanel-restart() { 
    echo "Reiniciando xPanel..."
    cd /opt/xpanel-config && docker compose restart
    echo "✅ xPanel reiniciado"
}
xpanel-update() { 
    echo "Atualizando xPanel..."
    cd /opt/xpanel-config
    docker compose pull
    docker compose up -d
    echo "✅ xPanel atualizado"
}
xpanel-backup() { 
    if [ -f /opt/xpanel-config/backup.sh ]; then
        /opt/xpanel-config/backup.sh
    else
        echo "❌ Script de backup não encontrado"
    fi
}
xpanel-status() { 
    echo "=== Status dos Containers ==="
    docker ps --filter name=traefik --filter name=xpanel --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo -e "\n=== Uso de Disco ==="
    df -h /opt | grep -v "Filesystem"
    echo -e "\n=== Rede Traefik ==="
    docker network inspect traefik-network --format "{{range .Containers}}{{.Name}} {{end}}" 2>/dev/null || echo "Rede não encontrada"
}
xpanel-uninstall() { 
    echo -e "\n⚠️  ATENÇÃO: Esta ação irá remover TUDO do xPanel!"
    echo "   - Containers Docker"
    echo "   - Configurações"
    echo "   - Dados do banco"
    echo "   - Backups"
    echo "   - Certificados SSL"
    echo ""
    read -p "Tem certeza? Digite 'REMOVER TUDO' para confirmar: " -r
    if [[ $REPLY == "REMOVER TUDO" ]]; then
        echo "🗑️ Removendo containers..."
        cd /opt/xpanel-config && docker compose down -v 2>/dev/null || true
        cd /opt/traefik && docker compose down -v 2>/dev/null || true
        
        echo "🗑️ Removendo arquivos..."
        rm -rf /opt/xpanel-config /opt/traefik /opt/backups /var/log/xpanel 2>/dev/null || true
        
        echo "🗑️ Limpando crontab..."
        crontab -l 2>/dev/null | grep -v "xpanel" | crontab - 2>/dev/null || true
        
        echo "🗑️ Removendo comandos do .bashrc..."
        sed -i '/# Comandos xPanel/,/^$/d' /root/.bashrc 2>/dev/null || true
        
        echo "🗑️ Removendo rede Docker..."
        docker network rm traefik-network 2>/dev/null || true
        
        echo "✅ xPanel completamente removido!"
    else
        echo "❌ Remoção cancelada."
    fi
}
EOF

# Recarregar .bashrc
source /root/.bashrc 2>/dev/null || true

# === 12. Verificações finais ===
log "Verificando se os containers estão rodando..."
sleep 5

TRAEFIK_STATUS=$(docker inspect -f '{{.State.Status}}' traefik-proxy 2>/dev/null || echo "not_found")
XPANEL_STATUS=$(docker inspect -f '{{.State.Status}}' xpanel-container 2>/dev/null || echo "not_found")

if [ "$TRAEFIK_STATUS" != "running" ]; then
    warn "Traefik não está rodando corretamente"
fi

if [ "$XPANEL_STATUS" != "running" ]; then
    warn "xPanel não está rodando corretamente"
fi

# === 13. Relatório Final ===
PROTOCOL=$([ "$USE_SSL" = true ] && echo "https" || echo "http")
TRAEFIK_DASHBOARD_URL=$([ "$USE_SSL" = true ] && echo "https://traefik.$DOMAIN" || echo "http://$DOMAIN:8080")

echo -e "
${GREEN}========================================${NC}
       ✅ INSTALAÇÃO CONCLUÍDA!
${GREEN}========================================${NC}

🔍 ACESSO PRINCIPAL:
  🔗 $PROTOCOL://$DOMAIN
  👤 Usuário: $ADMIN_USER
  🔐 Senha: [definida por você]

🛠️ TRAEFIK DASHBOARD:
  🔗 $TRAEFIK_DASHBOARD_URL

📋 COMANDOS ÚTEIS:
  xpanel-status       - Status dos containers
  xpanel-logs         - Logs do xPanel
  xpanel-traefik-logs - Logs do Traefik
  xpanel-restart      - Reiniciar xPanel
  xpanel-update       - Atualizar xPanel
  xpanel-backup       - Fazer backup manual
  xpanel-uninstall    - Remover tudo

📦 Backup automático: $( [ -n "$CRON_TIME" ] && echo "✅ ATIVO ($CRON_TIME)" || echo "❌ DESATIVADO" )

📁 DIRETÓRIOS:
  /opt/xpanel-config  - Configurações
  /opt/traefik        - Proxy reverso
  /opt/backups        - Backups automáticos
  /var/log/xpanel     - Logs da aplicação

📄 Log de instalação: $LOG_FILE

${GREEN}🚀 Sistema pronto para uso!${NC}
"

if [ "$USE_SSL" = true ]; then
    echo -e "${YELLOW}⏳ Aguarde alguns minutos para os certificados SSL serem gerados automaticamente.${NC}"
fi

log "Instalação finalizada com sucesso!"
echo -e "\n${GREEN}Para ver os logs em tempo real: xpanel-logs${NC}"