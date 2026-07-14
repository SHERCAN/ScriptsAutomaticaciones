import sharp from 'sharp';
import { fileURLToPath } from 'url';
import { dirname, join, extname, basename } from 'path';
import { readdir, stat } from 'fs/promises';
import { existsSync, statSync } from 'fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// --- CONFIGURACIÓN ---
// Directorio de entrada: toma el argumento pasado por terminal o busca 'public' por defecto
const inputDir = process.argv[2] ? join(process.cwd(), process.argv[2]) : join(__dirname, 'public');
const quality = 80; // Calidad de conversión (0-100)

// Función para convertir una imagen a WebP
async function convertToWebP(inputPath) {
    const extension = extname(inputPath);
    if (!['.jpg', '.jpeg', '.png'].includes(extension.toLowerCase())) {
        return;
    }

    const outputPath = inputPath.replace(extension, '.webp');

    try {
        // Si el archivo WebP ya existe, se omite
        if (existsSync(outputPath)) {
            console.log(`Skipping ${basename(inputPath)} - WebP version already exists`);
            return;
        }

        await sharp(inputPath)
            .webp({ quality: quality })
            .toFile(outputPath);

        console.log(`✅ Converted ${basename(inputPath)} to WebP`);

        // Obtener ahorros de tamaño
        const originalSize = statSync(inputPath).size;
        const webpSize = statSync(outputPath).size;
        const savings = ((originalSize - webpSize) / originalSize * 100).toFixed(2);

        console.log(`   Original size: ${(originalSize / 1024).toFixed(2)}KB`);
        console.log(`   WebP size: ${(webpSize / 1024).toFixed(2)}KB`);
        console.log(`   Saved: ${savings}%`);
    } catch (error) {
        console.error(`❌ Error converting ${basename(inputPath)}:`, error);
    }
}

// Función para procesar un directorio recursivamente
async function processDirectory(dirPath) {
    if (!existsSync(dirPath)) {
        console.error(`❌ Error: El directorio no existe: ${dirPath}`);
        process.exit(1);
    }
    const items = await readdir(dirPath);

    for (const item of items) {
        const fullPath = join(dirPath, item);
        const stats = await stat(fullPath);

        if (stats.isDirectory()) {
            await processDirectory(fullPath);
        } else {
            await convertToWebP(fullPath);
        }
    }
}

// Ejecutar la conversión
console.log(`🔄 Starting image conversion to WebP in: ${inputDir}`);
processDirectory(inputDir)
    .then(() => console.log('✨ Conversion complete!'))
    .catch(console.error);
