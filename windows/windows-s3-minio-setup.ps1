# =============================================================================
# windows-s3-minio-setup.ps1 — Instala AWS CLI y configura credenciales S3/MinIO
# =============================================================================
# Requiere: Windows 10/11 o Windows Server 2019+
# Ejecutar como Administrador en una sesión de PowerShell
# =============================================================================

$ErrorActionPreference = "Stop"
$scriptFailed = $false

try {
    Write-Host "=== Instalación de AWS CLI y Configuración de S3/MinIO ===" -ForegroundColor Cyan

    # Verificar Privilegios de Administrador y auto-elevación
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "No se detectaron privilegios de Administrador. Solicitando elevación (UAC)..." -ForegroundColor Yellow
        try {
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction Stop
        }
        catch {
            throw "La elevación fue rechazada o falló. Por favor, ejecuta la terminal de PowerShell como Administrador e inténtalo de nuevo."
        }
        Exit
    }

    # --- DESCARGA E INSTALACIÓN DE AWS CLI ---
    Write-Host "`n[1/2] Instalando AWS CLI..." -ForegroundColor Yellow
    $msiUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
    $tempMsi = Join-Path $env:TEMP "AWSCLIV2_$((Get-Date).Ticks).msi"
    
    Write-Host "Descargando AWS CLI desde $msiUrl..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $msiUrl -OutFile $tempMsi
    
    Write-Host "Ejecutando instalador MSI (silencioso)..." -ForegroundColor Gray
    $proc = Start-Process msiexec.exe -ArgumentList "/passive /i `"$tempMsi`"" -Wait -NoNewWindow -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "La instalación de AWS CLI falló con código de salida: $($proc.ExitCode)"
    }
    
    # Limpieza de archivo temporal
    if (Test-Path $tempMsi) {
        Remove-Item -Path $tempMsi -Force -ErrorAction SilentlyContinue
    }
    Write-Host "AWS CLI instalado correctamente." -ForegroundColor Green

    # Actualizar la variable de entorno PATH de la sesión actual
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # --- CONFIGURACIÓN DE CREDENCIALES ---
    Write-Host "`n[2/2] Configurando credenciales S3/MinIO..." -ForegroundColor Yellow
    $minioEndpoint = Read-Host -Prompt "S3 Endpoint URL (ej: https://minio.yourdomain.com)"
    $minioKey = Read-Host -Prompt "S3 Access Key"
    $minioSecret = Read-Host -Prompt "S3 Secret Key" -AsSecureString
    $minioBstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($minioSecret)
    $minioPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($minioBstr)

    # Validar que AWS CLI se pueda ejecutar en esta sesión
    if (-not (Get-Command "aws.exe" -ErrorAction SilentlyContinue)) {
        Write-Host "⚠️  aws.exe no se detectó en el PATH de la sesión actual." -ForegroundColor Yellow
        Write-Host "Intentando buscar en la ruta de instalación por defecto de AWS CLI..." -ForegroundColor Gray
        $defaultAwsPath = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
        if (Test-Path $defaultAwsPath) {
            function aws { & $defaultAwsPath $args }
        } else {
            throw "No se pudo encontrar aws.exe después de la instalación. Por favor, reinicia la terminal e intenta configurar manualmente."
        }
    }

    aws configure set aws_access_key_id "$minioKey"
    aws configure set aws_secret_access_key "$minioPlain"
    aws configure set endpoint_url "$minioEndpoint"
    aws configure set region us-east-1

    Write-Host "`n✅ Configuración de S3/MinIO completada correctamente." -ForegroundColor Green
}
catch {
    Write-Host "`n[ERROR] Ocurrió un error en la ejecución del script:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    $scriptFailed = $true
}
finally {
    Write-Host ""
    Read-Host -Prompt "Presiona Enter para cerrar..."
    if ($scriptFailed) {
        Exit 1
    }
}
