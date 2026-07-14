# =============================================================================
# windows-runner-setup.ps1 — Configura Gitea/GitHub Actions Runner en Windows
# =============================================================================
# Requiere: Windows 10/11 o Windows Server 2019+
# Ejecutar como Administrador en una sesión de PowerShell
# =============================================================================

$ErrorActionPreference = "Stop"

# --- CONFIGURACIÓN DE ENTRADAS ---
Write-Host "=== Setup Windows Runner para Gitea/GitHub Actions ===" -ForegroundColor Cyan
$GITEA_URL = Read-Host -Prompt "Ingresa la URL de tu instancia Gitea/GitHub (ej: https://gitea.yourdomain.com)"
$RUNNER_TOKEN = Read-Host -Prompt "Ingresa el token de registro del runner"
$RUNNER_NAME = Read-Host -Prompt "Ingresa un nombre para este runner (ej: windows-builder)"
$RUNNER_LABELS = Read-Host -Prompt "Ingresa las etiquetas para el runner separadas por coma (ej: windows,msi)"

# 1. Instalar Gitea Actions Runner
Write-Host "[1/6] Instalando Actions Runner..." -ForegroundColor Yellow
$runnerDir = "$env:ProgramData\gitea-runner"
New-Item -ItemType Directory -Path $runnerDir -Force | Out-Null
Set-Location $runnerDir

# Descargar última versión del runner de act_runner
$repo = "gitea/act_runner"
$release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
$asset = $release.assets | Where-Object { $_.name -like "*windows-amd64*" }
Write-Host "Descargando act_runner desde $($asset.browser_download_url)..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile "act_runner.exe"

# Configurar e registrar como servicio
Write-Host "Registrando runner en el servidor..."
.\act_runner.exe register `
    --instance "$GITEA_URL" `
    --token "$RUNNER_TOKEN" `
    --name "$RUNNER_NAME" `
    --labels "$RUNNER_LABELS" `
    --no-interactive

# Instalar como servicio de Windows
Write-Host "Instalando servicio de Windows 'gitea-runner'..."
New-Service -Name "gitea-runner" `
    -BinaryPathName "`"$runnerDir\act_runner.exe`" daemon --config `"$runnerDir\.runner`"" `
    -DisplayName "Gitea Actions Runner" `
    -StartupType Automatic

Start-Service -Name "gitea-runner"

# 2. Instalar Rust toolchain (Opcional, útil para desarrollo)
$instalarRust = Read-Host -Prompt "¿Deseas instalar el toolchain de Rust (y/N)?"
if ($instalarRust -eq "y" -or $instalarRust -eq "s") {
    Write-Host "[2/6] Instalando Rust toolchain..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri "https://static.rust-lang.org/rustup/dist/i686-pc-windows-gnu/rustup-init.exe" `
        -OutFile "$env:TEMP\rustup-init.exe"
    & "$env:TEMP\rustup-init.exe" -y --default-host x86_64-pc-windows-gnu
    Remove-Item "$env:TEMP\rustup-init.exe"
    # Agregar target Windows GNU
    & "$env:USERPROFILE\.cargo\bin\rustup.exe" target add x86_64-pc-windows-gnu
} else {
    Write-Host "[2/6] Instalación de Rust omitida." -ForegroundColor Gray
}

# 3. Instalar WiX Toolset v4 (Opcional, para empaquetado de instaladores MSI)
$instalarWix = Read-Host -Prompt "¿Deseas instalar WiX Toolset v4 (y/N)?"
if ($instalarWix -eq "y" -or $instalarWix -eq "s") {
    Write-Host "[3/6] Instalando WiX Toolset..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri "https://github.com/wixtoolset/wix4/releases/latest/download/wix314.exe" `
        -OutFile "$env:TEMP\wix.exe"
    & "$env:TEMP\wix.exe" /install /quiet /norestart
    Remove-Item "$env:TEMP\wix.exe"
} else {
    Write-Host "[3/6] Instalación de WiX omitida." -ForegroundColor Gray
}

# 4. Instalar AWS CLI (para MinIO S3 compat)
$instalarAws = Read-Host -Prompt "¿Deseas instalar AWS CLI (y/N)?"
if ($instalarAws -eq "y" -or $instalarAws -eq "s") {
    Write-Host "[4/6] Instalando AWS CLI..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" `
        -OutFile "$env:TEMP\AWSCLIV2.msi"
    & msiexec.exe /passive /i "$env:TEMP\AWSCLIV2.msi"
    Remove-Item "$env:TEMP\AWSCLIV2.msi"

    # 5. Configurar credenciales MinIO/S3
    Write-Host "[5/6] Configurando credenciales S3/MinIO..." -ForegroundColor Yellow
    $minioEndpoint = Read-Host -Prompt "S3 Endpoint URL (ej: https://minio.yourdomain.com)"
    $minioKey = Read-Host -Prompt "S3 Access Key"
    $minioSecret = Read-Host -Prompt "S3 Secret Key" -AsSecureString
    $minioBstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($minioSecret)
    $minioPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($minioBstr)

    & aws configure set aws_access_key_id "$minioKey"
    & aws configure set aws_secret_access_key "$minioPlain"
    & aws configure set endpoint_url "$minioEndpoint"
    & aws configure set region us-east-1
} else {
    Write-Host "[4/6] [5/6] Instalación y configuración de AWS CLI omitida." -ForegroundColor Gray
}

# 6. Verificar instalación
Write-Host "[6/6] Verificando instalación..." -ForegroundColor Yellow
$checks = @{
    "Gitea Runner" = { Get-Service "gitea-runner" -ErrorAction SilentlyContinue }
    "Rust"         = { Get-Command "rustc.exe" -ErrorAction SilentlyContinue }
    "Cargo"        = { Get-Command "cargo.exe" -ErrorAction SilentlyContinue }
    "AWS CLI"      = { Get-Command "aws.exe" -ErrorAction SilentlyContinue }
}

$allOk = $true
foreach ($check in $checks.Keys) {
    $result = & $checks[$check]
    if ($result) {
        Write-Host "  ✅ ${check}: Instalado/Activo" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  ${check}: No detectado en PATH (puede requerir reiniciar la consola)" -ForegroundColor Yellow
        $allOk = $false
    }
}

Write-Host ""
if ($allOk) {
    Write-Host "=== Setup completado exitosamente ===" -ForegroundColor Cyan
    Write-Host "Runner registrado: $RUNNER_NAME"
} else {
    Write-Host "⚠️ Algunos componentes pueden requerir reiniciar la terminal de PowerShell para ser detectados." -ForegroundColor Yellow
}
