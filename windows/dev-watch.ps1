#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Ejecuta un servicio de Rust con recarga en caliente (cargo-watch) dentro de un Workspace.
.DESCRIPTION
    Este script automatiza el inicio de cargo-watch para un servicio específico del workspace.
    Si cargo-watch no está instalado, procede a instalarlo automáticamente.
.PARAMETER Service
    Nombre del servicio de Rust (crate) que se desea ejecutar en modo watch.
.EXAMPLE
    .\dev-watch.ps1 -Service backend-api
    .\dev-watch.ps1 -Service your-rust-service
#>

param(
    [Parameter(Mandatory=$true, HelpMessage="Nombre del servicio en el workspace de Cargo que deseas iniciar")]
    [string]$Service
)

$ErrorActionPreference = 'Stop'

# Verificar si cargo-watch está instalado en el sistema
if (-not (Get-Command 'cargo-watch' -ErrorAction SilentlyContinue)) {
    Write-Host "cargo-watch no detectado. Instalando automáticamente..." -ForegroundColor Yellow
    cargo install cargo-watch
}

Write-Host "Iniciando servicio '$Service' con recarga en caliente (hot-reload)..." -ForegroundColor Green
cargo watch -x "run -p $Service"
