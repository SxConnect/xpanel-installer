#!/bin/bash
# install.sh - Instalador principal do xPanel (modo seguro - CORRIGIDO)
# Executado após o bootstrap clonar o repositório
# github.com/SxConnect/xpanel-installer

set -euo pipefail

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Detectar diretório do script atual
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
log "Diretório do script: $SCRIPT_DIR"

# === 1. Root check ===
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo bash install.sh"
fi

# === 2. Verificar sistema (scripts locais) ===
log "Verificando requisitos do sistema..."

# Verificar se o script auxiliar existe, se não, criar básico
if [ -f "$SCRIPT_DIR/utils/check-system.sh" ]; then
    bash "$SCRIPT_DIR/utils/check-system.sh"
else
    warn "Script check-system.sh não encontrado, fazendo verificação básica..."
    
    # Verificações básicas
    [ "$(uname)" = "Linux" ] || error "Sistema não é Linux"
    command -v curl >/dev/null || { log "Instalando curl..."; apt update && apt install -y curl; }
    command -v wget >/dev/null || { log "Instalando wget..."; apt install -y wget; }
    
    success "Verificações básicas concluídas"
fi

# === 3. Configurar firewall ===
log "Configurando firewall..."

if [ -f "$SCRIPT_DIR/utils/setup-firewall.sh" ]; then
    bash "$SCRIPT_DIR/utils/setup-firewall.sh"
else
    warn "Script setup-firewall.sh não encontrado, configurando firewall básico..."
    
    # Configuração básica do UFW
    if command -v ufw >/dev/null; then
        ufw --force enable
        ufw allow ssh
        ufw allow 80/tcp
        ufw allow 443/tcp
        success "Firewall configurado"
    else
        warn "UFW não instalado, pulando configuração de firewall"
    fi
fi

# === 4. Atualizar sistema ===
log "Atualizando sistema..."
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
    log "Instalando Docker Compose..."
    apt install -y docker-compose-plugin
fi

# === 6. Criar rede Traefik ===
docker network create traefik-network 2>/dev/null || true
success "Rede traefik-network criada."

# === 7. Instalar Traefik ===
log "Configurando Traefik como proxy reverso..."

mkdir -p "$TRAEFIK_DIR" "$TRAEFIK_DIR/config"

# Verificar se arquivos de configuração existem, se não, criar básicos
if [ -f "$SCRIPT_DIR/traefik/docker-compose.yml" ]; then
    cp "$SCRIPT_DIR/traefik/docker-compose.yml" "$TRAEFIK_DIR/docker-compose.yml"
else
    warn "docker-compose.yml do Traefik não encontrado, criando básico..."
    cat > "$TRAEFIK_DIR/docker-compose.yml" << 'EOF'
version: '3.8'
services:
  traefik:
    image: traefik:v2.10
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./acme.json:/acme.json
      - ./config:/config:ro
    command:
      - --api.dashboard=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --providers.file.directory=/config
      - --providers.file.watch=true
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --certificatesresolvers.letsencrypt.acme.email=admin@localhost
      - --certificatesresolvers.letsencrypt.acme.storage=/acme.json
      - --certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web
    networks:
      - traefik-network

networks:
  traefik-network:
    external: true
EOF
fi

# Configurar acme.json
if [ -f "$SCRIPT_DIR/traefik/acme.json" ]; then
    cp "$SCRIPT_DIR/traefik/acme.json" "$TRAEFIK_DIR/acme.json"
else
    echo '{}' > "$TRAEFIK_DIR/acme.json"
fi
chmod 600 "$TRAEFIK_DIR/acme.json"

# Configurar dynamic.yml
if [ -f "$SCRIPT_DIR/traefik/config/dynamic.yml" ]; then
    cp "$SCRIPT_DIR/traefik/config/dynamic.yml" "$TRAEFIK_DIR/config/dynamic.yml"
else
    warn "dynamic.yml não encontrado, criando básico..."
    cat > "$TRAEFIK_DIR/config/dynamic.yml" << 'EOF'
http:
  middlewares:
    default-headers:
      headers:
        frameDeny: true
        sslRedirect: true
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000
EOF
fi

# Subir Traefik
cd "$TRAEFIK_DIR"
if command -v docker compose &> /dev/null; then
    docker compose up -d || error "Falha ao iniciar Traefik"
else
    docker-compose up -d || error "Falha ao iniciar Traefik"
fi
success "Traefik está rodando com SSL automático!"

# === 8. Perguntar IP ou Domínio ===
echo -e "\n${YELLOW}Como você quer acessar o painel?${NC}"
read -p "Acessar via [I]P ou [D]omínio? (i/d): " ACCESS_TYPE
ACCESS_TYPE=${ACCESS_TYPE,,} # converter para minúsculo

if [[ "$ACCESS_TYPE" == "d" || "$ACCESS_TYPE" == "dominio" ]]; then
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

