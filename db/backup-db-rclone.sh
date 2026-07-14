#!/bin/bash
# =============================================================================
# backup-db-rclone.sh — Copia de seguridad diaria de PostgreSQL / TimescaleDB
# =============================================================================
# Propósito:
#   Realiza un pg_dump comprimido de la base de datos local y, si está
#   disponible rclone, sube el archivo a un almacenamiento en la nube (ej. Google Drive).
#   También limpia copias locales antiguas mayores a un número de días determinado.
# =============================================================================

set -euo pipefail

# --- CONFIGURACIÓN DE CONEXIÓN Y DESTINO ---
DB_HOST="${DB_HOST:-localhost}"
DB_USER="${DB_USER:-your_db_user}"
DB_NAME="${DB_NAME:-your_db_name}"
# Si deseas omitir la petición de contraseña de pg_dump, define PGPASSWORD en el entorno.

BACKUP_DIR="/var/backups/db-backups" # Directorio local para guardar los backups
KEEP_DAYS=7                         # Días a retener los backups locales
RCLONE_REMOTE="gdrive:db-backups"   # Nombre de la conexión rclone y la carpeta remota

DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${DATE}.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Iniciando copia de seguridad de la base de datos '${DB_NAME}'..."

# Dump database con compresión gzip
pg_dump -h "$DB_HOST" -U "$DB_USER" "$DB_NAME" | gzip > "$BACKUP_FILE"

echo "[$(date)] Copia de seguridad creada localmente: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"

# Subir a la nube mediante Rclone si está configurado
if command -v rclone &> /dev/null; then
    echo "[$(date)] Subiendo copia de seguridad al remoto '${RCLONE_REMOTE}'..."
    rclone copy "$BACKUP_FILE" "$RCLONE_REMOTE/" --progress
    echo "[$(date)] Subida completada."
else
    echo "[$(date)] ADVERTENCIA: 'rclone' no encontrado. La copia de seguridad solo se guardará localmente."
fi

# Eliminar copias de seguridad locales más antiguas de KEEP_DAYS
echo "[$(date)] Limpiando copias de seguridad locales de más de $KEEP_DAYS días..."
find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -mtime +"$KEEP_DAYS" -delete

echo "[$(date)] Proceso de copia de seguridad completado."
