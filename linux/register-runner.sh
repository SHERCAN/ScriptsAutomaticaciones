#!/bin/bash
# =============================================================================
# Script de Registro e Instalación de un nuevo Gitea/GitHub Runner en Linux
# =============================================================================
# NOTA: Para hacer el script ejecutable y ejecutarlo:
#       chmod +x register-runner.sh
#       sudo ./register-runner.sh
# =============================================================================

# Salir ante cualquier error
set -e

# Configuración base
RUNNER_DIR="/opt/gitea-runner"

# Colores para la salida
GREEN='\033[0;32m'
NC='\033[0m' # Sin color
RED='\033[0;31m'
YELLOW='\033[1;33m'

log() {
    echo -e "${GREEN}[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"
    exit 1
}

# Verificar que se ejecuta como root/sudo
if [ "$EUID" -ne 0 ]; then
    error "Este script debe ejecutarse como root o con sudo."
fi

# --- CONFIGURACIÓN INTERACTIVA ---
echo -e "${GREEN}=== Setup Linux Runner para Gitea/GitHub Actions ===${NC}"

# 1. URL de la Instancia Gitea/GitHub
echo -e "${YELLOW}Ingresa la URL de tu instancia Gitea/GitHub (ej: https://gitea.yourdomain.com):${NC}"
read -r GITEA_URL
if [ -z "$GITEA_URL" ]; then
    error "La URL de la instancia no puede estar vacía."
fi

# 2. Token de Registro
REG_TOKEN=""
if [ -n "${1:-}" ]; then
    REG_TOKEN="$1"
else
    echo -e "${YELLOW}Ingresa el token de registro del runner:${NC}"
    read -r -s REG_TOKEN
fi
if [ -z "$REG_TOKEN" ]; then
    error "El token de registro no puede estar vacío."
fi

# 3. Nombre del Runner
DEFAULT_NAME=$(hostname)
echo -e "${YELLOW}Ingresa un nombre para este runner (Default: $DEFAULT_NAME):${NC}"
read -r RUNNER_NAME
RUNNER_NAME="${RUNNER_NAME:-$DEFAULT_NAME}"

# 4. Etiquetas
DEFAULT_LABELS="linux,self-hosted"
echo -e "${YELLOW}Ingresa las etiquetas para el runner separadas por coma (Default: $DEFAULT_LABELS):${NC}"
read -r RUNNER_LABELS
RUNNER_LABELS="${RUNNER_LABELS:-$DEFAULT_LABELS}"

# --- DETENER SERVICIO PREVIO SI EXISTE ---
if systemctl is-active --quiet gitea-runner || systemctl is-enabled --quiet gitea-runner; then
    log "Se detectó un servicio gitea-runner previo. Deteniendo y deshabilitando..."
    systemctl stop gitea-runner || true
    systemctl disable gitea-runner || true
fi

# 1. Crear directorio del runner
log "Creando directorio del runner en $RUNNER_DIR..."
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# 2. Descargar gitea-runner si no existe
if [ ! -f "gitea-runner" ]; then
    log "Buscando la última versión del runner de act_runner para Linux x64..."
    DOWNLOAD_URL=""
    
    # Intentar desde Gitea.com API
    log "Obteniendo información desde Gitea.com..."
    DOWNLOAD_URL=$(curl -s https://gitea.com/api/v1/repos/gitea/runner/releases/latest | grep -oP '"browser_download_url":\s*"\K[^"]+-linux-amd64(?=")' | head -n 1)
    
    # Fallback a GitHub API
    if [ -z "$DOWNLOAD_URL" ]; then
        warn "No se pudo obtener desde Gitea.com. Intentando fallback con GitHub..."
        DOWNLOAD_URL=$(curl -s https://api.github.com/repos/gitea/act_runner/releases/latest | grep -oP '"browser_download_url":\s*"\K[^"]+-linux-amd64(?=")' | head -n 1)
    fi

    # Fallback estático
    if [ -z "$DOWNLOAD_URL" ]; then
        DOWNLOAD_URL="https://gitea.com/gitea/runner/releases/download/v2.0.1/gitea-runner-2.0.1-linux-amd64"
        warn "No se pudo autodetectar la URL, usando fallback estático: $DOWNLOAD_URL"
    fi
    
    log "Descargando desde: $DOWNLOAD_URL..."
    curl -L "$DOWNLOAD_URL" -o gitea-runner
    chmod +x gitea-runner
else
    log "gitea-runner ya está descargado en este directorio."
fi

# 3. Generar archivo de configuración
log "Generando configuración por defecto config.yaml..."
./gitea-runner generate-config > config.yaml

# 4. Configurar etiquetas para usar las de la registración
log "Configurando config.yaml para usar las etiquetas del registro (.runner)..."
# Elimina las líneas con guiones de la sección de labels por defecto y deja labels vacíos: labels: []
sed -i '/labels:/,/^[^ ]/ { /^[[:space:]]*- /d }' config.yaml
sed -i 's/labels:.*$/labels: []/' config.yaml

# 5. Registrar el runner
log "Registrando el runner en el servidor Git con el nombre: $RUNNER_NAME..."
./gitea-runner register \
  --instance "$GITEA_URL" \
  --token "$REG_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$RUNNER_LABELS" \
  --no-interactive

if [ ! -f ".runner" ]; then
    error "El archivo '.runner' de registro no se generó. Registro fallido."
fi

# 6. Crear el archivo de servicio de systemd para Linux
log "Creando servicio systemd..."
cat <<EOF > /etc/systemd/system/gitea-runner.service
[Unit]
Description=Gitea Actions Runner ($RUNNER_NAME)
After=network.target docker.service

[Service]
Type=simple
WorkingDirectory=$RUNNER_DIR
Environment="HOME=/root"
ExecStart=$RUNNER_DIR/gitea-runner daemon --config $RUNNER_DIR/config.yaml
Restart=always
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# 7. Recargar systemd, habilitar e iniciar el servicio
log "Iniciando servicio de systemd..."
systemctl daemon-reload
systemctl enable gitea-runner
systemctl restart gitea-runner

# 8. Verificar estado
sleep 2
if systemctl is-active --quiet gitea-runner; then
    log "¡El runner gitea-runner ($RUNNER_NAME) se ha registrado e iniciado correctamente!"
    log "Puedes verificar su estado ejecutando: systemctl status gitea-runner"
else
    error "El servicio gitea-runner se instaló pero no se pudo iniciar."
fi
