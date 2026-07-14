#!/usr/bin/env bash
# =============================================================================
# failback.sh — Reversa de failover: Server A vuelve a ser PRIMARY
# =============================================================================
# Uso: ./failback.sh <ip-server-a> <ip-server-b>
# EJECUTAR EN SERVER B (STANDBY) después de que Server A se haya recuperado
# =============================================================================

set -euo pipefail

# --- CONFIGURACIÓN DE PROYECTO ---
COMPOSE_DIR="/opt/your-project"
DB_CONTAINER="your-db-container"  # Ej: timescaledb, postgres
DB_USER="${DB_USER:-your_db_user}"
DB_NAME="${DB_NAME:-your_db_name}"
DB_PASSWORD="${DB_PASSWORD:-your_db_password}"

# Lista de servicios a detener en Server B temporalmente para sincronizar datos
SERVICES_TO_STOP=(
    "backend-api"
    "events-relay"
    "telemetry-ingestor"
    "frontend-pwa"
    "frontend-admin"
    "mosquitto"
)

# Validación de parámetros
SERVER_A="${1:?Uso: $0 <ip-server-a> <ip-server-b>}"
SERVER_B="${2:?Uso: $0 <ip-server-a> <ip-server-b>}"

echo "=== FAILBACK: Reversando failover ==="
echo "Server A: $SERVER_A"
echo "Server B: $SERVER_B (servidor actual)"

# Verificar que Server A está online
echo ""
echo "[1/7] Verificando que Server A responde..."
if ! ping -c 3 "$SERVER_A" &> /dev/null; then
    echo "  ❌ Server A no responde ping. Abortando."
    exit 1
fi
if ! curl -sf "http://$SERVER_A:8080/health" &> /dev/null; then
    echo "  ⚠️  Server A responde ping pero no responde el health endpoint."
    echo "  ¿Está Docker funcionando en Server A?"
    read -rp "  ¿Continuar de todas formas? (s/N): " confirm
    if [ "$confirm" != "s" ]; then
        exit 1
    fi
fi

# 1. Detener servicios de aplicación en Server B
echo "[2/7] Deteniendo servicios de aplicación en Server B..."
cd "$COMPOSE_DIR"
docker compose stop "${SERVICES_TO_STOP[@]}" 2>/dev/null || true

# 2. Sincronizar datos de la Base de Datos de vuelta a Server A
echo "[3/7] Sincronizando Base de Datos con Server A..."
docker exec "$DB_CONTAINER" pg_dump -U "${DB_USER}" -d "${DB_NAME}" \
    -F c -f /tmp/backup.dump 2>/dev/null || true

# Transferir backup a Server A
scp /tmp/backup.dump "root@$SERVER_A:/tmp/backup.dump" 2>/dev/null || {
    echo "  ⚠️  No se pudo copiar backup a Server A"
    echo "  ¿Quieres continuar con failback? (se perderán datos recientes)"
    read -rp "  ¿Continuar? (s/N): " confirm
    if [ "$confirm" != "s" ]; then
        exit 1
    fi
}

# 3. Restaurar backup en Server A
echo "[4/7] Restaurando backup en Server A..."
ssh "root@$SERVER_A" "
    cd $COMPOSE_DIR
    docker compose up -d $DB_CONTAINER
    sleep 10
    pg_restore -U ${DB_USER} -d ${DB_NAME} -F c /tmp/backup.dump 2>/dev/null || true
    rm -f /tmp/backup.dump
" || echo "  ⚠️  Restauración con posibles advertencias/errores no críticos"

# 4. Reconfigurar DB en Server A como primary
echo "[5/7] Reconfigurando Server A como primary..."
ssh "root@$SERVER_A" "
    cd $COMPOSE_DIR
    docker compose down
    rm -f /var/lib/postgresql/data/standby.signal
    sed -i '/primary_conninfo/d' /var/lib/postgresql/data/postgresql.conf
    docker compose up -d
" || {
    echo "  ❌ Error reconfigurando Server A"
    exit 1
}

# 5. Reconfigurar Server B como replica
echo "[6/7] Reconfigurando Server B como replica..."
cd "$COMPOSE_DIR"
docker compose down "$DB_CONTAINER" 2>/dev/null || true
rm -rf /var/lib/postgresql/data.bak
mv /var/lib/postgresql/data /var/lib/postgresql/data.bak 2>/dev/null || true

# pg_basebackup desde Server A
docker run --rm \
    -e PGPASSWORD="${DB_PASSWORD}" \
    timescale/timescaledb:2.26.1-pg16 \
    pg_basebackup -h "$SERVER_A" \
        -U "${DB_USER}" \
        -D /var/lib/postgresql/data \
        -P -R --wal-method=stream

# Iniciar replica
docker compose up -d "$DB_CONTAINER"

# 6. Limpiar y reiniciar agentes auxiliares
echo "[7/7] Reiniciando agentes de monitoreo/health..."
docker compose down failover-agent 2>/dev/null || true
docker compose up -d failover-agent health-endpoint 2>/dev/null || true

echo ""
echo "=== FAILBACK COMPLETADO ==="
echo "Server A ahora es PRIMARY"
echo "Server B ahora es STANDBY"
echo ""
echo "Verifica: curl http://$SERVER_A:8080/health"
