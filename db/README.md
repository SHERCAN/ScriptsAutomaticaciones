# Automatización de Base de Datos (db/)

Esta carpeta contiene scripts orientados a la administración de bases de datos PostgreSQL o TimescaleDB, abarcando flujos de copia de seguridad local/nube y restauración rápida.

## 📂 Contenido de la carpeta

### 1. [`backup-db-rclone.sh`](./backup-db-rclone.sh)
Genera copias de seguridad de una base de datos local y las sube automáticamente a almacenamiento en la nube.
*   **Características**:
    *   Crea dumps sql comprimidos (`.gz`) etiquetados con fecha y hora.
    *   Integra `rclone` para enviar copias remotas a proveedores como Google Drive, OneDrive o AWS S3.
    *   Limpia localmente los archivos antiguos mayores a un número ajustable de días para prevenir problemas de almacenamiento.
*   **Uso**:
    ```bash
    ./backup-db-rclone.sh
    ```

### 2. [`restore-db.sh`](./restore-db.sh)
Restaura de forma rápida y guiada una base de datos desde un archivo `.sql.gz`.
*   **Características**:
    *   Muestra los backups locales disponibles si no se pasa ningún archivo por parámetro.
    *   Pide confirmación expresa en la terminal antes de sobreescribir los datos actuales para mitigar errores accidentales.
*   **Uso**:
    ```bash
    ./restore-db.sh /var/backups/db-backups/mi_backup.sql.gz
    ```
