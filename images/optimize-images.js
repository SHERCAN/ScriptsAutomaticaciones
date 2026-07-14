import sharp from 'sharp';
import fs from 'fs/promises';
import path from 'path';

// --- CONFIGURACIÓN ---
const PUBLIC_DIR = process.argv[2] || 'public';
const OPTIMIZED_DIR = process.argv[3] || 'public/optimized';
const MAX_WIDTH = 1920; // Ancho máximo
const QUALITY = 80;    // Calidad del WebP

async function optimizeImages() {
  try {
    // Crear directorio optimizado si no existe
    await fs.mkdir(OPTIMIZED_DIR, { recursive: true });

    // Obtener todos los archivos de imágenes
    const files = await fs.readdir(PUBLIC_DIR);
    const imageFiles = files.filter(file => 
      /\.(jpg|jpeg|png|webp)$/i.test(file)
    );

    if (imageFiles.length === 0) {
      console.log(`No se encontraron imágenes en el directorio: ${PUBLIC_DIR}`);
      return;
    }

    for (const file of imageFiles) {
      const inputPath = path.join(PUBLIC_DIR, file);
      const outputPath = path.join(OPTIMIZED_DIR, file);

      // Optimizar imagen
      await sharp(inputPath)
        .resize(MAX_WIDTH, null, { // máximo ancho manteniendo proporción
          withoutEnlargement: true,
          fit: 'inside'
        })
        .webp({ quality: QUALITY }) // convertir a WebP con calidad especificada
        .toFile(outputPath.replace(/\.[^.]+$/, '.webp'));

      console.log(`✅ Optimized and converted to WebP: ${file}`);
    }
    console.log(`✨ Proceso completado. Imágenes guardadas en: ${OPTIMIZED_DIR}`);
  } catch (error) {
    console.error('Error optimizing images:', error);
  }
}

optimizeImages();
