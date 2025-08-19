#!/bin/bash
# status.sh
# Mostra status do xPanel, Traefik e sistema
# github.com/seuusuario/xpanel-installer

set -euo pipefail

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Funções
log() { echo -e "[$(date +'%H:%M:%S')] $1"; }
warn() { log "${YELLOW}AVISO: $1${NC}"; }

# === Cabeçalho ===
echo -e "
${BLUE}========================================${NC}
       📊 STATUS DO SISTEMA - xPanel
${BLUE}========================================${NC}
"

# === xPanel ===
echo -e "${BLUE}🔧 xPanel${NC}"
if docker ps --filter "name=xpanel-container" --format '{{.Status}}' | grep -q "Up"; then
    PORT=$(docker port xpanel-container | grep 3000 | awk '{print $2}')
    echo -e "   ${GREEN}✅ Ativo${NC} | Container: xpanel-container"
    echo -e "   🔗 Mapeado para: $PORT"
else
    echo -e "   ${RED}❌ Inativo${NC}"
fi

# === Traefik ===
echo -e "\n${BLUE}🛡️  Traefik (Proxy)${NC}"
if docker ps --filter "name=traefik-proxy" --format '{{.Status}}' | grep -q "Up"; then
    echo -e "   ${GREEN}✅ Ativo${NC} | Container: traefik-proxy"
    echo -e "   🔌 Portas: 80 (HTTP), 443 (HTTPS)"
else
    echo -e "   ${RED}❌ Inativo${NC}"
fi

# === Rede ===
echo -e "\n${BLUE}🌐 Rede${NC}"
if docker network ls --filter "name=traefik-network" -q | grep -q .; then
    echo -e "   ${GREEN}✅ Rede 'traefik-network' existe${NC}"
else
    echo -e "   ${RED}❌ Rede 'traefik-network' não encontrada${NC}"
fi

# === SSL (acme.json) ===
echo -e "\n${BLUE}🔐 SSL (Let's Encrypt)${NC}"
ACME="/opt/traefik/acme.json"
if [ -f "$ACME" ] && [ -s "$ACME" ]; then
    SIZE=$(stat -c%s "$ACME")
    if [ $SIZE -gt 100 ]; then
        echo -e "   ${GREEN}✅ Certificado SSL armazenado${NC}"
        # Extrair domínio (opcional)
        DOMAIN=$(grep -o '"domain":"[^"]*"' "$ACME" | head -1 | cut -d'"' -f4 2>/dev/null || echo "não detectado")
        echo -e "   🌐 Domínio: $DOMAIN"
    else
        echo -e "   ${YELLOW}⚠️  acme.json existe, mas vazio${NC}"
    fi
else
    echo -e "   ${RED}❌ acme.json não encontrado ou vazio${NC}"
fi

# === Uso de Recursos ===
echo -e "\n${BLUE}📊 Recursos do Sistema${NC}"
RAM_USED=$(free -h | awk '/^Mem:/{print $3}')
RAM_TOTAL=$(free -h | awk '/^Mem:/{print $2}')
DISK_USED=$(df -h / | awk 'NR==2{print $3}')
DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}')
CPU_LOAD=$(uptime | awk -F'load average:' '{print $2}' | xargs)

echo "   🧠 RAM: $RAM_USED / $RAM_TOTAL"
echo "   💾 Disco: $DISK_USED / $DISK_TOTAL"
echo "   ⚙️  CPU Load: $CPU_LOAD"

# === Comando útil ===
echo -e "\n💡 Execute 'xpanel-logs' para ver os logs em tempo real"
echo -e "${BLUE}========================================${NC}\n"