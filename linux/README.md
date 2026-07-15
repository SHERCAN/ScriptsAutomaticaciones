# Scripts de Automatización para Linux

Esta carpeta contiene scripts orientados a servidores y sistemas basados en Linux (Bash/Shell).

## 📂 Contenido de la carpeta

### 1. [`cloudflare-setup.sh`](./cloudflare-setup.sh)
Configura automáticamente registros DNS y balanceadores de carga en Cloudflare mediante peticiones REST a su API v4.
*   **Caso de uso**: Despliegue de arquitecturas con alta disponibilidad y failover automático basado en Health Checks HTTP.
*   **Variables clave**:
    *   `CF_TOKEN`: Token de API con permisos de edición de DNS.
    *   `CF_ZONE_ID`: ID de zona de tu dominio en Cloudflare.
    *   `CF_ACCOUNT_ID`: ID de tu cuenta de Cloudflare (requerido para los pools de Load Balancing).
*   **Uso**:
    ```bash
    ./cloudflare-setup.sh tu-dominio.com 192.168.1.10 192.168.1.11
    ```

### 2. [`setup-domains.sh`](./setup-domains.sh)
Automatiza la sincronización de dominios entre Dokploy (Traefik) y registros DNS de Cloudflare de manera combinada.
*   **Caso de uso**: Al añadir un nuevo subdominio a tu aplicación web Docker Compose gestionada por Dokploy, este script crea el registro DNS proxied en Cloudflare, añade la regla de dominio en Dokploy con SSL Let's Encrypt automático y ejecuta el despliegue del stack.
*   **Uso**:
    ```bash
    ./setup-domains.sh --domain tu-dominio.com --ip 192.168.1.10 --dokploy-key tu_api_key
    ```

### 3. [`vps-bootstrap.sh`](./vps-bootstrap.sh)
Configuración inicial y aprovisionamiento de un servidor Linux limpio para actuar como host principal.
*   **Caso de uso**: Configuración de SSH, UFW, Git, instalación de Docker, descarga del código fuente del proyecto desde un repositorio Git e inicio de los servicios principales.
*   **Uso**:
    ```bash
    sudo ./vps-bootstrap.sh production https://gitea.tu-dominio.com
    ```

### 4. [`register-runner.sh`](./register-runner.sh)
Descarga, configura e instala `act_runner` como un servicio systemd para habilitar compilaciones de CI/CD autohospedadas.
*   **Caso de uso**: Registrar servidores adicionales para ejecutar pipelines de GitHub Actions o Gitea Actions de forma automática.
*   **Uso**:
    ```bash
    sudo ./register-runner.sh TU_REGISTRATION_TOKEN
    ```

### 5. [`failback.sh`](./failback.sh)
Script operativo para revertir un estado de failover. Mueve el tráfico y los datos de base de datos Postgres/TimescaleDB actualizados del servidor de respaldo (Standby) de vuelta al servidor principal (Primary).
*   **Caso de uso**: Recuperación ante fallos del servidor principal una vez que este vuelve a estar disponible.
*   **Variables clave**:
    *   `DB_CONTAINER`: Nombre del contenedor DB en Docker.
    *   `DB_USER`: Usuario administrador de la base de datos.
    *   `DB_NAME`: Nombre de la base de datos.
*   **Uso**:
    ```bash
    ./failback.sh IP_PRIMARY IP_STANDBY
    ```

### 6. [`deploy.sh`](./deploy.sh)
Autentica con un registro de contenedores privado, realiza pull de las últimas imágenes y levanta la pila de Docker Compose, verificando que la API principal responda con código HTTP 200 en su endpoint de salud.
*   **Caso de uso**: Orquestación de despliegues continuos desde herramientas de CI/CD.
*   **Uso**:
    ```bash
    ./deploy.sh 192.168.1.10 registry.tu-dominio.com
    ```

### 7. [`configure_firewall.sh`](./configure_firewall.sh)
Detecta automáticamente el sistema de firewall activo en el VPS (UFW, Firewalld o iptables) y abre los puertos de red necesarios.
*   **Caso de uso**: Apertura de puertos para el tráfico de la aplicación (HTTP/HTTPS, consola de administración, puertos MQTT con/sin TLS y salida SMTP para correos).
*   **Uso**:
    ```bash
    # Si vienes de Windows, limpia saltos de línea (CRLF) y dale permisos:
    tr -d '\r' < configure_firewall.sh > vps_firewall.sh
    chmod +x vps_firewall.sh
    # Ejecuta como superusuario:
    sudo ./vps_firewall.sh
    ```

