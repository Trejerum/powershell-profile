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

function nvim-config {
    <#
    .SYNOPSIS
        Navega al directorio de configuración de Neovim ($env:LOCALAPPDATA\nvim).
    .EXAMPLE
        nvim-config
        nvim-config -Edit
    #>
    [CmdletBinding()]
    param(
        [Alias('e', 'v')]
        [switch]$Edit
    )
    $nvimDir = Join-Path $env:LOCALAPPDATA "nvim"
    if (-not (Test-Path -LiteralPath $nvimDir)) {
        Write-Warning "El directorio de configuración de Neovim no existe: $nvimDir"
        return
    }
    Set-Location -LiteralPath $nvimDir
    if ($Edit) {
        nvim .
    }
}
Set-Alias cdnvim  nvim-config
Set-Alias cd-nvim nvim-config
Set-Alias nvimdir nvim-config

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

function en {
    <#
    .SYNOPSIS
        Abre la configuración de Neovim ($env:LOCALAPPDATA\nvim) o un archivo específico en Neovim.
    .EXAMPLE
        en
        en init.lua
    #>
    param(
        [Parameter(Position = 0)]
        [string]$File
    )
    $nvimDir = Join-Path $env:LOCALAPPDATA "nvim"
    if ($File) {
        $target = Join-Path $nvimDir $File
        if (Test-Path -LiteralPath $target) {
            nvim $target
            return
        }
    }
    nvim $nvimDir
}
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

# ==============================================================================
# MARCADORES TEMPORALES DE NAVEGACIÓN (BOOKMARKS)
# ==============================================================================
$script:MarksFile = Join-Path $env:LOCALAPPDATA "powershell_marks.json"

function Get-ProfileMarks {
    if (Test-Path -LiteralPath $script:MarksFile) {
        try {
            $raw = [System.IO.File]::ReadAllText($script:MarksFile, [System.Text.Encoding]::UTF8)
            if ($raw -and $raw.Trim()) {
                $obj = ConvertFrom-Json $raw
                $dict = @{}
                foreach ($prop in $obj.PSObject.Properties) {
                    $dict[$prop.Name] = $prop.Value
                }
                return $dict
            }
        } catch { }
    }
    return @{}
}

function Save-ProfileMarks {
    param([hashtable]$Marks)
    try {
        $json = $Marks | ConvertTo-Json -Compress
        [System.IO.File]::WriteAllText($script:MarksFile, $json, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Warning "No se pudieron guardar los marcadores: $_"
    }
}

function mark {
    <#
    .SYNOPSIS
        Guarda el directorio actual con una etiqueta rápida de navegación.
    .EXAMPLE
        mark
        mark api
        mark logs
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name
    )
    $curr = (Get-Location).Path
    $markName = if ($Name) { $Name.Trim().ToLowerInvariant() } else { (Split-Path -Leaf $curr).ToLowerInvariant() }

    $marks = Get-ProfileMarks
    $marks[$markName] = $curr
    Save-ProfileMarks -Marks $marks

    Write-Host "[OK] Marcador guardado: " -NoNewline -ForegroundColor Green
    Write-Host "$markName" -NoNewline -ForegroundColor Yellow
    Write-Host " -> $curr" -ForegroundColor DarkGray
}

