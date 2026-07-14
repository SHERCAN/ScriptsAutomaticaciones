#!/bin/bash
# =============================================================================
# Script de Registro e Instalación de un nuevo Gitea/GitHub Runner en Linux
# =============================================================================

# Salir ante cualquier error
set -e

# Configuración por defecto
RUNNER_DIR="/opt/gitea-runner"
RUNNER_NAME="your-runner-name"
GITEA_URL="https://gitea.yourdomain.com"
RUNNER_LABELS="linux,self-hosted"

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

# Solicitar el Token de Registro
REG_TOKEN=""
if [ -z "${1:-}" ]; then
    echo -e "${YELLOW}Por favor, ingresa el Registration Token de tu servidor Git:${NC}"
    read -r REG_TOKEN
else
    REG_TOKEN="$1"
fi

if [ -z "$REG_TOKEN" ]; then
    error "El token de registro no puede estar vacío."
fi

# 1. Crear directorio del runner
log "Creando directorio del runner en $RUNNER_DIR..."
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# 2. Descargar gitea-runner si no existe
if [ ! -f "gitea-runner" ]; then
    log "Obteniendo la última versión de gitea-runner para Linux x64..."
    DOWNLOAD_URL=$(curl -s https://gitea.com/api/v1/repos/gitea/runner/releases | grep -oP '"browser_download_url":\s*"\K[^"]+linux-amd64' | head -n 1)
    
    if [ -z "$DOWNLOAD_URL" ]; then
        DOWNLOAD_URL="https://gitea.com/gitea/runner/releases/download/v2.0.1/gitea-runner-2.0.1-linux-amd64"
        warn "No se pudo obtener la última versión, descargando versión fallback: $DOWNLOAD_URL"
    fi
    
    log "Descargando desde: $DOWNLOAD_URL..."
    curl -L "$DOWNLOAD_URL" -o gitea-runner
    chmod +x gitea-runner
else
    log "gitea-runner ya está descargado."
fi

# 3. Generar archivo de configuración
log "Generando configuración por defecto config.yaml..."
./gitea-runner generate-config > config.yaml

# 4. Configurar etiquetas personalizadas en config.yaml
log "Configurando etiquetas en config.yaml..."
sed -i "/labels:/,/^[^ ]/ {
    /labels:/a\    - \"${RUNNER_LABELS}\"
}" config.yaml

# 5. Registrar el runner
log "Registrando el runner con el nombre: $RUNNER_NAME..."
./gitea-runner register \
  --instance "$GITEA_URL" \
  --token "$REG_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$RUNNER_LABELS" \
  --no-interactive

# 6. Crear el archivo de servicio de systemd para Linux
log "Creando servicio systemd..."
cat <<EOF > /etc/systemd/system/gitea-runner.service
[Unit]
Description=Gitea Actions Runner ($RUNNER_NAME)
After=network.target docker.socket
Requires=docker.socket

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
