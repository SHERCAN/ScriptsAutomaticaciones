#!/usr/bin/env bash
# =============================================================================
# cloudflare-setup.sh — Configura DNS y Load Balancer en Cloudflare
# =============================================================================
# Uso: ./cloudflare-setup.sh <dominio> <ip-server-a> <ip-server-b>
# Ejemplo: ./cloudflare-setup.sh example.com 1.2.3.4 5.6.7.8
# =============================================================================

set -euo pipefail

# --- CONFIGURACIÓN DE CREDENCIALES ---
# Define tus credenciales de Cloudflare aquí o pásalas como variables de entorno
CF_TOKEN="${CF_TOKEN:-YOUR_CLOUDFLARE_API_TOKEN}"
CF_ZONE_ID="${CF_ZONE_ID:-YOUR_CLOUDFLARE_ZONE_ID}"
CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-YOUR_CLOUDFLARE_ACCOUNT_ID}"
CF_NOTIFY_EMAIL="${CF_NOTIFY_EMAIL:-your-email@example.com}"
CLOUDFLARE_API="${CLOUDFLARE_API:-https://api.cloudflare.com/client/v4}"

# Validación de parámetros obligatorios
DOMAIN="${1:?Uso: $0 <dominio> <ip-server-a> <ip-server-b>}"
IP_A="${2:?Uso: $0 <dominio> <ip-server-a> <ip-server-b>}"
IP_B="${3:?Uso: $0 <dominio> <ip-server-a> <ip-server-b>}"

# Validar que las credenciales no sean los valores por defecto
if [[ "$CF_TOKEN" == "YOUR_CLOUDFLARE_API_TOKEN" ]] || [[ "$CF_ZONE_ID" == "YOUR_CLOUDFLARE_ZONE_ID" ]]; then
    echo "❌ ERROR: Por favor, edita las credenciales de Cloudflare en la cabecera del script antes de ejecutarlo." >&2
    exit 1
fi

echo "=== Configurando Cloudflare para $DOMAIN ==="

# Subdominios a crear
SUBDOMAINS=(
    "@"
    "www"
    "app"
    "admin"
    "console"
    "mobile"
    "campo"
    "api"
    "build"
)

create_dns_record() {
    local name="$1" content="$2" type="${3:-A}" proxied="${4:-true}"
    echo "  DNS $type: $name.$DOMAIN -> $content (proxy=$proxied)"
    curl -s -X POST "$CLOUDFLARE_API/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"proxied\":$proxied}" > /dev/null
}

echo ""
echo "1. Creando registros DNS apuntando al Load Balancer..."

# Los subdominios principales apuntan a Server A (el LB decidirá)
for sub in "${SUBDOMAINS[@]}"; do
    create_dns_record "$sub" "$IP_A" "A" true
done

echo ""
echo "2. Creando Load Balancer..."

# Crear Pool A (primary)
POOL_A=$(curl -s -X POST "$CLOUDFLARE_API/accounts/$CF_ACCOUNT_ID/load_balancers/pools" \
    -H "Authorization: Bearer $CF_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{
        \"name\": \"$DOMAIN-pool-primary\",
        \"description\": \"Primary server A\",
        \"enabled\": true,
        \"minimum_origin_health\": 1,
        \"notification_email\": \"$CF_NOTIFY_EMAIL\",
        \"origins\": [
            {
                \"name\": \"server-a\",
                \"address\": \"$IP_A\",
                \"enabled\": true
            }
        ],
        \"check_regions\": [\"WEU\", \"EEU\", \"ENAM\"],
        \"origin_steering\": {
            \"policy\": \"random\"
        }
    }" | jq -r '.result.id')

# Crear Pool B (standby)
POOL_B=$(curl -s -X POST "$CLOUDFLARE_API/accounts/$CF_ACCOUNT_ID/load_balancers/pools" \
    -H "Authorization: Bearer $CF_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{
        \"name\": \"$DOMAIN-pool-standby\",
        \"description\": \"Standby server B\",
        \"enabled\": true,
        \"minimum_origin_health\": 1,
        \"notification_email\": \"$CF_NOTIFY_EMAIL\",
        \"origins\": [
            {
                \"name\": \"server-b\",
                \"address\": \"$IP_B\",
                \"enabled\": true
            }
        ],
        \"check_regions\": [\"WEU\", \"EEU\", \"ENAM\"],
        \"origin_steering\": {
            \"policy\": \"random\"
        }
    }" | jq -r '.result.id')

# Crear health check monitor
MONITOR_ID=$(curl -s -X POST "$CLOUDFLARE_API/accounts/$CF_ACCOUNT_ID/load_balancers/monitors" \
    -H "Authorization: Bearer $CF_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{
        \"type\": \"http\",
        \"description\": \"HTTP health check on port 8080\",
        \"method\": \"GET\",
        \"path\": \"/health\",
        \"port\": 8080,
        \"expected_codes\": \"200\",
        \"interval\": 30,
        \"retries\": 3,
        \"timeout\": 10,
        \"probe_zone\": \"$DOMAIN\"
    }" | jq -r '.result.id')

# Asignar monitor a pools
curl -s -X PATCH "$CLOUDFLARE_API/accounts/$CF_ACCOUNT_ID/load_balancers/pools/$POOL_A" \
    -H "Authorization: Bearer $CF_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"monitor\": \"$MONITOR_ID\"}" > /dev/null

curl -s -X PATCH "$CLOUDFLARE_API/accounts/$CF_ACCOUNT_ID/load_balancers/pools/$POOL_B" \
    -H "Authorization: Bearer $CF_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"monitor\": \"$MONITOR_ID\"}" > /dev/null

# Crear el Load Balancer
curl -s -X POST "$CLOUDFLARE_API/accounts/$CF_ACCOUNT_ID/load_balancers" \
    -H "Authorization: Bearer $CF_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{
        \"name\": \"$DOMAIN-lb\",
        \"description\": \"Load Balancer for $DOMAIN\",
        \"enabled\": true,
        \"ttl\": 30,
        \"proxied\": true,
        \"fallback_pool\": \"$POOL_B\",
        \"default_pools\": [\"$POOL_A\", \"$POOL_B\"],
        \"pop_steering_policy\": \"dynamic_latency\",
        \"region_pools\": {
            \"EEU\": [\"$POOL_A\"],
            \"WEU\": [\"$POOL_A\"],
            \"ENAM\": [\"$POOL_A\"]
        }
    }" > /dev/null

echo ""
echo "=== Configuración completada ==="
echo "Load Balancer activo con health checks cada 30s"
echo "Failover automático si Server A falla 3 checks (~90s)"
