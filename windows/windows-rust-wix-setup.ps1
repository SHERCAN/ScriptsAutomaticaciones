# =============================================================================
# windows-rust-wix-setup.ps1 — Instala Rust Toolchain (GNU) y WiX Toolset v4
# =============================================================================
# Requiere: Windows 10/11 o Windows Server 2019+
# Ejecutar como Administrador en una sesión de PowerShell
# =============================================================================

$ErrorActionPreference = "Stop"
$scriptFailed = $false

try {
    Write-Host "=== Instalación de Herramientas de Compilación: Rust y WiX ===" -ForegroundColor Cyan

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

    # --- INSTALACIÓN DE RUST TOOLCHAIN ---
    Write-Host "`n[1/2] Instalando Rust toolchain (GNU)..." -ForegroundColor Yellow
    $rustupUrl = "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-gnu/rustup-init.exe"
    $tempRustup = Join-Path $env:TEMP "rustup-init_$((Get-Date).Ticks).exe"
    
    Write-Host "Descargando rustup-init desde $rustupUrl..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $rustupUrl -OutFile $tempRustup

    Write-Host "Ejecutando instalación desatendida de Rust..." -ForegroundColor Gray
    $proc = Start-Process $tempRustup -ArgumentList "-y --default-host x86_64-pc-windows-gnu" -Wait -NoNewWindow -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "La instalación de Rust falló con código de salida: $($proc.ExitCode)"
    }
    
    # Limpieza de archivo temporal
    if (Test-Path $tempRustup) {
        Remove-Item -Path $tempRustup -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Rust toolchain instalado correctamente." -ForegroundColor Green

    # --- INSTALACIÓN DE WIX TOOLSET V4 ---
    Write-Host "`n[2/2] Instalando WiX Toolset v4..." -ForegroundColor Yellow
    $wixUrl = "https://github.com/wixtoolset/wix4/releases/latest/download/wix314.exe" # Nota: WiX v3/v4 instalador bootstrap
    $tempWix = Join-Path $env:TEMP "wix_$((Get-Date).Ticks).exe"

    Write-Host "Descargando instalador de WiX desde $wixUrl..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $wixUrl -OutFile $tempWix

    Write-Host "Instalando WiX de forma silenciosa..." -ForegroundColor Gray
    $proc = Start-Process $tempWix -ArgumentList "/install /quiet /norestart" -Wait -NoNewWindow -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "La instalación de WiX falló con código de salida: $($proc.ExitCode)"
    }

    # Limpieza de archivo temporal
    if (Test-Path $tempWix) {
        Remove-Item -Path $tempWix -Force -ErrorAction SilentlyContinue
    }
    Write-Host "WiX Toolset instalado correctamente." -ForegroundColor Green

    Write-Host "`n=== Instalación completada exitosamente ===" -ForegroundColor Cyan
    Write-Host "⚠️  Nota: Puede ser necesario reiniciar la consola de PowerShell para detectar 'rustc', 'cargo' o 'wix'." -ForegroundColor Yellow
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
