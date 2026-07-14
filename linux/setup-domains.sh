#!/usr/bin/env bash
# =============================================================================
# setup-domains.sh — Script de Automatización de Dominios (Cloudflare y Dokploy)
# =============================================================================
#
# Propósito:
#   Este script automatiza el flujo completo de enrutamiento y despliegue de 
#   los subdominios requeridos por la plataforma en un entorno de producción.
#   
#   Realiza dos tareas principales:
#     1. Crea o actualiza registros DNS tipo "A" en Cloudflare apuntando a la
#        IP pública del servidor VPS, con el Proxy (CDN) activo.
#     2. Registra los dominios en la API de Dokploy asociándolos a cada servicio 
#        específico dentro de la pila Docker Compose (con SSL automático 
#        mediante Let's Encrypt), e inicia un re-despliegue de la pila.
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# 1. Configuración por Defecto y Variables de Estado
# -----------------------------------------------------------------------------

DOMAIN=""                     # Dominio base (ej. tu-dominio.com). Se solicita si falta.
SERVER_IP=""                  # IP pública del VPS. Se solicita si falta.
PROJECT_NAME="your-project"   # Nombre del proyecto en el panel de Dokploy.
COMPOSE_NAME="your-compose"   # Nombre de la aplicación Docker Compose en Dokploy.
CF_TOKEN=""                   # Token de API de Cloudflare (permisos DNS Edit).
CF_ZONE_ID=""                 # ID de la Zona de Cloudflare asignada al dominio.
DOKPLOY_API_URL=""            # URL base de la API de Dokploy.
DOKPLOY_API_KEY=""            # Token/API Key de Dokploy.
DRY_RUN=false                 # true para modo de simulación sin aplicar cambios.
SKIP_REDEPLOY=false           # true para omitir el re-despliegue automático de la pila.

CLOUDFLARE_API="https://api.cloudflare.com/client/v4"

# -----------------------------------------------------------------------------
# 2. Función de Carga Segura de Archivos de Entorno (.env)
# -----------------------------------------------------------------------------
load_env_file() {
    local env_file="$1"
    if [ -f "$env_file" ]; then
        echo "ℹ️ Cargando variables de entorno desde $env_file..."
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line##[[:space:]]}"
            [[ "$line" =~ ^# ]] && continue
            [[ -z "$line" ]] && continue
            if [[ "$line" == *=* ]]; then
                local key="${line%%=*}"
                local value="${line#*=}"
                value="${value%%#*}"
                key="${key#"${key%%[![:space:]]*}"}"
                key="${key%"${key##*[![:space:]]}"}"
                value="${value#"${value%%[![:space:]]*}"}"
                value="${value%"${value##*[![:space:]]}"}"
                if [[ "$value" =~ ^\".*\"$ ]] || [[ "$value" =~ ^\'.*\'$ ]]; then
                    value="${value:1:${#value}-2}"
                fi
                if [ -n "$key" ]; then
                    declare -x "$key=$value" 2>/dev/null || true
                fi
            fi
        done < "$env_file"
    fi
}

# Cargar configuración desde archivos locales
load_env_file ".env"
load_env_file ".env.production"

# Acoplar variables precargadas desde el entorno
DOMAIN="${DOMAIN:-${APP_DOMAIN:-}}"
SERVER_IP="${SERVER_IP:-${APP_IP:-}}"
CF_TOKEN="${CF_TOKEN:-${CLOUDFLARE_TOKEN:-}}"
CF_ZONE_ID="${CF_ZONE_ID:-${CLOUDFLARE_ZONE_ID:-}}"
DOKPLOY_API_URL="${DOKPLOY_API_URL:-}"
DOKPLOY_API_KEY="${DOKPLOY_API_KEY:-}"

# -----------------------------------------------------------------------------
# 3. Procesamiento de Argumentos de la Línea de Comandos
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain) DOMAIN="$2"; shift 2 ;;
        --ip) SERVER_IP="$2"; shift 2 ;;
        --project) PROJECT_NAME="$2"; shift 2 ;;
        --compose) COMPOSE_NAME="$2"; shift 2 ;;
        --cf-token) CF_TOKEN="$2"; shift 2 ;;
        --cf-zone-id) CF_ZONE_ID="$2"; shift 2 ;;
        --dokploy-url) DOKPLOY_API_URL="$2"; shift 2 ;;
        --dokploy-key) DOKPLOY_API_KEY="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --skip-redeploy) SKIP_REDEPLOY=true; shift ;;
        -h|--help)
            echo "Uso: $0 [opciones]"
            echo ""
            echo "Opciones:"
            echo "  --domain <dominio>         Dominio principal (ej. tu-dominio.com)"
            echo "  --ip <ip>                  IP pública del servidor VPS"
            echo "  --project <nombre>         Nombre del proyecto en Dokploy"
            echo "  --compose <nombre>         Nombre de la app Compose en Dokploy"
            echo "  --cf-token <token>         Token de Cloudflare API"
            echo "  --cf-zone-id <id>          Zone ID de Cloudflare"
            echo "  --dokploy-url <url>        URL API Dokploy"
            echo "  --dokploy-key <key>        API Key de Dokploy"
            echo "  --dry-run                  Modo simulación"
            echo "  --skip-redeploy            Evita el re-despliegue automático en Dokploy"
            exit 0
            ;;
        *)
            echo "❌ Opción desconocida: $1"
            exit 1
            ;;
    esac
