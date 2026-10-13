# ==============================================================================
# INSTALADOR Y APROVISIONAMIENTO DEL ENTORNO DE DESARROLLO (POWERSHELL & DOTFILES)
# ==============================================================================
# Ejecuta este script en un equipo nuevo tras clonar el repositorio:
#   .\install.ps1               # Instalación interactiva guiada
#   .\install.ps1 -All          # Instalación desatendida completa (Core + Nvim + Utils + Fuentes)
#   .\install.ps1 -Core         # Instalación desatendida solo de herramientas esenciales
#   .\install.ps1 -NoTools      # Solo vinculación de perfil y módulos (omite winget)
# ==============================================================================

[CmdletBinding()]
param(
    [switch]$All,
    [switch]$Core,
    [switch]$NoTools,
    [switch]$SyncNvim,
    [switch]$Force
)

$ErrorActionPreference = "Continue"

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  Instalación y Configuración del Entorno PowerShell" -ForegroundColor Cyan
Write-Host "==========================================================`n" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 0. FUNCIONES AUXILIARES DE ENTORNO Y WINGET
# ------------------------------------------------------------------------------

function Update-SessionPath {
    <#
    .SYNOPSIS
        Refresca la variable PATH de la sesión actual leyendo del Registro (Machine + User).
    #>
    try {
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:PATH    = "$userPath;$machinePath"
    } catch {
        Write-Warning "No se pudo actualizar `$env:PATH dinámicamente: $_"
    }
}

function Test-CommandAvailable ([string]$CmdName) {
    if (Get-Command -Name $CmdName -CommandType Application, Alias -ErrorAction SilentlyContinue) {
        return $true
    }
    Update-SessionPath
    return [bool](Get-Command -Name $CmdName -CommandType Application, Alias -ErrorAction SilentlyContinue)
}

function Install-WingetPackage ([string]$PackageId, [string]$DisplayName, [string]$CheckCmd = $null) {
    if ($CheckCmd -and (Test-CommandAvailable $CheckCmd)) {
        Write-Host "  [OK] $DisplayName ya instalado (encontrado '$CheckCmd')." -ForegroundColor Green
        return $true
    }

    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
        Write-Warning "winget no está disponible en este equipo. No se puede instalar '$DisplayName'."
        return $false
    }

    Write-Host "  [>>] Instalando $DisplayName ($PackageId) mediante winget..." -ForegroundColor Cyan
    try {
        $proc = Start-Process -FilePath "winget" -ArgumentList "install", $PackageId, "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity" -NoNewWindow -Wait -PassThru
        Update-SessionPath
        # Códigos de salida: 0 = éxito, -1978335189 (0x8A15002B) = ya instalado
        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq -1978335189) {
            Write-Host "  [OK] $DisplayName preparado correctamente." -ForegroundColor Green
            return $true
        } else {
            Write-Warning "winget finalizó con código $($proc.ExitCode) al procesar '$DisplayName'."
            return $false
        }
    } catch {
        Write-Warning "Excepción al invocar winget para '$DisplayName': $_"
        return $false
    }
}

# ------------------------------------------------------------------------------
# 1. VINCULACIÓN DUAL DE $PROFILE (PS 5.1 y PS 7) MEDIANTE UNIONES NTFS (JUNCTIONS)
# ------------------------------------------------------------------------------
Write-Host "1. Configurando vinculación dual de `$PROFILE..." -ForegroundColor DarkCyan

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$docsDir   = [Environment]::GetFolderPath('MyDocuments')

$targetProfileDirs = @(
    (Join-Path $docsDir "WindowsPowerShell"),
    (Join-Path $docsDir "PowerShell")
)

foreach ($targetDir in $targetProfileDirs) {
    $dirName = Split-Path -Leaf $targetDir
    if ($scriptDir.TrimEnd('\', '/') -ieq $targetDir.TrimEnd('\', '/')) {
        continue
    }

    try {
        $item = Get-Item -LiteralPath $targetDir -ErrorAction SilentlyContinue
        $isJunction = $item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)

        if ($isJunction -and -not $Force) {
            Write-Host "  [OK] $dirName ya está vinculado a dotfiles mediante Unión NTFS." -ForegroundColor Green
        } else {
            if (Test-Path -LiteralPath $targetDir) {
                $backupDir = "${targetDir}_bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
                Move-Item -LiteralPath $targetDir -Destination $backupDir -Force
                Write-Host "  (!) Carpeta previa '$dirName' respaldada en '$backupDir'." -ForegroundColor Yellow
            }
            cmd /c mklink /J "$targetDir" "$scriptDir" | Out-Null
            Write-Host "  [OK] Unión NTFS creada con éxito: '$dirName' -> '$scriptDir'." -ForegroundColor Green
        }
    } catch {
        Write-Warning "Error al vincular '$dirName': $_"
    }
}

