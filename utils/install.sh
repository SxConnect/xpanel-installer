# === 12. Instalar Traefik (proxy + SSL) ===
log "Configurando Traefik como proxy reverso..."

TRAEFIK_DIR="/opt/traefik"
mkdir -p "$TRAEFIK_DIR" "$TRAEFIK_DIR/config"

# Baixar docker-compose.traefik.yml
curl -sSL https://raw.githubusercontent.com/seuusuario/xpanel-installer/main/traefik/docker-compose.traefik.yml -o "$TRAEFIK_DIR/docker-compose.yml"

# Criar acme.json
touch "$TRAEFIK_DIR/acme.json"
chmod 600 "$TRAEFIK_DIR/acme.json"
echo '{}' > "$TRAEFIK_DIR/acme.json"

# Criar dynamic.yml
cat > "$TRAEFIK_DIR/config/dynamic.yml" << EOF
http:
  services:
  routers:
  middlewares:
EOF

# Criar rede externa
docker network create traefik-network 2>/dev/null || true

# Subir Traefik
cd "$TRAEFIK_DIR"
docker compose up -d

success "Traefik está rodando com SSL automático!"