done

# -----------------------------------------------------------------------------
# 4. Validaciones de Entorno e Interactividad
# -----------------------------------------------------------------------------
if ! command -v curl &>/dev/null; then
    echo "❌ Error: Se requiere 'curl' instalado en el sistema."
    exit 1
fi

# Buscador tolerante de 'jq'
JQ_CMD="jq"
if ! command -v jq &>/dev/null; then
    if [ -f "$HOME/jq" ]; then
        JQ_CMD="$HOME/jq"
    elif [ -f "$HOME/bin/jq" ]; then
        JQ_CMD="$HOME/bin/jq"
    elif [ -f "./jq" ]; then
        JQ_CMD="./jq"
    else
        echo "❌ Error: Se requiere 'jq' instalado en el sistema para procesar respuestas JSON."
        exit 1
    fi
fi

if [ -z "$DOMAIN" ]; then
    read -rp "Introduce el dominio principal (ej. tu-dominio.com): " DOMAIN
fi

if [ -z "$SERVER_IP" ]; then
    read -rp "Introduce la IP pública del servidor VPS: " SERVER_IP
fi

if [ -z "$DOMAIN" ] || [ -z "$SERVER_IP" ]; then
    echo "❌ Error: El dominio y la IP del servidor son campos obligatorios."
    exit 1
fi

if [ -z "$DOKPLOY_API_URL" ]; then
    DOKPLOY_API_URL="http://$SERVER_IP:3000/api"
fi

RUN_CLOUDFLARE=true
if [ -z "$CF_TOKEN" ] || [ -z "$CF_ZONE_ID" ]; then
    echo "⚠️ Advertencia: Falta CF_TOKEN o CF_ZONE_ID. Se omitirá Cloudflare."
    RUN_CLOUDFLARE=false
fi

RUN_DOKPLOY=true
if [ -z "$DOKPLOY_API_KEY" ]; then
    echo "⚠️ Advertencia: Falta DOKPLOY_API_KEY. Se omitirá Dokploy."
    RUN_DOKPLOY=false
fi

if [ "$RUN_CLOUDFLARE" = false ] && [ "$RUN_DOKPLOY" = false ]; then
    echo "❌ Error: No hay credenciales configuradas para Cloudflare ni para Dokploy."
    exit 1
fi

# -----------------------------------------------------------------------------
# 5. Mapeo de Subdominios a Contenedores Docker Compose
# -----------------------------------------------------------------------------
# Formato: "subdominio:nombre_servicio_docker:puerto_interno"
MAPPINGS=(
    "@:landing:80"                # tu-dominio.com -> contenedor 'landing' puerto 80
    "www:landing:80"              # www.tu-dominio.com -> contenedor 'landing' puerto 80
    "app:frontend-admin:80"       # app.tu-dominio.com -> contenedor 'frontend-admin' puerto 80
    "console:frontend-console:80" # console.tu-dominio.com -> contenedor 'frontend-console' puerto 80
    "api:backend-api:8000"        # api.tu-dominio.com -> contenedor 'backend-api' puerto 8000
    "mqtt:mosquitto:9001"         # mqtt.tu-dominio.com -> broker websocket mosquitto puerto 9001
)

