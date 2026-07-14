# Optimización y Procesamiento de Imágenes (images/)

Esta carpeta contiene scripts escritos en NodeJS para optimizar y convertir imágenes de manera recursiva utilizando la librería de alto rendimiento `sharp`.

## ⚙️ Requisitos Previos

Antes de ejecutar los scripts, asegúrate de tener instalado NodeJS y las dependencias del proyecto:

```bash
# Inicializa el proyecto npm si no existe
npm init -y

# Instala sharp
npm install sharp
```

---

## 📂 Contenido de la carpeta

### 1. [`convert-to-webp.js`](./convert-to-webp.js)
Busca todas las imágenes con extensiones `.jpg`, `.jpeg`, y `.png` dentro del directorio especificado (y todos sus subdirectorios) y las convierte recursivamente al formato WebP.
*   **Características**:
    *   Omite archivos que ya cuentan con una versión WebP para ahorrar recursos de CPU.
    *   Muestra en consola estadísticas de compresión del tamaño de archivo original frente al WebP indicando el porcentaje de ahorro.
*   **Uso**:
    ```bash
    # Procesa la carpeta 'public' por defecto
    node convert-to-webp.js
    
    # Procesa una carpeta específica
    node convert-to-webp.js ruta/a/tus/imagenes
    ```

### 2. [`optimize-images.js`](./optimize-images.js)
Optimiza masivamente una carpeta de imágenes, redimensionando su ancho máximo a 1920 píxeles (proporcionalmente, sin deformar) y guardándolas en un directorio optimizado separado en formato WebP con calidad 80%.
*   **Uso**:
    ```bash
    # Procesa 'public' y guarda en 'public/optimized'
    node optimize-images.js
    
    # Procesa carpeta de origen personalizada y carpeta destino personalizada
    node optimize-images.js carpeta_entrada carpeta_salida
    ```
