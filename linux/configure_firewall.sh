#!/bin/bash
# =============================================================================
# SCADA System - Configuración de Firewall para VPS (Linux)
# Este script detecta el firewall activo (UFW, firewalld o iptables)
# y abre los puertos necesarios para el correcto funcionamiento del sistema.
#
# INSTRUCCIONES DE USO EN EL VPS:
# 1. Sube este archivo al VPS (vía SFTP/SCP) o copia y pega su contenido.
# 2. Si vienes de Windows, limpia los saltos de línea (CRLF) ejecutando:
#       tr -d '\r' < configure_firewall.sh > vps_firewall.sh
# 3. Asigna permisos de ejecución al script limpio:
#       chmod +x vps_firewall.sh
# 4. Ejecútalo como superusuario (root):
#       sudo ./vps_firewall.sh
# =============================================================================

# Asegurar que se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Por favor, ejecuta este script como root (sudo)."
    exit 1
fi

echo "🔍 Detectando sistema de firewall activo..."

# Listas de puertos a configurar
INBOUND_TCP_PORTS=(80 443 1883 8883 9883 3000)
OUTBOUND_TCP_PORTS=(25 465 587)

# -----------------------------------------------------------------------------
# 1. Configuración usando UFW (Debian/Ubuntu)
# -----------------------------------------------------------------------------
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    echo "🔥 UFW detectado y activo. Configurando reglas..."
    
    # Permitir puertos de entrada
    for port in "${INBOUND_TCP_PORTS[@]}"; do
        echo "  - Permitir entrada TCP puerto $port"
        ufw allow "$port/tcp" >/dev/null
    done
    
    # Permitir puertos de salida (por defecto UFW permite todo de salida,
    # pero los configuramos explícitamente por seguridad si la política por defecto es denegar)
    for port in "${OUTBOUND_TCP_PORTS[@]}"; do
        echo "  - Permitir salida TCP puerto $port"
        ufw allow out "$port/tcp" >/dev/null
    done
    
    echo "🔄 Recargando reglas de UFW..."
    ufw reload >/dev/null
    echo "✅ Firewall configurado correctamente con UFW."

# -----------------------------------------------------------------------------
# 2. Configuración usando Firewalld (CentOS/RHEL/Rocky/Alma Linux)
# -----------------------------------------------------------------------------
elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    echo "🔥 Firewalld detectado y activo. Configurando reglas..."
    
    # Permitir puertos de entrada
    for port in "${INBOUND_TCP_PORTS[@]}"; do
        echo "  - Permitir entrada TCP puerto $port"
        firewall-cmd --permanent --add-port="$port/tcp" >/dev/null
    done
    
    # Nota: Firewalld permite todo el tráfico de salida por defecto en la zona estándar.
    
    echo "🔄 Recargando reglas de Firewalld..."
    firewall-cmd --reload >/dev/null
    echo "✅ Firewall configurado correctamente con Firewalld."

# -----------------------------------------------------------------------------
# 3. Configuración fallback usando iptables
# -----------------------------------------------------------------------------
elif command -v iptables >/dev/null 2>&1; then
    echo "🔥 No se detectó UFW ni Firewalld activos. Usando iptables directamente..."
    
    # Permitir entrada
    for port in "${INBOUND_TCP_PORTS[@]}"; do
        echo "  - Permitir entrada TCP puerto $port"
        iptables -A INPUT -p tcp --dport "$port" -m state --state NEW,ESTABLISHED -j ACCEPT
    done
    
    # Permitir salida
    for port in "${OUTBOUND_TCP_PORTS[@]}"; do
        echo "  - Permitir salida TCP puerto $port"
        iptables -A OUTPUT -p tcp --dport "$port" -m state --state NEW,ESTABLISHED -j ACCEPT
    done
    
    # Guardar reglas según distribución
    if [ -f /etc/debian_version ]; then
        if command -v iptables-save >/dev/null 2>&1; then
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/rules.v4
            echo "💾 Reglas guardadas en /etc/iptables/rules.v4"
        fi
    elif [ -f /etc/redhat-release ]; then
        service iptables save >/dev/null 2>&1 || iptables-save > /etc/sysconfig/iptables
        echo "💾 Reglas guardadas en /etc/sysconfig/iptables"
    fi
    
    echo "✅ Firewall configurado correctamente con iptables."

else
    echo "❌ Error: No se pudo detectar ningún sistema de firewall activo (UFW, Firewalld o iptables)."
    exit 1
fi

echo ""
echo "====================================================================="
echo "🎉 ¡Configuración del firewall del VPS completada!"
echo "====================================================================="
echo "Puertos abiertos para el flujo del sistema SCADA:"
echo "  📥 Entradas (Inbound):"
echo "     - 80/443 (HTTP/HTTPS para Traefik y Dokploy Web Services)"
echo "     - 1883 (MQTT - Conexión de Agentes sin TLS)"
echo "     - 8883 (MQTT - Conexión de Agentes con TLS/SSL)"
echo "     - 9883 (MQTT - Conexión de Agentes sobre WebSockets)"
echo "     - 3000 (Acceso a consola de administración / Dokploy)"
echo "  📤 Salidas (Outbound):"
echo "     - 25, 465, 587 (SMTP/SMTPS para el flujo de correos de verificación)"
echo "====================================================================="
echo "⚠️  NOTA IMPORTANTE:"
echo "Si después de ejecutar este script los correos siguen sin enviarse,"
echo "es un bloqueo a nivel de red por parte de tu proveedor de VPS."
echo "Deberás abrir un ticket de soporte con ellos (ej. Contabo) para"
echo "que desbloqueen los puertos SMTP de tu IP."
echo "====================================================================="