# ------------------------------------------------------------------------------
# 2. PROVEEDOR NUGET Y MÓDULOS DE POWERSHELL
# ------------------------------------------------------------------------------
Write-Host "`n2. Comprobando módulos de PowerShell..." -ForegroundColor DarkCyan

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    if (-not $nuget -or $nuget.Version -lt [Version]"2.8.5.201") {
        Write-Host "  [>>] Instalando/actualizando proveedor NuGet..." -ForegroundColor Cyan
        [void](Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction SilentlyContinue)
    }
} catch {
    Write-Warning "No se pudo actualizar NuGet automáticamente: $_"
}

$requiredModules = @(
    @{ Name = "posh-git";   Description = "Prompt Git y autocompletado avanzado"; MinVersion = "0.7.0" }
    @{ Name = "PSReadLine"; Description = "Autocompletado predictivo inteligente"; MinVersion = "2.2.6" }
)

$localModDir = Join-Path $scriptDir "Modules"
if (-not (Test-Path -LiteralPath $localModDir)) {
    New-Item -ItemType Directory -Path $localModDir -Force | Out-Null
}

foreach ($m in $requiredModules) {
    $modName = $m.Name
    $modDesc = $m.Description
    $minVer  = if ($m.MinVersion) { [Version]$m.MinVersion } else { $null }

    try {
        $installed = Get-Module -ListAvailable -Name $modName -ErrorAction SilentlyContinue |
                     Sort-Object Version -Descending | Select-Object -First 1

        if ($installed -and (-not $minVer -or $installed.Version -ge $minVer) -and ($installed.Path -match [regex]::Escape($localModDir))) {
            Write-Host "  [OK] Módulo '$modName' ($($installed.Version)) ya presente en dotfiles." -ForegroundColor Green
        } else {
            Write-Host "  [>>] Guardando módulo '$modName' en disco local..." -ForegroundColor Cyan
            try {
                Save-Module -Name $modName -Path $localModDir -Force -ErrorAction Stop
                Write-Host "  [OK] Módulo '$modName' guardado con éxito." -ForegroundColor Green
            } catch {
                Write-Host "  (!) Save-Module advirtió, probando Install-Module..." -ForegroundColor Yellow
                Install-Module -Name $modName -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber -ErrorAction SilentlyContinue
                Write-Host "  [OK] Módulo '$modName' instalado en CurrentUser." -ForegroundColor Green
            }
        }
    } catch {
        Write-Warning "Error al gestionar módulo '$modName': $_"
    }
}

# ------------------------------------------------------------------------------
# 3. CONFIGURACIONES LOCALES COMPARTIDAS (SQL & LAZYGIT)
# ------------------------------------------------------------------------------
Write-Host "`n3. Verificando configuraciones locales..." -ForegroundColor DarkCyan

$sqlCfg = Join-Path $scriptDir "sql-connections.json"
$sqlExample = Join-Path $scriptDir "sql-connections.example.json"
if (-not (Test-Path -LiteralPath $sqlCfg) -and (Test-Path -LiteralPath $sqlExample)) {
    Copy-Item -LiteralPath $sqlExample -Destination $sqlCfg -Force
    Write-Host "  [OK] Creado 'sql-connections.json' desde plantilla de ejemplo." -ForegroundColor Green
} elseif (Test-Path -LiteralPath $sqlCfg) {
    Write-Host "  [OK] 'sql-connections.json' ya presente." -ForegroundColor Green
}

$lgTargetDir = Join-Path $env:APPDATA "lazygit"
$lgSource = Join-Path $scriptDir "config\lazygit.yml"
$lgTarget = Join-Path $lgTargetDir "config.yml"
if (Test-Path -LiteralPath $lgSource) {
    if (-not (Test-Path -LiteralPath $lgTargetDir)) {
        New-Item -ItemType Directory -Path $lgTargetDir -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $lgTarget)) {
        Copy-Item -LiteralPath $lgSource -Destination $lgTarget -Force
        Write-Host "  [OK] Archivo 'config.yml' de Lazygit inicializado en AppData." -ForegroundColor Green
    } else {
        Write-Host "  [OK] Configuración de Lazygit ya presente en AppData." -ForegroundColor Green
    }
}

