#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Despliegue automático (usado por CI/CD y automatizaciones)
# =============================================================================
# Uso: ./deploy.sh <server-host> <git-registry>
# =============================================================================

set -euo pipefail

# --- CONFIGURACIÓN ---
COMPOSE_DIR="/opt/your-project"
APP_PORT="8000"  # Puerto interno a monitorear para el health check
HEALTH_PATH="/health"

SERVER_HOST="${1:?Uso: $0 <server-host> <git-registry>}"
GIT_REGISTRY="${2:?Uso: $0 <server-host> <git-registry>}"

# Credenciales de despliegue obtenidas de variables de entorno
DEPLOY_USER="${GIT_DEPLOY_USER:-your_deploy_user}"
DEPLOY_TOKEN="${GIT_DEPLOY_TOKEN:-your_deploy_token}"

echo "=== Deploy en $SERVER_HOST ==="

# 1. Autenticar en registry
echo "[1/4] Autenticando en $GIT_REGISTRY..."
echo "$DEPLOY_TOKEN" | docker login "$GIT_REGISTRY" -u "$DEPLOY_USER" --password-stdin

# 2. Pull de imágenes
echo "[2/4] Descargando imágenes..."
cd "$COMPOSE_DIR"
docker compose pull

# 3. Desplegar
echo "[3/4] Desplegando servicios..."
docker compose up -d --remove-orphans

# 4. Verificar health
echo "[4/4] Verificando health..."
for i in $(seq 1 12); do
    if curl -sf "http://localhost:${APP_PORT}${HEALTH_PATH}" > /dev/null 2>&1; then
        echo "  ✅ Application API healthy"
        break
    fi
    if [ "$i" -eq 12 ]; then
        echo "  ❌ Application API no responde después de 60s"
        exit 1
    fi
    sleep 5
done

echo "=== Deploy completado ==="
