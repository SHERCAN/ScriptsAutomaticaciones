# =============================================================================
# windows-runner-setup.ps1 — Configura Gitea/GitHub Actions Runner en Windows
# =============================================================================
# Requiere: Windows 10/11 o Windows Server 2019+
# Ejecutar como Administrador en una sesión de PowerShell
# =============================================================================

$ErrorActionPreference = "Stop"
$scriptFailed = $false

try {
    Write-Host "=== Setup Windows Runner para Gitea/GitHub Actions ===" -ForegroundColor Cyan

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

    # Verificar si services.msc (consola MMC) está abierta
    if (Get-Process -Name mmc -ErrorAction SilentlyContinue) {
        Write-Host "⚠️  Se detectó la consola de Servicios de Windows (services.msc) abierta." -ForegroundColor Yellow
        Write-Host "Por favor, ciérrala antes de continuar para evitar que bloquee la reinstalación del servicio." -ForegroundColor Yellow
        Read-Host -Prompt "Presiona Enter cuando hayas cerrado la consola para continuar..."
    }

    # --- CONFIGURACIÓN DE ENTRADAS ---
    $GITEA_URL = Read-Host -Prompt "Ingresa la URL de tu instancia Gitea/GitHub (ej: https://gitea.yourdomain.com)"
    $RUNNER_TOKEN = Read-Host -Prompt "Ingresa el token de registro del runner"
    $RUNNER_NAME = Read-Host -Prompt "Ingresa un nombre para este runner (ej: windows-builder)"
    $RUNNER_LABELS = Read-Host -Prompt "Ingresa las etiquetas para el runner separadas por coma (ej: windows,msi)"

    Write-Host "`n[1/4] Preparando entorno..." -ForegroundColor Yellow
    $runnerDir = "$env:ProgramData\gitea-runner"
    if (-not (Test-Path $runnerDir)) {
        New-Item -ItemType Directory -Path $runnerDir -Force | Out-Null
    }

    # --- DESCARGA DE ACT_RUNNER ---
    Write-Host "`n[2/4] Buscando última versión del runner..." -ForegroundColor Yellow
    $downloadUrl = $null
    
    # 1. Intentar desde Gitea.com API
    try {
        $apiUri = "https://gitea.com/api/v1/repos/gitea/runner/releases/latest"
        Write-Host "Obteniendo información de descarga desde Gitea.com..." -ForegroundColor Gray
        $release = Invoke-RestMethod -Uri $apiUri
        $asset = $release.assets | Where-Object { $_.name -like "*windows-amd64.exe" }
        if ($asset) {
            $downloadUrl = $asset.browser_download_url
        }
    }
    catch {
        Write-Host "No se pudo obtener información desde Gitea.com. Reintentando con GitHub..." -ForegroundColor Yellow
    }

    # 2. Intentar desde GitHub API (fallback)
    if (-not $downloadUrl) {
        try {
            $apiUri = "https://api.github.com/repos/gitea/act_runner/releases/latest"
            Write-Host "Obteniendo información de descarga desde GitHub..." -ForegroundColor Gray
            $release = Invoke-RestMethod -Uri $apiUri
            $asset = $release.assets | Where-Object { $_.name -like "*windows-amd64*" -and $_.name -like "*.exe" }
            if ($asset) {
                $downloadUrl = $asset.browser_download_url
            }
        }
        catch {
            throw "No se pudo obtener la información de releases de act_runner de ninguna fuente: $_"
        }
    }

    if (-not $downloadUrl) {
        throw "No se pudo encontrar un enlace de descarga válido para el runner de Windows AMD64."
    }

    $tempExe = Join-Path $env:TEMP "act_runner_temp_$((Get-Date).Ticks).exe"
    Write-Host "Descargando runner desde: $downloadUrl" -ForegroundColor Gray
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempExe
    Write-Host "Descarga finalizada temporalmente en: $tempExe" -ForegroundColor Green

    # 1. Terminar cualquier proceso act_runner.exe o GiteaRunner.exe huérfano para evitar bloqueos de archivo
    $orphanProcesses = @("act_runner", "GiteaRunner")
    foreach ($procName in $orphanProcesses) {
        if (Get-Process -Name $procName -ErrorAction SilentlyContinue) {
            Write-Host "Se encontraron procesos '$procName' activos. Finalizándolos..." -ForegroundColor Yellow
            Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    }

    # 2. Detener y eliminar servicios previos de Gitea Runner
    $oldServiceNames = @("gitea-runner", "GiteaRunner")
    foreach ($svcName in $oldServiceNames) {
        if (Get-Service -Name $svcName -ErrorAction SilentlyContinue) {
            Write-Host "El servicio '$svcName' ya existe. Deteniendo y eliminando..." -ForegroundColor Yellow
            Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            
            # Asegurar que se detenga el binario respectivo del servicio
            $executableName = [System.IO.Path]::GetFileNameWithoutExtension($svcName)
            Stop-Process -Name $executableName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1

            sc.exe delete $svcName | Out-Null
            
            # Esperar a que Windows elimine el servicio por completo para evitar conflictos
            Write-Host "Esperando a que el sistema elimine el servicio '$svcName'..." -ForegroundColor Gray
            $timeout = 10
            while ((Get-Service -Name $svcName -ErrorAction SilentlyContinue) -and ($timeout -gt 0)) {
                if ($timeout -eq 5) {
                    Write-Host "⚠️ La eliminación de '$svcName' está tomando más tiempo. Asegúrate de cerrar la consola de Servicios (services.msc) y Task Manager si están abiertos." -ForegroundColor Yellow
                }
                Start-Sleep -Seconds 1
                $timeout--
            }
            Start-Sleep -Seconds 1
        }
    }

    # Copiar ejecutable al directorio final
    Write-Host "Copiando binario a la ubicación final..." -ForegroundColor Gray
    Copy-Item -Path $tempExe -Destination "$runnerDir\act_runner.exe" -Force

    # Generar archivo de configuración config.yaml para especificar la ruta absoluta de .runner
    Write-Host "Generando archivo de configuración config.yaml..." -ForegroundColor Gray
    $configFileContent = @"
runner:
  file: $runnerDir\.runner
"@
    Set-Content -Path "$runnerDir\config.yaml" -Value $configFileContent -Force

    # --- REGISTRO DEL RUNNER ---
    Write-Host "`n[3/4] Registrando runner con la instancia..." -ForegroundColor Yellow
    
    # Cambiar de directorio para que el archivo de configuración .runner se cree allí
    $originalDir = Get-Location
    Set-Location $runnerDir

    # Ejecutar registro con control manual de errores
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    & .\act_runner.exe register `
        --config "$runnerDir\config.yaml" `
        --instance "$GITEA_URL" `
        --token "$RUNNER_TOKEN" `
        --name "$RUNNER_NAME" `
        --labels "$RUNNER_LABELS" `
        --no-interactive

    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldEap

    if ($exitCode -ne 0) {
        Set-Location $originalDir
        throw "El registro del runner falló con código de salida $exitCode. Revisa los mensajes anteriores para más detalles."
    }

    if (-not (Test-Path ".runner")) {
        Set-Location $originalDir
        throw "El archivo de configuración '.runner' no fue creado. Registro fallido."
    }

    # Volver al directorio original
    Set-Location $originalDir

    # --- INSTALACIÓN Y ARRANQUE COMO SERVICIO CON WINSW ---
    Write-Host "`n[4/4] Instalando y arrancando servicio de Windows..." -ForegroundColor Yellow
    $winswUrl = "https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe"
    $winswExe = "$runnerDir\gitea-runner-service.exe"
    $winswXml = "$runnerDir\gitea-runner-service.xml"

    # Descargar WinSW si no existe para ahorrar ancho de banda, o forzar descarga si es necesario
    Write-Host "Descargando WinSW Service Wrapper desde $winswUrl..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $winswUrl -OutFile $winswExe

    # Generar el archivo XML para configurar WinSW
    Write-Host "Generando archivo XML de configuración para el servicio..." -ForegroundColor Gray
    $xmlContent = @"
<service>
  <id>gitea-runner</id>
  <name>Gitea Actions Runner</name>
  <description>Runner de Gitea Actions (WinSW Wrapper)</description>
  <executable>$runnerDir\act_runner.exe</executable>
  <arguments>daemon --config "$runnerDir\config.yaml"</arguments>
  <workingdirectory>$runnerDir</workingdirectory>
  <startmode>Automatic</startmode>
  <stoptimeout>15000</stoptimeout>
  <log mode="roll-by-size">
    <sizeThreshold>10240</sizeThreshold>
    <keepFiles>10</keepFiles>
  </log>
  <onfailure action="restart" delay="10 sec"/>
  <onfailure action="restart" delay="30 sec"/>
</service>
"@
    Set-Content -Path $winswXml -Value $xmlContent -Force

    # Registrar el servicio de Windows usando WinSW
    Write-Host "Registrando el servicio de Windows con WinSW..." -ForegroundColor Gray
    $installOutput = & $winswExe install 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Salida del comando de instalación de WinSW:" -ForegroundColor Red
        $installOutput | Out-String | Write-Host
        throw "El instalador del servicio de WinSW falló con código de salida $LASTEXITCODE. Asegúrate de haber cerrado la ventana de Servicios (services.msc) y de que ningún proceso bloquee el servicio."
    }

    Write-Host "Iniciando servicio 'gitea-runner'..." -ForegroundColor Gray
    Start-Service -Name "gitea-runner"

    # Verificar que el servicio esté corriendo
    $service = Get-Service -Name "gitea-runner"
    if ($service.Status -ne "Running") {
        throw "El servicio se creó pero se encuentra en estado: $($service.Status)"
    }
    Write-Host "  ✅ Servicio 'gitea-runner': Instalado y Activo con éxito (WinSW Wrapper)" -ForegroundColor Green

    # Limpieza de archivos temporales
    if (Test-Path $tempExe) {
        Write-Host "Limpiando archivo temporal de instalación..." -ForegroundColor Gray
        Remove-Item -Path $tempExe -Force -ErrorAction SilentlyContinue
    }

    Write-Host "`n=== Setup completado exitosamente ===" -ForegroundColor Cyan
    Write-Host "Runner registrado: $RUNNER_NAME"
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