function jump {
    <#
    .SYNOPSIS
        Navega rápidamente a un directorio marcado previamente.
    .EXAMPLE
        jump api
        j logs
        j (abre menú difuso si fzf está instalado)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name
    )
    $marks = Get-ProfileMarks
    if ($marks.Count -eq 0) {
        Write-Host "● No hay marcadores guardados todavía. Usa 'mark [nombre]' para guardar la carpeta actual." -ForegroundColor DarkGray
        return
    }

    $targetName = if ($Name) { $Name.Trim().ToLowerInvariant() } else { "" }

    if (-not $targetName) {
        if (Get-Command fzf -ErrorAction SilentlyContinue) {
            $lines = foreach ($k in ($marks.Keys | Sort-Object)) { "$($k.PadRight(16)) -> $($marks[$k])" }
            $selected = $lines | fzf --prompt="Marcadores > " --height=40% --reverse
            if ($selected) {
                $targetName = ($selected.Split(' ')[0]).Trim().ToLowerInvariant()
            } else {
                return
            }
        } else {
            marks
            return
        }
    }

    if ($marks.ContainsKey($targetName)) {
        $path = $marks[$targetName]
        if (Test-Path -LiteralPath $path) {
            Set-Location -LiteralPath $path
            Write-Host "[OK] Salto a [$targetName]: $path" -ForegroundColor Green
        } else {
            Write-Warning "La ruta del marcador '$targetName' no existe en disco: $path"
            Write-Host "Tip: Usa 'unmark -Clean' para purgar marcadores obsoletos." -ForegroundColor DarkGray
        }
    } else {
        Write-Warning "No existe ningún marcador llamado '$targetName'."
        Write-Host "Usa 'marks' para ver la lista de marcadores disponibles." -ForegroundColor DarkGray
    }
}
Set-Alias j jump

function marks {
    <#
    .SYNOPSIS
        Lista todos los marcadores de navegación guardados y su estado.
    .EXAMPLE
        marks
    #>
    [CmdletBinding()]
    param()

    $marks = Get-ProfileMarks
    if ($marks.Count -eq 0) {
        Write-Host "`n● No hay marcadores activos. Usa 'mark [nombre]' en cualquier carpeta.`n" -ForegroundColor DarkGray
        return
    }

    Write-Host "`n=== Marcadores de Navegación ($($marks.Count)) ===`n" -ForegroundColor DarkCyan
    foreach ($k in ($marks.Keys | Sort-Object)) {
        $path = $marks[$k]
        $exists = Test-Path -LiteralPath $path
        Write-Host "  $($k.PadRight(18))" -NoNewline -ForegroundColor Yellow
        Write-Host "$path " -NoNewline -ForegroundColor $(if ($exists) { "Cyan" } else { "DarkRed" })
        if (-not $exists) {
            Write-Host "[RUTA NO ENCONTRADA]" -ForegroundColor Red
        } else {
            Write-Host ""
        }
    }
    Write-Host ""
}
Set-Alias lmarks marks

function unmark {
    <#
    .SYNOPSIS
        Elimina uno, varios o todos los marcadores guardados.
    .EXAMPLE
        unmark api
        unmark -All
        unmark -Clean
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Position = 0)]
        [string]$Name,

        [switch]$All,
        [switch]$Clean,
        [switch]$Force
    )

    $marks = Get-ProfileMarks
    if ($marks.Count -eq 0) {
        Write-Host "● No hay marcadores guardados." -ForegroundColor DarkGray
        return
    }

    if ($All -or $Name -eq "*") {
        if ($Force -or $PSCmdlet.ShouldContinue("¿Seguro que deseas eliminar TODOS los marcadores ($($marks.Count))?", "Confirmar eliminación total")) {
            Save-ProfileMarks -Marks @{}
            Write-Host "[OK] Todos los marcadores han sido eliminados." -ForegroundColor Green
        }
        return
    }

    if ($Clean) {
        $toRemove = @()
        foreach ($k in $marks.Keys) {
            if (-not (Test-Path -LiteralPath $marks[$k])) {
                $toRemove += $k
            }
        }
        if ($toRemove.Count -eq 0) {
            Write-Host "[OK] No hay marcadores huérfanos. Todas las rutas existen." -ForegroundColor Green
            return
        }
        foreach ($k in $toRemove) {
            $marks.Remove($k)
        }
        Save-ProfileMarks -Marks $marks
        Write-Host "[OK] Limpieza completada: $($toRemove.Count) marcadores obsoletos eliminados ($($toRemove -join ', '))." -ForegroundColor Green
        return
    }

    if (-not $Name) {
        Write-Warning "Especifica el nombre del marcador a eliminar (ej. 'unmark api'), o usa 'unmark -All' o 'unmark -Clean'."
        return
    }

    $targetName = $Name.Trim().ToLowerInvariant()
    if ($marks.ContainsKey($targetName)) {
        $marks.Remove($targetName)
        Save-ProfileMarks -Marks $marks
        Write-Host "[OK] Marcador '$targetName' eliminado correctamente." -ForegroundColor Green
    } else {
        Write-Warning "No se encontró el marcador '$targetName'."
    }
}