# ------------------------------------------------------------------------------
# 4. INSTALACIÓN DE HERRAMIENTAS CLI VÍA WINGET
# ------------------------------------------------------------------------------
Write-Host "`n4. Comprobando herramientas recomendadas del sistema..." -ForegroundColor DarkCyan

$coreTools = @(
    @{ Cmd = "pwsh";  Name = "PowerShell 7";                 Winget = "Microsoft.PowerShell" }
    @{ Cmd = "git";   Name = "Git (Control de versiones)";   Winget = "Git.Git" }
    @{ Cmd = "nvim";  Name = "Neovim";                       Winget = "Neovim.Neovim" }
    @{ Cmd = "rg";    Name = "Ripgrep (Búsqueda en notas)";  Winget = "BurntSushi.ripgrep.MSVC" }
    @{ Cmd = "fd";    Name = "fd (Buscador de ficheros)";    Winget = "sharkdp.fd" }
    @{ Cmd = "fzf";   Name = "FZF (Fuzzy Finder)";           Winget = "junegunn.fzf" }
    @{ Cmd = "lg";    Name = "Lazygit (TUI Git)";            Winget = "jesseduffield.lazygit"; AltCmd = "lazygit" }
)

$recommendedTools = @(
    @{ Cmd = "bat";     Name = "bat (Cat con resaltado)";      Winget = "sharkdp.bat" }
    @{ Cmd = "7z";      Name = "7-Zip (Descompresor)";         Winget = "7zip.7zip" }
    @{ Cmd = "btop";    Name = "btop (Monitor de recursos)";   Winget = "aristocratos.btop4win" }
    @{ Cmd = "dust";    Name = "dust (Espacio en disco TUI)";  Winget = "bootandy.dust" }
    @{ Cmd = "wiztree"; Name = "WizTree (Mapa de disco)";      Winget = "AntibodySoftware.WizTree" }
    @{ Cmd = "font";    Name = "JetBrainsMono Nerd Font";      Winget = "DEVCOM.JetBrainsMonoNerdFont" }
    @{ Cmd = "clang";   Name = "LLVM / Clang (C para Treesitter)"; Winget = "LLVM.LLVM" }
)

$missingCore = @()
foreach ($t in $coreTools) {
    $exists = (Test-CommandAvailable $t.Cmd) -or ($t.AltCmd -and (Test-CommandAvailable $t.AltCmd))
    if ($exists) {
        Write-Host "  [OK] $($t.Name) disponible en el sistema." -ForegroundColor Green
    } else {
        Write-Host "  [--] $($t.Name) NO encontrado." -ForegroundColor Yellow
        $missingCore += $t
    }
}

$missingRec = @()
if (-not $Core) {
    foreach ($t in $recommendedTools) {
        $exists = if ($t.Cmd -eq "font") { $false } else { Test-CommandAvailable $t.Cmd }
        if ($exists) {
            Write-Host "  [OK] $($t.Name) disponible en el sistema." -ForegroundColor Green
        } else {
            Write-Host "  [○] $($t.Name) no detectado (opcional)." -ForegroundColor DarkGray
            $missingRec += $t
        }
    }
}

if (-not $NoTools) {
    $shouldInstallCore = $false
    $shouldInstallRec  = $false

    if ($All) {
        $shouldInstallCore = ($missingCore.Count -gt 0)
        $shouldInstallRec  = ($missingRec.Count -gt 0)
    } elseif ($Core) {
        $shouldInstallCore = ($missingCore.Count -gt 0)
    } else {
        # Modo interactivo
        $isInteractive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
        if ($isInteractive) {
            if ($missingCore.Count -gt 0) {
                Write-Host ""
                $ans = Read-Host "¿Deseas instalar las herramientas esenciales faltantes con winget? ($($missingCore.Name -join ', ')) [S/n]"
                if ($ans -eq '' -or $ans -match '^[sSyY]') {
                    $shouldInstallCore = $true
                }
            }
            if ($missingRec.Count -gt 0) {
                Write-Host ""
                $ansRec = Read-Host "¿Deseas instalar también utilidades recomendadas y Nerd Font? ($($missingRec.Name -join ', ')) [s/N]"
                if ($ansRec -match '^[sSyY]') {
                    $shouldInstallRec = $true
                }
            }
        }
    }

    if ($shouldInstallCore) {
        Write-Host "`n  [*] Instalando herramientas esenciales..." -ForegroundColor Cyan
        foreach ($t in $missingCore) {
            $alt = if ($t.AltCmd) { $t.AltCmd } else { $t.Cmd }
            Install-WingetPackage -PackageId $t.Winget -DisplayName $t.Name -CheckCmd $alt
        }
    }

    if ($shouldInstallRec) {
        Write-Host "`n  [*] Instalando herramientas recomendadas y fuentes..." -ForegroundColor Cyan
        foreach ($t in $missingRec) {
            $chk = if ($t.Cmd -eq "font") { $null } else { $t.Cmd }
            Install-WingetPackage -PackageId $t.Winget -DisplayName $t.Name -CheckCmd $chk
        }
    }

    Update-SessionPath
}

