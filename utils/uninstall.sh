#!/bin/bash
# xPanel Auto Installer com Traefik
# github.com/seuusuario/xpanel-installer

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
GITHUB_CONFIGS="https://github.com/seuusuario/xpanel-config.git"

# Funções
log() { echo -e "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
error() { log "${RED}ERRO: $1${NC}" >&2; exit 1; }
success() { log "${GREEN}SUCESSO: $1${NC}"; }
warn() { log "${YELLOW}AVISO: $1${NC}"; }

# === 0. Preparar ambiente ===
mkdir -p "$SCRIPT_DIR"
touch "$LOG_FILE"
log "Iniciando instalador do xPanel com Traefik..."

# === 1. Root check ===
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo bash install.sh"
fi

# === 2. Ubuntu check ===
if ! command -v lsb_release &> /dev/null; then
    error "Ubuntu não detectado."
fi

UBUNTU_VERSION=$(lsb_release -rs)
if ! [[ "$UBUNTU_VERSION" =~ ^(20.04|22.04|24.04)$ ]]; then
    error "Ubuntu $UBUNTU_VERSION não suportado."
fi
success "Ubuntu $UBUNTU_VERSION OK."

# === 3. Atualizar sistema ===
apt update && apt upgrade -y

# === 4. Docker ===
if ! command -v docker &> /dev/null; then
    log "Instalando Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker --now
    success "Docker instalado."
fi

# === 5. Criar rede Traefik ===
docker network create traefik-network 2>/dev/null || true
success "Rede traefik-network criada."

# === 6. Instalar Traefik ===
log "Configurando Traefik como proxy reverso..."

mkdir -p "$TRAEFIK_DIR" "$TRAEFIK_DIR/config"

# Baixar docker-compose.yml do Traefik
curl -sSL https://raw.githubusercontent.com/seuusuario/xpanel-installer/main/traefik/docker-compose.yml -o "$TRAEFIK_DIR/docker-compose.yml"

# Criar acme.json com permissão segura
touch "$TRAEFIK_DIR/acme.json"
echo '{}' > "$TRAEFIK_DIR/acme.json"
chmod 600 "$TRAEFIK_DIR/acme.json"
success "acme.json criado com permissão 600"

# Criar dynamic.yml
cat > "$TRAEFIK_DIR/config/dynamic.yml" << EOF
http:
  services:
  routers:
  middlewares:
EOF

# Subir Traefik
cd "$TRAEFIK_DIR"
docker compose up -d
success "Traefik está rodando com SSL automático!"

# === 7. Perguntar IP ou Domínio ===
read -p "Acessar via IP ou Domínio? [ip/dominio]: " ACCESS_TYPE
if [[ "$ACCESS_TYPE" == "dominio" ]]; then
    read -p "Domínio ou subdomínio (ex: painel.seusite.com): " DOMAIN
else
    IP=$(curl -s ifconfig.me)
    DOMAIN="$IP"
fi

# === 8. Credenciais do xPanel ===
log "Configurando usuário admin..."

while true; do
    read -p "Usuário admin: " ADMIN_USER
    ADMIN_USER=$(echo "$ADMIN_USER" | xargs)
    [ -n "$ADMIN_USER" ] && break || warn "Usuário não pode ser vazio."
done

while true; do
    read -s -p "Senha admin: " ADMIN_PASS; echo
    [ ${#ADMIN_PASS} -ge 6 ] || { warn "Senha mínima: 6 caracteres."; continue; }
    read -s -p "Confirme a senha: " ADMIN_PASS_CONFIRM; echo
    [ "$ADMIN_PASS" = "$ADMIN_PASS_CONFIRM" ] && break || warn "Senhas não coincidem."
done

# === 9. Clonar configurações do xPanel ===
rm -rf "$CONFIG_DIR"
git clone "$GITHUB_CONFIGS" "$CONFIG_DIR"
cd "$CONFIG_DIR"

# Criar .env
cat > .env << EOF
ADMIN_USER=$ADMIN_USER
ADMIN_PASS=$ADMIN_PASS
DOMAIN=$DOMAIN
EOF
chmod 600 .env
success ".env criado e protegido"

# Subir xPanel
docker compose up -d
success "xPanel está rodando atrás do Traefik!"

# === 10. Comandos úteis ===
cat >> /root/.bashrc << 'EOF'

# Comandos xPanel
xpanel-logs() { docker logs -f xpanel-container; }
xpanel-restart() { cd /opt/xpanel-config && docker compose restart; }
xpanel-update() { cd /opt/xpanel-config && git pull && docker compose up -d; }
xpanel-uninstall() { 
    read -p "Desinstalar tudo? (s/n): " -n1 -r; echo
    [[ $REPLY =~ ^[Ss]$ ]] && cd /opt/xpanel-config && docker compose down && rm -rf /opt/xpanel-config && echo "xPanel removido."
}
EOF

# === 11. Relatório Final ===
echo -e "
${GREEN}========================================${NC}
       ✅ xPanel + Traefik INSTALADO!
${GREEN}========================================${NC}
Acesse: https://$DOMAIN
Usuário: $ADMIN_USER
Senha: ****** (definida por você)

🔐 SSL automático via Let's Encrypt
🛠️ Traefik protege todas as conexões

Comandos úteis:
  xpanel-logs     → Ver logs
  xpanel-restart  → Reiniciar
  xpanel-update   → Atualizar

Dashboard do Traefik: https://traefik.$DOMAIN (ativar em /opt/traefik/config/dynamic.yml)

Logs: $LOG_FILE
"