# -----------------------------------------------------------------------------
# 6. Funciones de Integración con la API de Cloudflare (DNS)
# -----------------------------------------------------------------------------
setup_cloudflare_dns() {
    local name="$1" content="$2" type="${3:-A}" proxied="${4:-true}"
    local record_name
    
    if [ "$name" = "@" ]; then
        record_name="$DOMAIN"
    else
        record_name="$name.$DOMAIN"
    fi

    echo "  → Configurando DNS para $record_name -> $content"

    local search_res
    search_res=$(curl -s -X GET "$CLOUDFLARE_API/zones/$CF_ZONE_ID/dns_records?name=$record_name&type=$type" \
        -H "Authorization: Bearer $CF_TOKEN" \
        -H "Content-Type: application/json")

    if ! echo "$search_res" | "$JQ_CMD" -e '.success' | grep -q "true"; then
        local err
        err=$(echo "$search_res" | "$JQ_CMD" -r '.errors[0].message // "Error en autenticación/red"')
        echo "    ❌ Falló la consulta a Cloudflare: $err"
        return 1
    fi

    local record_id
    record_id=$(echo "$search_res" | "$JQ_CMD" -r '.result[0].id // empty')

    local payload
    payload=$("$JQ_CMD" -n \
        --arg type "$type" \
        --arg name "$record_name" \
        --arg content "$content" \
        --argjson proxied "$proxied" \
        '{type: $type, name: $name, content: $content, proxied: $proxied, ttl: 1}')

    local response
    if [ -n "$record_id" ]; then
        response=$(curl -s -X PUT "$CLOUDFLARE_API/zones/$CF_ZONE_ID/dns_records/$record_id" \
            -H "Authorization: Bearer $CF_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$payload")
    else
        response=$(curl -s -X POST "$CLOUDFLARE_API/zones/$CF_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CF_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$payload")
    fi

    if echo "$response" | "$JQ_CMD" -e '.success' | grep -q "true"; then
        echo "    ✅ DNS $record_name configurado con éxito."
    else
        local err
        err=$(echo "$response" | "$JQ_CMD" -r '.errors[0].message // "Error desconocido"')
        echo "    ❌ Falló la creación/actualización de DNS $record_name: $err"
    fi
}

# -----------------------------------------------------------------------------
# 7. Funciones de Integración con la API de Dokploy (Enrutamiento)
# -----------------------------------------------------------------------------
create_dokploy_domain() {
    local host="$1" service="$2" port="$3" compose_id="$4"
    echo "  → Registrando en Dokploy: $host -> servicio '$service' (puerto $port)"

    local payload
    payload=$("$JQ_CMD" -n \
        --arg host "$host" \
        --arg composeId "$compose_id" \
        --arg serviceName "$service" \
        --argjson port "$port" \
        '{host: $host, composeId: $composeId, serviceName: $serviceName, port: $port, https: true, certificateType: "letsencrypt", path: "/"}')

    local response
    response=$(curl -s -X POST "$DOKPLOY_API_URL/domain.create" \
        -H "x-api-key: $DOKPLOY_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload")

    if echo "$response" | "$JQ_CMD" -e '.error // .message // empty' > /dev/null; then
        local error_msg
        error_msg=$(echo "$response" | "$JQ_CMD" -r '.message // .error')
        if [[ "$error_msg" == *"already exists"* || "$error_msg" == *"Duplicate"* ]]; then
            echo "    ⚠️ El dominio $host ya está registrado en Dokploy. Saltando..."
        else
            echo "    ❌ Error al registrar dominio $host en Dokploy: $error_msg"
        fi
    else
        echo "    ✅ Dominio $host enrutado con éxito."
    fi
}

redeploy_dokploy_compose() {
    local compose_id="$1"
    echo "=== Solicitando Re-despliegue de la pila en Dokploy ==="
    local response
    response=$(curl -s -X POST "$DOKPLOY_API_URL/compose.redeploy" \
        -H "x-api-key: $DOKPLOY_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"composeId\":\"$compose_id\"}")

    if echo "$response" | "$JQ_CMD" -e '.error // .message // empty' > /dev/null; then
        local error_msg
        error_msg=$(echo "$response" | "$JQ_CMD" -r '.message // .error')
        echo "  ❌ Error al solicitar re-despliegue: $error_msg"
    else
        echo "  ✅ Re-despliegue iniciado con éxito en Dokploy."
    fi
}

