# Scripts de Automatización y Operaciones (ScriptsAutomaticaciones)

Este repositorio contiene una colección de scripts sanitizados y listos para producción para automatizar tareas comunes de despliegue, infraestructura, bases de datos y procesamiento de imágenes. 

Todos los scripts han sido limpiados de credenciales específicas, llaves secretas, direcciones IP o dominios personales, exponiendo variables de configuración en la parte superior de cada archivo o mediante parámetros de ejecución.

---

## 📂 Estructura del Repositorio

A continuación se detallan los scripts disponibles agrupados por categoría. Haz clic en el enlace de la carpeta para ver las instrucciones específicas.

### 🐧 [Servidores y Sistemas Linux (linux/)](./linux/)
Scripts de administración de servidores VPS, configuración DNS en la nube, pipelines de despliegue y configuraciones de runners para CI/CD.

*   [**`cloudflare-setup.sh`**](./linux/cloudflare-setup.sh): Automatiza la creación de registros DNS (tipo A) y balanceadores de carga mediante la API de Cloudflare.
*   [**`setup-domains.sh`**](./linux/setup-domains.sh): Asocia subdominios a servicios de contenedores Docker Compose en el panel Dokploy y actualiza la Zona DNS de Cloudflare de forma automática.
*   [**`vps-bootstrap.sh`**](./linux/vps-bootstrap.sh): Configura un nuevo servidor VPS con Docker, UFW, Git, clona el repositorio del proyecto e inicializa el despliegue.
*   [**`register-runner.sh`**](./linux/register-runner.sh): Instala y registra un Actions Runner (Gitea/GitHub) en una máquina Linux, configurando un servicio `systemd`.
*   [**`failback.sh`**](./linux/failback.sh): Script operativo de replicación para retornar la carga de producción de un servidor Standby de vuelta al servidor Primary sin pérdida de datos.
*   [**`deploy.sh`**](./linux/deploy.sh): Ejecuta un despliegue automático de contenedores en Dokploy/Compose y verifica que el API Backend responda saludablemente.

---

### 🪟 [PowerShell para Windows (windows/)](./windows/)
Scripts de Powershell para aprovisionar entornos de compilación de Action Runners en Windows y scripts de soporte al desarrollo en Rust.

*   [**`windows-runner-setup.ps1`**](./windows/windows-runner-setup.ps1): Automatiza la instalación y registro de act_runner en Windows, instalando opcionalmente Rust toolchain, AWS CLI (para MinIO) y WiX Toolset.
*   [**`dev-watch.ps1`**](./windows/dev-watch.ps1): Monitorea los cambios de archivos en un Workspace de Cargo e inicia la recarga en caliente de servicios en Rust de forma ágil.

---

### 🗄️ [Bases de Datos (db/)](./db/)
Automatizaciones para copias de seguridad locales/remotas y recuperación rápida de datos.

*   [**`backup-db-rclone.sh`**](./db/backup-db-rclone.sh): Genera un volcado de PostgreSQL/TimescaleDB, lo comprime, realiza una limpieza de archivos locales antiguos y sube el backup a la nube (como Google Drive) mediante Rclone.
*   [**`restore-db.sh`**](./db/restore-db.sh): Script interactivo y seguro para restaurar una base de datos a partir de archivos comprimidos `.sql.gz`.

---

### 🖼️ [Optimización de Imágenes (images/)](./images/)
Utilidades escritas en NodeJS utilizando Sharp para optimizar el peso y rendimiento de assets en aplicaciones web modernas.

*   [**`convert-to-webp.js`**](./images/convert-to-webp.js): Convierte recursivamente todas las imágenes PNG, JPG y JPEG de un directorio especificado a formato WebP optimizando espacio en disco.
*   [**`optimize-images.js`**](./images/optimize-images.js): Redimensiona las imágenes a resoluciones Full HD y las comprime a formato WebP.

---

## 🚀 Cómo utilizar este repositorio

1.  **Clona el repositorio**:
    ```bash
    git clone https://github.com/SHERCAN/ScriptsAutomaticaciones.git
    cd ScriptsAutomaticaciones
    ```
2.  **Configura las variables**:
    Cada archivo de script posee una sección `CONFIGURACIÓN` en la parte superior. Abre el archivo y rellenalo con tus propios tokens, puertos, nombres de proyecto o endpoints antes de ejecutarlo.
3.  **Ejecuta el script**:
    *   Para scripts Bash: `chmod +x linux/script.sh && ./linux/script.sh`
    *   Para scripts PowerShell (como Administrador): `Set-ExecutionPolicy Bypass -Scope Process; .\windows\script.ps1`
    *   Para scripts NodeJS: `npm install sharp && node images/script.js`