# Autocompletado con Tabulador para jump y unmark
if (Get-Command Register-ArgumentCompleter -ErrorAction SilentlyContinue) {
    $script:MarkCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $marks = Get-ProfileMarks
        $marks.Keys | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "$_ -> $($marks[$_])")
        }
    }
    Register-ArgumentCompleter -CommandName jump   -ParameterName Name -ScriptBlock $script:MarkCompleter
    Register-ArgumentCompleter -CommandName j      -ParameterName Name -ScriptBlock $script:MarkCompleter
    Register-ArgumentCompleter -CommandName unmark -ParameterName Name -ScriptBlock $script:MarkCompleter
}

# ==============================================================================
# WINDOWS TERMINAL WORKSPACE LAYOUTS
# ==============================================================================
function layout-dev {
    <#
    .SYNOPSIS
        Abre un espacio de trabajo dividido en Windows Terminal (Neovim + Terminal Git + Terminal SQL/Soporte).
    .EXAMPLE
        layout-dev
        layout-dev mi-proyecto
        wtd
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path
    )

    if (-not (Get-Command wt -ErrorAction SilentlyContinue)) {
        Write-Warning "Windows Terminal (wt.exe) no está instalado o no se encuentra en el PATH."
        return
    }

    $targetPath = if ($Path) {
        if (Test-Path -LiteralPath $Path) {
            (Resolve-Path $Path).Path
        } else {
            $inProjects = Join-Path $global:ProjectsRoot $Path
            if (Test-Path -LiteralPath $inProjects) {
                (Resolve-Path $inProjects).Path
            } else {
                (Get-Location).Path
            }
        }
    } else {
        (Get-Location).Path
    }

    Write-Host "🚀 Iniciando layout dev en: $targetPath" -ForegroundColor Cyan

    $wtArgs = @(
        "-d", "`"$targetPath`"", "powershell.exe", "-NoExit", "-Command", "`"nvim .`"",
        ";", "split-pane", "-V", "-s", "0.35", "-d", "`"$targetPath`"", "powershell.exe",
        ";", "split-pane", "-H", "-s", "0.50", "-d", "`"$targetPath`"", "powershell.exe"
    )

    Start-Process wt.exe -ArgumentList $wtArgs
}
Set-Alias wtd layout-dev
Set-Alias dev-layout layout-dev

function split-term {
    <#
    .SYNOPSIS
        Divide el panel actual de Windows Terminal en la misma carpeta.
    .EXAMPLE
        split-term          # Divide verticalmente (panel a la derecha)
        split-term -H       # Divide horizontalmente (panel abajo)
        split-v
        split-h
    #>
    [CmdletBinding()]
    param(
        [Alias('v')]
        [switch]$Vertical,

        [Alias('h')]
        [switch]$Horizontal
    )
    if (-not (Get-Command wt -ErrorAction SilentlyContinue)) {
        Write-Warning "Windows Terminal (wt.exe) no está instalado o no se encuentra en el PATH."
        return
    }

    $curr = (Get-Location).Path
    $splitFlag = if ($Horizontal) { "-H" } else { "-V" }

    Start-Process wt.exe -ArgumentList @("-w", "0", "split-pane", $splitFlag, "-d", "`"$curr`"", "powershell.exe")
}
function split-v { split-term -Vertical }
function split-h { split-term -Horizontal }

# Recargar el perfil de PowerShell en la sesión actual
function reload {
    <#
    .SYNOPSIS
        Recarga el perfil activo de PowerShell en la consola actual.
    #>
    . $PROFILE
    Write-Host "[OK] Perfil de PowerShell recargado correctamente." -ForegroundColor Green
}
Set-Alias rel reload
Set-Alias rprof reload
Set-Alias reload-profile reload

