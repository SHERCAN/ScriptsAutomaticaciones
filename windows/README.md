# Scripts de Automatización para Windows

Esta carpeta contiene scripts orientados a entornos Windows utilizando PowerShell (archivos `.ps1`).

## 📂 Contenido de la carpeta

### 1. [`windows-runner-setup.ps1`](./windows-runner-setup.ps1)
Instala de forma desatendida y configura un Actions Runner (para Gitea o GitHub) en Windows de forma interactiva y segura:
*   Descarga la última versión del runner directamente de Gitea o GitHub (con fallback).
*   Registra el runner en el servidor Gitea/GitHub.
*   Instala y arranca el runner como un servicio de Windows con reinicio automático.
*   Realiza limpieza automática de archivos temporales de instalación.
*   **Requisitos**: Ejecutar como Administrador en una consola de PowerShell 5.1 o PowerShell Core.
*   **Uso**:
    ```powershell
    Set-ExecutionPolicy Bypass -Scope Process; .\windows-runner-setup.ps1
    ```

### 2. [`dev-watch.ps1`](./dev-watch.ps1)
Monitorea los archivos fuente en un workspace de Rust y reinicia el servicio especificado inmediatamente después de detectar cambios en el código.
*   **Características**: Instala automáticamente la herramienta `cargo-watch` si no está disponible en la máquina de desarrollo.
*   **Uso**:
    ```powershell
    .\dev-watch.ps1 -Service nombre-de-tu-crate
    ```

### 3. [`windows-s3-minio-setup.ps1`](./windows-s3-minio-setup.ps1)
Instala AWS CLI de forma desatendida y configura las credenciales locales de S3/MinIO para interactuar con buckets u objetos de almacenamiento de forma interactiva y segura.
*   **Requisitos**: Ejecutar como Administrador.
*   **Uso**:
    ```powershell
    Set-ExecutionPolicy Bypass -Scope Process; .\windows-s3-minio-setup.ps1
    ```

### 4. [`windows-rust-wix-setup.ps1`](./windows-rust-wix-setup.ps1)
Instala de forma desatendida el toolchain de Rust (target GNU) y WiX Toolset v4, herramientas esenciales para el desarrollo, compilación y empaquetado de aplicaciones de escritorio en Windows (instaladores `.msi`).
*   **Requisitos**: Ejecutar como Administrador.
*   **Uso**:
    ```powershell
    Set-ExecutionPolicy Bypass -Scope Process; .\windows-rust-wix-setup.ps1
    ```
