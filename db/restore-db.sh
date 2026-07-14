#!/bin/bash
# =============================================================================
# restore-db.sh — Restaura base de datos a partir de archivos comprimidos sql.gz
# =============================================================================
# Uso: ./restore-db.sh <ruta_al_archivo_backup.sql.gz>
# =============================================================================

set -euo pipefail

# --- CONFIGURACIÓN ---
DB_HOST="${DB_HOST:-localhost}"
DB_USER="${DB_USER:-your_db_user}"
DB_NAME="${DB_NAME:-your_db_name}"
BACKUP_DIR="/var/backups/db-backups"

if [ $# -eq 0 ]; then
  echo "Uso: $0 <archivo_backup.sql.gz>"
  echo ""
  echo "Copias de seguridad locales disponibles en $BACKUP_DIR:"
  ls -lh "$BACKUP_DIR"/*.sql.gz 2>/dev/null || echo "  No se encontraron copias de seguridad locales."
  exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "❌ ERROR: Archivo de copia de seguridad no encontrado: $BACKUP_FILE"
  exit 1
fi

echo "⚠️  ADVERTENCIA: ¡Esto SOBREESCRIBIRÁ la base de datos actual '$DB_NAME'!"
read -rp "¿Estás seguro de continuar? (escribe 'yes' para confirmar): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Operación cancelada."
  exit 0
fi

echo "[$(date)] Restaurando base de datos '$DB_NAME' desde: $BACKUP_FILE..."

# Descomprimir y restaurar
gunzip -c "$BACKUP_FILE" | psql -h "$DB_HOST" -U "$DB_USER" "$DB_NAME"

echo "[$(date)] Restauración completada con éxito."
