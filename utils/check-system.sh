#!/bin/bash
# check-system.sh
# Verifica o sistema e pergunta se o usuário deseja continuar
# github.com/SxConnect/xpanel-installer

set -euo pipefail

# Cores
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variáveis
HAS_ERRORS=0
HAS_WARNINGS=0
REPORT=""

add_report() {
    REPORT+="$1\n"
}

# === 1. Verificar SO ===
if ! command -v lsb_release &> /dev/null; then
    add_report "${RED}❌ SO: 'lsb_release' não encontrado. Requer Ubuntu${NC}"
    HAS_ERRORS=1
else
    OS=$(lsb_release -is)
    VERSION=$(lsb_release -rs)
    if [[ "$OS" != "Ubuntu" ]]; then
        add_report "${RED}❌ SO: $OS não suportado. Requerido: Ubuntu${NC}"
        HAS_ERRORS=1
    elif ! [[ "$VERSION" =~ ^(20.04|22.04|24.04)$ ]]; then
        add_report "${RED}❌ Versão: Ubuntu $VERSION não suportada. Use 20.04, 22.04 ou 24.04${NC}"
        HAS_ERRORS=1
    else
        add_report "${GREEN}✅ SO: Ubuntu $VERSION (compatível)${NC}"
    fi
fi

# === 2. Arquitetura ===
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
    add_report "${RED}❌ Arquitetura: $ARCH não suportada. Requer x86_64${NC}"
    HAS_ERRORS=1
else
    add_report "${GREEN}✅ Arquitetura: $ARCH${NC}"
fi

# === 3. Recursos ===
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
DISK_GB=$(df / --output=size --block-size=G | tail -1 | tr -d 'G')
CPU_CORES=$(nproc)

add_report "${BLUE}📊 Recursos detectados:${NC}"
add_report "   RAM: ${RAM_GB}GB | Disco: ${DISK_GB}GB | CPU: ${CPU_CORES} core(s)"

if [ "$RAM_GB" -lt 2 ]; then
    add_report "${YELLOW}⚠️  RAM: $RAM_GB GB (recomendado: 2GB+)${NC}"
    HAS_WARNINGS=1
else
    add_report "${GREEN}✅ RAM: suficiente${NC}"
fi

if [ "$DISK_GB" -lt 20 ]; then
    add_report "${YELLOW}⚠️  Disco: $DISK_GB GB (recomendado: 20GB+)${NC}"
    HAS_WARNINGS=1
else
    add_report "${GREEN}✅ Disco: suficiente${NC}"
fi

if [ "$CPU_CORES" -lt 1 ]; then
    add_report "${RED}❌ CPU: menos de 1 core${NC}"
    HAS_ERRORS=1
else
    add_report "${GREEN}✅ CPU: $CPU_CORES core(s)${NC}"
fi

# === 4. Conectividade ===
add_report "${BLUE}🌐 Conectividade:${NC}"
if ! curl -s --connect-timeout 10 https://github.com > /dev/null; then
    add_report "${RED}❌ Falha ao conectar ao GitHub (verifique internet)${NC}"
    HAS_ERRORS=1
else
    add_report "${GREEN}✅ Conexão com GitHub: OK${NC}"
fi

# === 5. Portas 80 e 443 ===
PORTS=""
if command -v ss &> /dev/null; then
    PORTS=$(ss -tuln | grep -E ':(80|443)\s' | awk '{print $5}' | cut -d: -f2 | sort -u | tr '\n' ',' | sed 's/,$//')
elif command -v netstat &> /dev/null; then
    PORTS=$(netstat -tuln | grep -E ':(80|443)\s' | awk '{print $4}' | cut -d: -f2 | sort -u | tr '\n' ',' | sed 's/,$//')
fi

if [[ -n "$PORTS" ]]; then
    add_report "${RED}❌ Portas críticas ocupadas: $PORTS (feche nginx, apache, etc)${NC}"
    HAS_ERRORS=1
else
    add_report "${GREEN}✅ Portas 80 e 443: livres${NC}"
fi

# === 6. Docker ===
if command -v docker &> /dev/null; then
    add_report "${GREEN}✅ Docker: instalado ($(docker --version))${NC}"
else
    add_report "${BLUE}ℹ️  Docker: não instalado (será instalado pelo instalador)${NC}"
fi

# === Exibir Relatório Final ===
clear
echo -e "
${BLUE}========================================${NC}
     🧪 RELATÓRIO DE SISTEMA - xPanel
${BLUE}========================================${NC}
$(echo -e "$REPORT")
${BLUE}========================================${NC}
"

if [ "$HAS_ERRORS" -eq 1 ]; then
    echo -e "${RED}❌ Foram encontrados ERROS críticos.${NC}"
    echo -e "${RED}Corrija os problemas acima antes de continuar.${NC}"
    exit 1
fi

if [ "$HAS_WARNINGS" -eq 1 ]; then
    echo -e "${YELLOW}⚠️  Foram encontrados AVISOS (não críticos).${NC}"
fi

# === Perguntar se deseja continuar ===
echo -e "\n${GREEN}Deseja prosseguir com a instalação? (s/n): ${NC}\c"
read -n1 -r REPLY
echo

if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo -e "${YELLOW}Instalação cancelada pelo usuário.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Verificação concluída. Prosseguindo com a instalação...${NC}"
exit 0

