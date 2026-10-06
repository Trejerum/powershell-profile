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

# 1. Configurar vinculación dual de $PROFILE (PS 5.1 y PS 7) mediante Unión NTFS (Junction)
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$docsDir   = [Environment]::GetFolderPath('MyDocuments')

$targetProfileDirs = @(
    (Join-Path $docsDir "WindowsPowerShell"),
    (Join-Path $docsDir "PowerShell")
)

Write-Host "● Comprobando vinculación dual de `$PROFILE (PS 5.1 y PS 7) con dotfiles..." -ForegroundColor Cyan

foreach ($targetDir in $targetProfileDirs) {
    $dirName = Split-Path -Leaf $targetDir
    if ($scriptDir.TrimEnd('\', '/') -ieq $targetDir.TrimEnd('\', '/')) {
        continue
    }

    $item = Get-Item -LiteralPath $targetDir -ErrorAction SilentlyContinue
    $isJunction = $item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)

    if ($isJunction) {
        Write-Host "✓ $dirName ya está vinculado a dotfiles mediante Unión NTFS." -ForegroundColor Green
    } else {
        if (Test-Path -LiteralPath $targetDir) {
            $backupDir = "${targetDir}_bak"
            Move-Item -LiteralPath $targetDir -Destination $backupDir -Force
            Write-Host "  (!) Carpeta previa '$dirName' respaldada en '$backupDir'." -ForegroundColor Yellow
        }
        cmd /c mklink /J "$targetDir" "$scriptDir" | Out-Null
        Write-Host "✓ Unión NTFS creada con éxito: '$dirName' -> '$scriptDir'." -ForegroundColor Green
    }
}

# 2. Configurar soporte TLS 1.2 para conexiones seguras con PowerShell Gallery
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 3. Configurar NuGet PackageProvider si no está instalado
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

# 4. Instalación de módulos PowerShell necesarios
$requiredModules = @(
    @{ Name = "posh-git";   Description = "Prompt con estado de Git y autocompletado avanzado"; MinVersion = "0.7.0" }
    @{ Name = "PSReadLine"; Description = "Autocompletado predictivo inteligente (versión 2.2+)"; MinVersion = "2.2.6" }
)

$localModDir = Join-Path $scriptDir "Modules"
if (-not (Test-Path -LiteralPath $localModDir)) {
    New-Item -ItemType Directory -Path $localModDir -Force | Out-Null
}

foreach ($m in $requiredModules) {
    $modName = $m.Name
    $modDesc = $m.Description
    $minVer  = if ($m.MinVersion) { [Version]$m.MinVersion } else { $null }

    $installed = Get-Module -ListAvailable -Name $modName | Sort-Object Version -Descending | Select-Object -First 1
    if ($installed -and (-not $minVer -or $installed.Version -ge $minVer) -and ($installed.Path -match [regex]::Escape($localModDir))) {
        Write-Host "✓ Módulo '$modName' ($($installed.Version)) ($modDesc) ya está instalado en dotfiles." -ForegroundColor Green
    }
    else {
        $actionText = if ($installed) { "Actualizando" } else { "Instalando" }
        Write-Host "● $actionText módulo '$modName' ($modDesc) en disco local..." -ForegroundColor Cyan
        try {
            Save-Module -Name $modName -Path $localModDir -Force -ErrorAction Stop
            Write-Host "✓ Módulo '$modName' guardado en '$localModDir' con éxito." -ForegroundColor Green
        }
        catch {
            Write-Host "  (!) Save-Module advirtió ($($_)), intentando Install-Module..." -ForegroundColor Yellow
            Install-Module -Name $modName -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
        }
    }
}

# 5. Inicializar configuración de conexiones SQL locales
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

# 5b. Configurar configuraciones compartidas de herramientas (Ripgrep y Lazygit)
$lgTargetDir = Join-Path $env:APPDATA "lazygit"
$lgSource = Join-Path $scriptDir "config\lazygit.yml"
$lgTarget = Join-Path $lgTargetDir "config.yml"
if (Test-Path -LiteralPath $lgSource) {
    if (-not (Test-Path -LiteralPath $lgTargetDir)) {
        [void](New-Item -ItemType Directory -Path $lgTargetDir -Force)
    }
    if (-not (Test-Path -LiteralPath $lgTarget)) {
        Copy-Item -LiteralPath $lgSource -Destination $lgTarget -Force
        Write-Host "✓ Inicializado archivo de configuración de Lazygit en AppData." -ForegroundColor Green
    }
}

# 6. Comprobación de herramientas externas recomendadas
Write-Host "`n--- Comprobando herramientas recomendadas del sistema ---" -ForegroundColor DarkGray

$cliTools = @(
    @{ Cmd = "nvim"; Name = "Neovim"; Winget = "Neovim.Neovim" }
    @{ Cmd = "rg";   Name = "Ripgrep"; Winget = "BurntSushi.ripgrep.MSVC" }
    @{ Cmd = "lg";   Name = "Lazygit"; Winget = "jesseduffield.lazygit" }
    @{ Cmd = "fzf";  Name = "FZF (Fuzzy Finder)"; Winget = "junegunn.fzf" }
    @{ Cmd = "fd";   Name = "fd (File Finder)"; Winget = "sharkdp.fd" }
    @{ Cmd = "bat";  Name = "bat (Cat con syntax highlight)"; Winget = "sharkdp.bat" }
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
