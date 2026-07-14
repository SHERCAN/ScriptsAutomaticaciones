# Scripts de Automatización para Windows

Esta carpeta contiene scripts orientados a entornos Windows utilizando PowerShell (archivos `.ps1`).

## 📂 Contenido de la carpeta

### 1. [`windows-runner-setup.ps1`](./windows-runner-setup.ps1)
Instala de forma desatendida y configura un Actions Runner (para Gitea o GitHub) en Windows. De manera opcional, descarga e instala las herramientas necesarias para tareas de empaquetado y compilación:
*   Rust Toolchain (con target GNU).
*   WiX Toolset v4 (para compilar instaladores de Windows `.msi`).
*   AWS CLI y configuración de almacenamiento compatible con S3 (como MinIO) para almacenamiento de caché u objetos de build.
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
