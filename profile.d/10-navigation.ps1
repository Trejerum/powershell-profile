# ==============================================================================
# 10-NAVIGATION: NAVEGACIÓN RÁPIDA (PROYECTOS & ENTORNO)
# ==============================================================================

# Directorio raíz de proyectos (configurable vía variable de entorno $env:PROJECTS_DIR)
$global:ProjectsRoot = if ($env:PROJECTS_DIR -and (Test-Path -LiteralPath $env:PROJECTS_DIR)) {
    $env:PROJECTS_DIR
} else {
    Join-Path $HOME "Documentos\Proyectos"
}

function profile { Set-Location (Split-Path -Parent $PROFILE) }
function notes   { Set-Location (Join-Path $HOME "Documentos\Notes") }

function ep {
    <#
    .SYNOPSIS
        Abre $PROFILE o un módulo de 'profile.d' en Neovim para editarlo.
    .EXAMPLE
        ep
        ep sql
        ep git
        ep local
    #>
    param(
        [Parameter(Position = 0)]
        [string]$Module
    )
    if ($Module) {
        if ($Module -ieq "local") {
            $localF = Join-Path (Split-Path -Parent $PROFILE) "profile.local.ps1"
            if (-not (Test-Path -LiteralPath $localF)) {
                [System.IO.File]::WriteAllText($localF, "# ==============================================================================`r`n# PERFIL LOCAL PERSONAL`r`n# ==============================================================================`r`n", [System.Text.Encoding]::UTF8)
            }
            nvim $localF
            return
        }
        $profDir = Split-Path -Parent $PROFILE
        $target = Get-ChildItem -Path "$profDir\profile.d\*$Module*.ps1" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($target) {
            nvim $target.FullName
            return
        }
    }
    nvim $PROFILE
}
function en      { nvim (Join-Path $env:LOCALAPPDATA "nvim") }
Set-Alias edit-profile ep
Set-Alias edit-nvim    en

# Subir niveles de directorio rápidamente
function ..   { Set-Location .. }
function ...  { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

# Crear directorio y entrar inmediatamente
function mkcd {
    <#
    .SYNOPSIS
        Crea una carpeta (y sus directorios padres si no existen) y navega a ella de inmediato.
    .EXAMPLE
        mkcd backend/api/v2
    #>
    param([Parameter(Mandatory = $true, Position = 0)][string]$Path)
    [void](New-Item -ItemType Directory -Path $Path -Force)
    Set-Location $Path
}

# Abrir explorador de archivos en la ruta actual o indicada
function open {
    <#
    .SYNOPSIS
        Abre el Explorador de archivos de Windows en la carpeta actual o en la ruta indicada.
    .EXAMPLE
        open
        open ./logs
    #>
    param([Parameter(Position = 0)][string]$Path = ".")
    Invoke-Item $Path
}
Set-Alias o open

# ==============================================================================
# GESTOR DE ENTORNOS DESECHABLES / SANDBOX (SCRATCHPADS)
# ==============================================================================
$global:ScratchRoot = if ($env:SCRATCH_DIR) { $env:SCRATCH_DIR } else { Join-Path $HOME "Documentos\Scratch" }

function scratch {
    <#
    .SYNOPSIS
        Crea o navega a un entorno temporal desechable fechado (sandbox) para pruebas rápidas.
    .EXAMPLE
        scratch                 # Crea/entra en Documentos\Scratch\yyyy-MM-dd
        scratch test-api        # Crea/entra en Documentos\Scratch\yyyy-MM-dd\test-api
        scratch -List           # Lista los entornos scratch existentes y su tamaño
        scratch -Clean 7        # Elimina directorios scratch con más de 7 días
        scratch -Nvim           # Entra y abre Neovim de inmediato (-v)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name,

        [Alias('l')]
        [switch]$List,

        [int]$Clean = 0,

        [Alias('v')]
        [switch]$Nvim,

        [Alias('o')]
        [switch]$Open
    )

    $root = $global:ScratchRoot

    # 1. Listado de entornos existentes (-List)
    if ($List) {
        if (-not (Test-Path -LiteralPath $root)) {
            Write-Host "● No hay entornos scratch creados todavía ($root)." -ForegroundColor DarkGray
            return
        }
        $dirs = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if (-not $dirs -or $dirs.Count -eq 0) {
            Write-Host "● No hay entornos scratch creados todavía ($root)." -ForegroundColor DarkGray
            return
        }

        Write-Host "`n=== Entornos Scratch Desechables ($root) ===`n" -ForegroundColor DarkCyan
        foreach ($d in $dirs) {
            $files = @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File -ErrorAction SilentlyContinue)
            $sizeMB = [Math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
            $dateStr = $d.LastWriteTime.ToString("yyyy-MM-dd HH:mm")

            Write-Host "  $($d.Name.PadRight(24))" -NoNewline -ForegroundColor Yellow
            Write-Host "$dateStr" -NoNewline -ForegroundColor DarkGray
            Write-Host " | " -NoNewline -ForegroundColor DarkGray
            Write-Host "$($files.Count) archivos ($sizeMB MB)" -ForegroundColor Cyan
        }
        Write-Host ""
        return
    }

    # 2. Limpieza de entornos antiguos (-Clean N días)
    if ($Clean -gt 0) {
        if (-not (Test-Path -LiteralPath $root)) { return }
        $cutoff = (Get-Date).AddDays(-$Clean)
        $oldDirs = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff }
        if (-not $oldDirs -or $oldDirs.Count -eq 0) {
            Write-Host "✓ No hay carpetas scratch con más de $Clean días." -ForegroundColor Green
            return
        }
        foreach ($d in $oldDirs) {
            Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "✓ Eliminado entorno antiguo: $($d.Name)" -ForegroundColor DarkGray
        }
        Write-Host "✓ Limpieza completada: $($oldDirs.Count) directorios eliminados." -ForegroundColor Green
        return
    }

    # 3. Creación o navegación a scratchpad fechado
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $targetDir = Join-Path $root $today
    if ($Name) {
        $targetDir = Join-Path $targetDir $Name
    }

    if (-not (Test-Path -LiteralPath $targetDir)) {
        [void](New-Item -ItemType Directory -Path $targetDir -Force)
        Write-Host "✓ Entorno scratch preparado: $targetDir" -ForegroundColor Green
    } else {
        Write-Host "● Entrando a entorno scratch existente: $targetDir" -ForegroundColor DarkGray
    }

    Set-Location -LiteralPath $targetDir

    if ($Nvim) {
        nvim .
    } elseif ($Open) {
        Invoke-Item $targetDir
    }
}
Set-Alias sandbox scratch

# Recargar el perfil de PowerShell en la sesión actual
function reload {
    <#
    .SYNOPSIS
        Recarga el perfil activo de PowerShell en la consola actual.
    #>
    . $PROFILE
    Write-Host "✓ Perfil de PowerShell recargado correctamente." -ForegroundColor Green
}
Set-Alias rel reload
Set-Alias rprof reload
Set-Alias reload-profile reload

