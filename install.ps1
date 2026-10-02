# ==============================================================================
# INSTALADOR Y APROVISIONAMIENTO DEL PERFIL DE POWERSHELL
# ==============================================================================
# Ejecuta este script en un equipo nuevo tras clonar el repositorio:
#   .\install.ps1
# ==============================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  Instalación y Configuración del Entorno PowerShell" -ForegroundColor Cyan
Write-Host "==========================================================`n" -ForegroundColor Cyan

# 1. Configurar soporte TLS 1.2 para conexiones seguras con PowerShell Gallery
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 2. Configurar NuGet PackageProvider si no está instalado
try {
    $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    if (-not $nuget -or $nuget.Version -lt [Version]"2.8.5.201") {
        Write-Host "● Instalando/actualizando proveedor NuGet..." -ForegroundColor Cyan
        [void](Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser)
    }
}
catch {
    Write-Warning "No se pudo actualizar NuGet automáticamente: $_"
}

# 3. Instalación de módulos PowerShell necesarios
$requiredModules = @(
    @{ Name = "posh-git"; Description = "Prompt con estado de Git y autocompletado avanzado" }
)

foreach ($m in $requiredModules) {
    $modName = $m.Name
    $modDesc = $m.Description

    if (Get-Module -ListAvailable -Name $modName) {
        Write-Host "✓ Módulo '$modName' ($modDesc) ya está instalado." -ForegroundColor Green
    }
    else {
        Write-Host "● Instalando módulo '$modName' ($modDesc)..." -ForegroundColor Cyan
        try {
            Install-Module -Name $modName -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
            Write-Host "✓ Módulo '$modName' instalado con éxito." -ForegroundColor Green
        }
        catch {
            Write-Error "Fallo al instalar '$modName': $_"
        }
    }
}

# 4. Inicializar configuración de conexiones SQL locales
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$sqlCfg = Join-Path $scriptDir "sql-connections.json"
$sqlExample = Join-Path $scriptDir "sql-connections.example.json"

if (-not (Test-Path -LiteralPath $sqlCfg) -and (Test-Path -LiteralPath $sqlExample)) {
    Copy-Item -LiteralPath $sqlExample -Destination $sqlCfg
    Write-Host "✓ Creado 'sql-connections.json' desde la plantilla de ejemplo." -ForegroundColor Green
    Write-Host "  (!) Configura tus instancias y credenciales en '$sqlCfg'." -ForegroundColor Yellow
}
elseif (Test-Path -LiteralPath $sqlCfg) {
    Write-Host "✓ 'sql-connections.json' ya existe en este equipo." -ForegroundColor Green
}

# 5. Comprobación de herramientas externas recomendadas
Write-Host "`n--- Comprobando herramientas recomendadas del sistema ---" -ForegroundColor DarkGray

$cliTools = @(
    @{ Cmd = "nvim"; Name = "Neovim"; Winget = "Neovim.Neovim" }
    @{ Cmd = "rg";   Name = "Ripgrep"; Winget = "BurntSushi.ripgrep.MSVC" }
    @{ Cmd = "lg";   Name = "Lazygit"; Winget = "jesseduffield.lazygit" }
    @{ Cmd = "7z";   Name = "7-Zip";   Winget = "7zip.7zip" }
)

$missingTools = @()
foreach ($tool in $cliTools) {
    $cmd = Get-Command -Name $tool.Cmd -CommandType Application, Alias -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "✓ $($tool.Name) encontrado en: $($cmd.Source)" -ForegroundColor Green
    }
    else {
        Write-Host "○ $($tool.Name) no encontrado en PATH (opcional)" -ForegroundColor DarkGray
        $missingTools += $tool.Winget
    }
}

if ($missingTools.Count -gt 0) {
    Write-Host "`nTip: Puedes instalar las herramientas faltantes con winget:" -ForegroundColor DarkCyan
    Write-Host "  winget install $($missingTools -join ' ')`n" -ForegroundColor DarkYellow
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  ¡Instalación completada con éxito!" -ForegroundColor Green
Write-Host "  Para activar tu perfil ahora, ejecuta: . `$PROFILE" -ForegroundColor Cyan
Write-Host "==========================================================`n" -ForegroundColor Green