# ------------------------------------------------------------------------------
# 5. APROVISIONAMIENTO Y VINCULACIÓN DE NEOVIM
# ------------------------------------------------------------------------------
Write-Host "`n5. Aprovisionando configuración de Neovim..." -ForegroundColor DarkCyan

$homeDir      = [Environment]::GetFolderPath('UserProfile')
$nvimDotfiles = Join-Path $homeDir ".dotfiles\nvim"
$nvimTarget   = Join-Path $env:LOCALAPPDATA "nvim"

# 5.1. Comprobar existencia del repositorio .dotfiles\nvim
if (-not (Test-Path -LiteralPath $nvimDotfiles)) {
    if (Test-CommandAvailable "git") {
        Write-Host "  [>>] Repositorio '$nvimDotfiles' no detectado. Clonando desde GitHub..." -ForegroundColor Cyan
        try {
            git clone "https://github.com/Trejerum/nvim-config.git" "$nvimDotfiles"
            Write-Host "  [OK] Repositorio de Neovim clonado con éxito." -ForegroundColor Green
        } catch {
            Write-Warning "No se pudo clonar el repositorio de Neovim: $_"
        }
    } else {
        Write-Host "  (!) Git no disponible para clonar automáticamente '$nvimDotfiles'." -ForegroundColor Yellow
    }
} else {
    Write-Host "  [OK] Repositorio de Neovim presente en '$nvimDotfiles'." -ForegroundColor Green
}

# 5.2. Crear unión NTFS: %LOCALAPPDATA%\nvim -> ~/.dotfiles/nvim
if (Test-Path -LiteralPath $nvimDotfiles) {
    try {
        $nvimItem = Get-Item -LiteralPath $nvimTarget -ErrorAction SilentlyContinue
        $isNvimJunction = $nvimItem -and ($nvimItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)

        if ($isNvimJunction -and -not $Force) {
            Write-Host "  [OK] Neovim en AppData ya está vinculado a dotfiles mediante Unión NTFS." -ForegroundColor Green
        } else {
            if (Test-Path -LiteralPath $nvimTarget) {
                $bak = "${nvimTarget}_bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
                Move-Item -LiteralPath $nvimTarget -Destination $bak -Force
                Write-Host "  (!) Configuración previa de Neovim respaldada en '$bak'." -ForegroundColor Yellow
            }
            cmd /c mklink /J "$nvimTarget" "$nvimDotfiles" | Out-Null
            Write-Host "  [OK] Unión NTFS de Neovim creada: '$nvimTarget' -> '$nvimDotfiles'." -ForegroundColor Green
        }
    } catch {
        Write-Warning "No se pudo vincular la carpeta de Neovim en AppData: $_"
    }
}