rm -rf "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR"

# Verificar se configuração do xPanel existe
if [ -d "$SCRIPT_DIR/xpanel-config" ]; then
    cp -r "$SCRIPT_DIR/xpanel-config/." "$CONFIG_DIR/"
else
    warn "Configuração xpanel-config não encontrada, criando básica..."
    
    # Criar docker-compose.yml básico para o xPanel
    cat > "$CONFIG_DIR/docker-compose.yml" << 'EOF'
version: '3.8'
services:
  xpanel:
    image: nginx:alpine
    container_name: xpanel-container
    restart: unless-stopped
    volumes:
      - ./html:/usr/share/nginx/html
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.xpanel.rule=Host(`${DOMAIN}`)"
      - "traefik.http.routers.xpanel.tls.certresolver=letsencrypt"
      - "traefik.http.services.xpanel.loadbalancer.server.port=80"
    networks:
      - traefik-network

networks:
  traefik-network:
    external: true
EOF

    # Criar página HTML básica
    mkdir -p "$CONFIG_DIR/html"
    cat > "$CONFIG_DIR/html/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>xPanel</title>
    <style>
        body { font-family: Arial; text-align: center; padding: 50px; }
        .container { max-width: 500px; margin: 0 auto; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 xPanel Instalado!</h1>
        <p>Usuário: <strong>$ADMIN_USER</strong></p>
        <p>Acesso: <strong>https://$DOMAIN</strong></p>
        <hr>
        <small>Configuração básica - Substitua pelos arquivos reais do xPanel</small>
    </div>
</body>
</html>
EOF
fi

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

# Substituir variáveis no docker-compose.yml se necessário
if command -v envsubst >/dev/null; then
    envsubst < docker-compose.yml > docker-compose.tmp && mv docker-compose.tmp docker-compose.yml
fi

if command -v docker compose &> /dev/null; then
    docker compose up -d || error "Falha ao iniciar xPanel"
else
    docker-compose up -d || error "Falha ao iniciar xPanel"
fi
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
    BACKUP_SCRIPT="$SCRIPT_DIR/utils/backup.sh"
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
xpanel-restart() { cd /opt/xpanel-config && docker compose restart || docker-compose restart; }
xpanel-update() { cd /opt/xpanel-config && git pull && (docker compose up -d || docker-compose up -d); }
xpanel-backup() { sudo /opt/xpanel-installer/utils/backup.sh 2>/dev/null || echo "Script de backup não encontrado"; }
xpanel-restore() { sudo /opt/xpanel-installer/utils/restore.sh 2>/dev/null || echo "Script de restore não encontrado"; }
xpanel-status() { 
    echo "=== Status dos Containers ==="
    docker ps --filter name=traefik --filter name=xpanel
    echo "=== Espaço em Disco ==="
    df -h /opt
}
xpanel-uninstall() { 
    echo "⚠️  CUIDADO: Isso irá remover TUDO do xPanel!"
    read -p "Desinstalar completamente? Digite 'CONFIRMAR': " -r
    if [[ $REPLY == "CONFIRMAR" ]]; then
        echo "Parando containers..."
        cd /opt/xpanel-config 2>/dev/null && (docker compose down || docker-compose down) 2>/dev/null
        cd /opt/traefik 2>/dev/null && (docker compose down || docker-compose down) 2>/dev/null
        
        echo "Removendo arquivos..."
        rm -rf /opt/xpanel-config /opt/traefik /opt/xpanel-installer /opt/backups 2>/dev/null || true
        
        echo "Limpando comandos..."
        sed -i '/# Comandos xPanel/,/^$/d' /root/.bashrc 2>/dev/null || true
        
        echo "✅ xPanel completamente removido!"
    else
        echo "❌ Cancelado."
    fi
}
EOF

# === 13. Teste final ===
log "Verificando se os serviços estão funcionando..."
sleep 5

TRAEFIK_STATUS=$(docker ps --filter "name=traefik" --format "{{.Status}}" 2>/dev/null || echo "Não encontrado")
XPANEL_STATUS=$(docker ps --filter "name=xpanel" --format "{{.Status}}" 2>/dev/null || echo "Não encontrado")

# === 14. Relatório Final ===
echo -e "
${GREEN}========================================${NC}
       ✅ INSTALAÇÃO CONCLUÍDA!
${GREEN}========================================${NC}

🔍 Informações de Acesso:
  🔗 URL: https://$DOMAIN
  👤 Usuário: $ADMIN_USER
  🔐 Senha: [definida por você]

📊 Status dos Serviços:
  🔄 Traefik: $TRAEFIK_STATUS
  🖥️  xPanel: $XPANEL_STATUS

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

# Carregar novos comandos no bash atual
source /root/.bashrc 2>/dev/null || true

log "Instalação finalizada com sucesso!"
"