# =============================================================================
# 8. Ejecución del Script (Flujo de Control)
# =============================================================================

echo "========================================================="
echo "  AUTOMATIZACIÓN DE DOMINIOS Y ENRUTAMIENTO"
echo "  Dominio: $DOMAIN"
echo "  IP Servidor: $SERVER_IP"
if [ "$DRY_RUN" = true ]; then
    echo "  ⚠️ MODO SIMULACIÓN ACTIVO (No se harán cambios reales)"
fi
echo "========================================================="

# Paso 1: Configurar DNS en Cloudflare
if [ "$RUN_CLOUDFLARE" = true ]; then
    echo ""
    echo "=== Paso 1: Configurando registros DNS en Cloudflare ==="
    for mapping in "${MAPPINGS[@]}"; do
        IFS=":" read -r sub service port <<< "$mapping"
        
        record_name=""
        if [ "$sub" = "@" ]; then record_name="$DOMAIN"; else record_name="$sub.$DOMAIN"; fi
        
        if [ "$DRY_RUN" = true ]; then
            echo "  [SIMULACIÓN] Crear/Actualizar A: $record_name -> $SERVER_IP (proxied=true)"
        else
            setup_cloudflare_dns "$sub" "$SERVER_IP" "A" true
        fi
    done
fi

# Paso 2: Resolución de recursos en Dokploy
if [ "$RUN_DOKPLOY" = true ]; then
    echo ""
    echo "=== Paso 2: Conectando con Dokploy y buscando recursos ==="
    
    compose_id="dummy-compose-id"
    
    if [ "$DRY_RUN" = false ]; then
        projects_json=$(curl -s -f -X GET "$DOKPLOY_API_URL/project.all" -H "x-api-key: $DOKPLOY_API_KEY")
        if [ $? -ne 0 ] || [ -z "$projects_json" ]; then
            echo "❌ Error: No se pudo conectar a Dokploy o la API key es inválida."
            exit 1
        fi

        project_id=$(echo "$projects_json" | "$JQ_CMD" -r --arg name "$PROJECT_NAME" '.[] | select(.name == $name) | .projectId // empty')
        
        if [ -z "$project_id" ]; then
            echo "❌ Error: El proyecto '$PROJECT_NAME' no fue encontrado en Dokploy."
            exit 1
        fi
        echo "  ✅ Proyecto '$PROJECT_NAME' encontrado. (ID: $project_id)"

        project_details=$(curl -s -f -X GET "$DOKPLOY_API_URL/project.one?projectId=$project_id" -H "x-api-key: $DOKPLOY_API_KEY")
        compose_id=$(echo "$project_details" | "$JQ_CMD" -r --arg name "$COMPOSE_NAME" '.compose[] | select(.name == $name) | .composeId // .id // empty')

        if [ -z "$compose_id" ]; then
            echo "❌ Error: El recurso Docker Compose '$COMPOSE_NAME' no fue encontrado."
            exit 1
        fi
        echo "  ✅ Docker Compose '$COMPOSE_NAME' encontrado. (ID: $compose_id)"
    else
        echo "  [SIMULACIÓN] Buscado proyecto '$PROJECT_NAME' y Compose '$COMPOSE_NAME'."
    fi

    # Paso 3: Registrar dominios en Dokploy
    echo ""
    echo "=== Paso 3: Registrando dominios en Dokploy ==="
    for mapping in "${MAPPINGS[@]}"; do
        IFS=":" read -r sub service port <<< "$mapping"
        
        host=""
        if [ "$sub" = "@" ]; then host="$DOMAIN"; else host="$sub.$DOMAIN"; fi

        if [ "$DRY_RUN" = true ]; then
            echo "  [SIMULACIÓN] Registrar dominio: $host -> servicio '$service' (puerto $port)"
        else
            create_dokploy_domain "$host" "$service" "$port" "$compose_id"
        fi
    done

    # Paso 4: Re-despliegue
    if [ "$SKIP_REDEPLOY" = false ]; then
        echo ""
        if [ "$DRY_RUN" = true ]; then
            echo "  [SIMULACIÓN] Re-desplegar compose con ID $compose_id"
        else
            redeploy_dokploy_compose "$compose_id"
        fi
    fi
fi

echo ""
echo "========================================================="
echo "  🎉 PROCESO FINALIZADO CON ÉXITO"
echo "========================================================="
