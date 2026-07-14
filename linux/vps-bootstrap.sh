#!/usr/bin/env bash
# =============================================================================
# vps-bootstrap.sh — Configura un nuevo Servidor VPS Primary
# =============================================================================
# Uso recomendado: DEPLOY_TOKEN=xxx ./vps-bootstrap.sh <env> <git-server-url>
# O simplemente ejecuta el script para ser guiado de forma interactiva.
# =============================================================================

set -euo pipefail

# 0. Comprobar permisos de root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root." >&2
    exit 1
fi

ENV="${1:-${ENV:-}}"
GIT_URL="${2:-${GIT_URL:-}}"
DEPLOY_TOKEN="${DEPLOY_TOKEN:-}"

# Advertir si se pasa el token en la línea de comandos por error
if [ -n "${3:-}" ]; then
    echo "ADVERTENCIA: Se ha detectado un tercer argumento en la línea de comandos." >&2
    echo "Para evitar registrar el token en el historial de comandos se recomienda" >&2
    echo "definirlo como variable de entorno o de forma interactiva." >&2
    DEPLOY_TOKEN="$3"
fi

# Solicitar de forma interactiva los valores que falten
if [ -z "$ENV" ]; then
    read -rp "Entorno (ej. production): " ENV
fi

if [ -z "$GIT_URL" ]; then
    read -rp "Git Server URL (ej. https://gitea.yourdomain.com): " GIT_URL
fi

if [ -z "$DEPLOY_TOKEN" ]; then
    read -rsp "Git Deploy Token (se ocultará al escribir): " DEPLOY_TOKEN
    echo
fi

COMPOSE_DIR="/opt/your-project"

echo "=== Bootstrap Server (PRIMARY) - Entorno: $ENV ==="

# Método de despliegue
if [ -z "${DEPLOY_METHOD:-}" ]; then
    echo "Elige el método de despliegue y gestión:"
    echo "1) Pure Docker Compose (Gestionado por terminal / CI/CD)"
    echo "2) Dokploy (Panel web para administración remota)"
    read -rp "Selecciona una opción [1 o 2, default: 1]: " SELECT_METHOD
    DEPLOY_METHOD="${SELECT_METHOD:-1}"
fi

# 1. Actualizar e Instalar dependencias
echo "[1/6] Actualizando paquetes e instalando dependencias (git, curl, ufw)..."
apt-get update
apt-get install -y git curl ufw

# 2. Instalar y Verificar Docker
echo "[2/6] Verificando e instalando Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
fi

# Esperar a que el demonio de Docker responda
echo "Esperando a que el servicio de Docker esté listo..."
until docker info >/dev/null 2>&1; do
    sleep 2
done

# Validar versión de Docker Compose
if ! docker compose version &> /dev/null; then
    echo "Docker Compose v2 no detectado. Instalando plugin..."
    apt-get install -y docker-compose-plugin
fi

# 3. Configurar firewall
echo "[3/6] Configurando firewall (UFW)..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp      # SSH
ufw allow 80/tcp      # HTTP
ufw allow 443/tcp     # HTTPS
ufw allow 1883/tcp    # MQTT (si aplica)
ufw allow 9001/tcp    # MQTT WebSockets (si aplica)

if [ "$DEPLOY_METHOD" = "2" ]; then
    ufw allow 3000/tcp    # Dokploy UI
else
    ufw allow 8080/tcp    # Health endpoint
fi

ufw --force enable

# 4. Clonar/Actualizar repositorio
echo "[4/6] Configurando repositorio..."
mkdir -p "$COMPOSE_DIR"

# Construir URL autenticada de Git
PROTO=$(echo "$GIT_URL" | grep :// | sed -e 's,^\(.*://\).*,\1,g')
if [ -z "$PROTO" ]; then
    PROTO="https://"
fi
HOST_AND_PORT=$(echo "$GIT_URL" | sed -e 's,^.*://,,g')
AUTH_REPO_URL="${PROTO}deploy:${DEPLOY_TOKEN}@${HOST_AND_PORT}/your-org/your-repo.git"

if [ -d "$COMPOSE_DIR/.git" ]; then
    echo "El repositorio ya existe. Actualizando remoto de git..."
    cd "$COMPOSE_DIR"
    git remote set-url origin "$AUTH_REPO_URL"
    git pull
else
    echo "Clonando repositorio..."
    git clone "$AUTH_REPO_URL" "$COMPOSE_DIR"
fi

# 5. Configurar .env
echo "[5/6] Configurando variables de entorno..."
cd "$COMPOSE_DIR"
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        cp ".env.example" ".env"
    else
        echo "DATABASE_URL=postgresql://user:pass@localhost:5432/db" > .env
    fi
    echo "========================================================================="
    echo "¡ATENCIÓN! Se ha creado un archivo .env base en: $COMPOSE_DIR/.env"
    echo "Por favor, edítalo con las credenciales reales de producción."
    echo "========================================================================="
    exit 0
fi

# 6. Desplegar
if [ "$DEPLOY_METHOD" = "2" ]; then
    echo "[6/6] Configurando Dokploy..."
    if docker ps -a --format '{{.Names}}' | grep -q "^dokploy$"; then
        echo "Dokploy ya está instalado y en ejecución."
    else
        echo "Instalando Dokploy..."
        docker run -d \
            --name dokploy \
            --restart always \
            -p 3000:3000 \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v /data/dokploy:/data \
            dokploy/dokploy:latest
    fi
    echo ""
    echo "=== Bootstrap con Dokploy completado ==="
    echo "Dokploy UI: http://<server-ip>:3000"
    echo "IMPORTANTE: Configura tus aplicaciones y Docker Compose desde el panel."
    echo ""
else
    echo "[6/6] Desplegando servicios con Docker Compose..."
    echo "$DEPLOY_TOKEN" | docker login "$GIT_URL" -u deploy --password-stdin
    docker compose pull
    docker compose up -d --remove-orphans
    echo ""
    echo "=== Bootstrap con Docker Compose completado ==="
    echo "Servicios activos."
    echo ""
fi
