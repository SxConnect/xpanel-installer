#!/bin/bash
# ssl-setup.sh
# Configura SSL com Let's Encrypt (Certbot) para domínios
# github.com/seuusuario/xpanel-installer

set -euo pipefail

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variáveis (serão passadas pelo install.sh)
DOMAIN=""
EMAIL="admin"
AUTO="false"

# Funções
log() { echo -e "[$(date +'%H:%M:%S')] $1"; }
warn() { log "${YELLOW}AVISO: $1${NC}"; }
error() { log "${RED}ERRO: $1${NC}" >&2; exit 1; }
success() { log "${GREEN}OK: $1${NC}"; }

# === Ajuda ===
show_help() {
    cat << EOF
Uso: $0 --domain <dominio> [--email <email>] [--auto]

Exemplo:
  $0 --domain painel.seusite.com --email contato@seusite.com

Opções:
  --domain    Domínio ou subdomínio a proteger
  --email     Email para Let's Encrypt (padrão: admin@dominio)
  --auto      Modo silencioso (sem perguntas)
EOF
    exit 1
}

# === Parse de argumentos ===
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"; shift 2 ;;
        --email)
            EMAIL="$2"; shift 2 ;;
        --auto)
            AUTO="true"; shift ;;
        -h|--help)
            show_help ;;
        *)
            error "Argumento desconhecido: $1"
            ;;
    esac
done

if [ -z "$DOMAIN" ]; then
    error "Domínio não fornecido. Use --domain."
fi

# === Verificar se é root ===
if [ "$EUID" -ne 0 ]; then
    error "Este script requer root. Execute com sudo."
fi

# === Definir email padrão ===
if [ "$EMAIL" == "admin" ]; then
    EMAIL="admin@${DOMAIN}"
fi

# === Verificar conectividade ===
log "Verificando se o domínio responde..."
if ! timeout 10 bash -c "ping -c1 $DOMAIN &> /dev/null"; then
    warn "Domínio $DOMAIN não responde a ping (pode ser normal)"
else
    success "Domínio $DOMAIN está acessível por rede"
fi

# === Verificar se o domínio aponta para este IP ===
PUBLIC_IP=$(curl -s ifconfig.me)
DOMAIN_IP=$(dig +short "$DOMAIN" | tail -1)

if [ -n "$DOMAIN_IP" ] && [ "$DOMAIN_IP" != "$PUBLIC_IP" ]; then
    error "Domínio $DOMAIN aponta para $DOMAIN_IP, mas este servidor é $PUBLIC_IP. Verifique o DNS."
fi

# === Instalar Certbot se necessário ===
if ! command -v certbot &> /dev/null; then
    log "Instalando Certbot..."
    apt update && apt install certbot python3-certbot-nginx -y || error "Falha ao instalar Certbot"
    success "Certbot instalado"
else
    success "Certbot já instalado"
fi

# === Perguntar se deseja emitir SSL ===
if [ "$AUTO" != "true" ]; then
    echo -e "
${BLUE}========================================${NC}
       🔐 CONFIGURAÇÃO DE SSL
${BLUE}========================================${NC}
Domínio: $DOMAIN
Email: $EMAIL

O certificado será emitido usando o plugin NGINX.
Isso requer que o NGINX esteja rodando e acessível na porta 80.

${YELLOW}Deseja emitir o certificado SSL agora? (s/n): ${NC}\c"
    read -n1 -r REPLY; echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        warn "Emissão de SSL cancelada pelo usuário."
        exit 0
    fi
fi

# === Emitir certificado ===
log "Emitindo certificado SSL com Certbot..."
certbot --nginx \
    --domain "$DOMAIN" \
    --email "$EMAIL" \
    --agree-tos \
    --non-interactive \
    --redirect \
    --hsts \
    --staple-ocsp

if [ $? -eq 0 ]; then
    success "✅ Certificado SSL emitido com sucesso para $DOMAIN"
    echo -e "
${GREEN}🔐 SSL ATIVO${NC}
Domínio: $DOMAIN
Expira em: $(date -d "`certbot certificates --domain $DOMAIN | grep 'Expiry Date' | awk '{print $4, $5, $6}'`" +"%d/%m/%Y")
Renovação automática: habilitada (via cron)
"
else
    error "Falha ao emitir certificado SSL"
fi

# === Verificar renovação automática ===
if ! crontab -l | grep -q "certbot.*renew"; then
    (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
    success "Renovação automática programada (diária)"
fi

exit 0