# 5.3. Sincronización desatendida de plugins con lazy.nvim
if (Test-CommandAvailable "nvim") {
    Write-Host "  [>>] Sincronizando plugins de Neovim con lazy.nvim (headless)..." -ForegroundColor Cyan
    try {
        $nvimProc = Start-Process -FilePath "nvim" -ArgumentList "--headless", "+Lazy! sync", "+qa" -NoNewWindow -Wait -PassThru
        Write-Host "  [OK] Plugins de Neovim sincronizados con éxito." -ForegroundColor Green
    } catch {
        Write-Warning "Aviso al sincronizar plugins con lazy.nvim: $_ (se descargarán al abrir nvim manualmente)."
    }
} else {
    Write-Host "  ○ Neovim no está disponible en PATH para sincronizar plugins." -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# 6. CONFIGURACIÓN DE TERMINALES (WINDOWS TERMINAL & VS CODE)
# ------------------------------------------------------------------------------
Write-Host "`n6. Configurando terminales predeterminadas..." -ForegroundColor DarkCyan

# 6.1. Windows Terminal
$wtCandidates = @(
    (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"),
    (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"),
    (Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\settings.json")
)
$wtSettings = $wtCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if ($wtSettings) {
    try {
        $rawWt = Get-Content -LiteralPath $wtSettings -Raw -Encoding UTF8
        $wtObj = $rawWt | ConvertFrom-Json
        $pwshGuid = "{574e775e-4f2a-5b96-ac1e-a2962a402336}"

        if ($wtObj.profiles -and $wtObj.profiles.list) {
            $pList = [System.Collections.ArrayList]@($wtObj.profiles.list)
            $existing = @($pList | Where-Object { $_.guid -eq $pwshGuid })

            if ($existing.Count -gt 0) {
                $primary = $existing[0]
                $primary.name = "PowerShell 7"
                $primary.source = "Windows.Terminal.PowershellCore"
                $primary.startingDirectory = "%USERPROFILE%"
                $primary.hidden = $false

                if ($existing.Count -gt 1) {
                    for ($i = $pList.Count - 1; $i -ge 0; $i--) {
                        if ($pList[$i].guid -eq $pwshGuid -and $pList[$i] -ne $primary) {
                            $pList.RemoveAt($i)
                        }
                    }
                }
            } else {
                $newProf = [PSCustomObject]@{
                    guid              = $pwshGuid
                    hidden            = $false
                    name              = "PowerShell 7"
                    source            = "Windows.Terminal.PowershellCore"
                    startingDirectory = "%USERPROFILE%"
                }
                [void]$pList.Insert(0, $newProf)
            }

            $wtObj.profiles.list = $pList
            $wtObj.defaultProfile = $pwshGuid

            $updatedJson = $wtObj | ConvertTo-Json -Depth 32
            [System.IO.File]::WriteAllText($wtSettings, $updatedJson, [System.Text.Encoding]::UTF8)
            Write-Host "  [OK] Windows Terminal configurado con PowerShell 7 por defecto." -ForegroundColor Green
        }
    } catch {
        Write-Warning "No se pudo actualizar Windows Terminal settings.json automáticamente: $_"
    }
} else {
    Write-Host "  ○ Windows Terminal no instalado o aún no inicializado." -ForegroundColor DarkGray
}

# 6.2. Visual Studio Code
$vscSettings = Join-Path $env:APPDATA "Code\User\settings.json"
if (Test-Path -LiteralPath $vscSettings) {
    try {
        $rawVsc = Get-Content -LiteralPath $vscSettings -Raw -Encoding UTF8
        $vscObj = $rawVsc | ConvertFrom-Json
        $vscObj | Add-Member -NotePropertyName "terminal.integrated.defaultProfile.windows" -NotePropertyValue "PowerShell 7" -Force

        $profilesProp = "terminal.integrated.profiles.windows"
        $currentProfiles = if ($vscObj.PSObject.Properties[$profilesProp]) { $vscObj.$profilesProp } else { [PSCustomObject]@{} }
        $currentProfiles | Add-Member -NotePropertyName "PowerShell 7" -NotePropertyValue ([PSCustomObject]@{ path = "pwsh.exe"; icon = "terminal-powershell" }) -Force
        $vscObj | Add-Member -NotePropertyName $profilesProp -NotePropertyValue $currentProfiles -Force

        $updatedVsc = $vscObj | ConvertTo-Json -Depth 32
        [System.IO.File]::WriteAllText($vscSettings, $updatedVsc, [System.Text.Encoding]::UTF8)
        Write-Host "  [OK] VS Code configurado con PowerShell 7 por defecto." -ForegroundColor Green
    } catch {
        Write-Warning "No se pudo actualizar VS Code settings.json automáticamente: $_"
    }
} else {
    Write-Host "  ○ VS Code no instalado o aún no configurado." -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# 7. RESUMEN FINAL
# ------------------------------------------------------------------------------
Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  ¡Aprovisionamiento completado con éxito!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  • `$PROFILE vinculado y activo para Windows PowerShell y PowerShell 7." -ForegroundColor White
Write-Host "  • Módulos posh-git y PSReadLine listos." -ForegroundColor White
if (Test-Path -LiteralPath $nvimTarget) {
    Write-Host "  • Neovim vinculado (%LOCALAPPDATA%\nvim -> ~/.dotfiles/nvim)." -ForegroundColor White
}
Write-Host "`n  Para activar el perfil en la consola actual, ejecuta:" -ForegroundColor DarkGray
Write-Host "    . `$PROFILE" -ForegroundColor Cyan
Write-Host "  O abre una nueva pestaña de PowerShell 7.`n" -ForegroundColor DarkGray
