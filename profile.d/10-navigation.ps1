# ==============================================================================
# 10-NAVIGATION: NAVEGACIÓN RÁPIDA (PROYECTOS & ENTORNO)
# ==============================================================================

$global:SgaRoot = Join-Path $HOME "Documentos\Proyectos\SGA"
$script:SgaRoot = $global:SgaRoot

function sga     { Set-Location $global:SgaRoot }
function rsga    { Set-Location (Join-Path $global:SgaRoot "RSGA") }
function rsga2   { Set-Location (Join-Path $global:SgaRoot "RSGA_2") }
function rsga3   { Set-Location (Join-Path $global:SgaRoot "RSGA_3") }
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
    #>
    param(
        [Parameter(Position = 0)]
        [string]$Module
    )
    if ($Module) {
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

# Salto dinámico a cualquier subproyecto dentro de Documentos\Proyectos con autocompletado
function proj {
    <#
    .SYNOPSIS
        Navega dinámicamente a cualquier subproyecto dentro de Documentos\Proyectos.
    .EXAMPLE
        proj
        proj MiProyecto
        proj ApiBackend
    #>
    param(
        [Parameter(Position = 0)]
        [string]$Name
    )
    $projDir = Join-Path $HOME "Documentos\Proyectos"
    if (-not (Test-Path -LiteralPath $projDir)) {
        Write-Warning "El directorio '$projDir' no existe."
        return
    }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Host "Proyectos disponibles en $projDir`:" -ForegroundColor DarkCyan
        Get-ChildItem -LiteralPath $projDir -Directory | Select-Object -ExpandProperty Name | ForEach-Object {
            Write-Host "  • $_" -ForegroundColor White
        }
        return
    }
    $target = Join-Path $projDir $Name
    if (Test-Path -LiteralPath $target) {
        Set-Location $target
    } else {
        $match = Get-ChildItem -LiteralPath $projDir -Directory | Where-Object { $_.Name -like "*$Name*" } | Select-Object -First 1
        if ($match) {
            Set-Location $match.FullName
        } else {
            Write-Host "● No se encontró ningún proyecto que coincida con '$Name' en $projDir" -ForegroundColor Yellow
        }
    }
}
Register-ArgumentCompleter -CommandName proj -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $projDir = Join-Path $HOME "Documentos\Proyectos"
    if (Test-Path -LiteralPath $projDir) {
        Get-ChildItem -LiteralPath $projDir -Directory |
            Where-Object { $_.Name -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', "Proyecto: $($_.Name)") }
    }
}

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

