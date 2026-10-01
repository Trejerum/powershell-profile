# ==============================================================================
# 3. ATAJOS DE GIT
# ==============================================================================

# 1. Alias nativo 'g' para Git (permite que posh-git lo detecte automáticamente para autocompletar)
Set-Alias -Name g -Value git -Option AllScope -ErrorAction SilentlyContinue

# 2. Integración con posh-git (autocompletado con Tab y estado de Git)
if (Get-Module -ListAvailable -Name posh-git) {
    Import-Module posh-git -ErrorAction SilentlyContinue
}

# 3. Autocompletado de ramas para 'gco' con posh-git
if (Get-Command Register-ArgumentCompleter -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -CommandName gco -Native -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        if (Get-Command Expand-GitCommand -ErrorAction SilentlyContinue) {
            $padLength = $cursorPosition - $commandAst.Extent.StartOffset
            $text = $commandAst.ToString().PadRight($padLength, ' ').Substring(0, $padLength)
            $text = $text -replace '^gco\s*', 'git checkout '
            $matches = Expand-GitCommand $text
            foreach ($m in $matches) {
                [System.Management.Automation.CompletionResult]::new($m, $m, 'ParameterValue', $m)
            }
        }
    }
}
function gs    { git status -sb $args }
function gp    { git pull $args }
function gf    { git fetch $args }
function gpush { git push $args }
# Push de la rama actual configurando upstream (por defecto 'origin')
function gpsup {
    $branch = (git branch --show-current 2>$null)
    if ([string]::IsNullOrWhiteSpace($branch)) {
        Write-Error "No estás en una rama de Git válida o no se pudo obtener la rama actual."
        return
    }
    $branch = $branch.Trim()

    $remote = "origin"
    $extraArgs = @()

    if ($args.Count -gt 0 -and -not ($args[0].StartsWith('-'))) {
        $remote = $args[0]
        if ($args.Count -gt 1) {
            $extraArgs = $args[1..($args.Count - 1)]
        }
    } else {
        $extraArgs = $args
    }

    git push --set-upstream $remote $branch @extraArgs
}
Set-Alias -Name gpu -Value gpsup -ErrorAction SilentlyContinue
Set-Alias -Name gpushu -Value gpsup -ErrorAction SilentlyContinue
function gco   { git checkout $args }
function ga    { git add . $args }
function glog  { git log --oneline --graph --decorate -n 10 $args }
function gme   { git for-each-ref --format="%(committername) | %(refname:short)" refs/remotes/ | Select-String "diego.corral" }

# Guardar cambios en el stash con mensaje descriptivo y timestamp
function gss {
    param([string]$Message)

    $branch = (git branch --show-current).Trim()
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"

    if ([string]::IsNullOrWhiteSpace($Message)) {
        $finalMsg = "WIP en [$branch] ($timestamp)"
    } else {
        $finalMsg = "$Message | [$branch] ($timestamp)"
    }

    git stash push -u -m "$finalMsg"
}

# Listar los stashes con formato legible
function gsl {
    git stash list --pretty=format:"%C(yellow)%gd%C(reset) - %C(cyan)%cr%C(reset) : %C(white)%s%C(reset)"
}

# Recuperar y aplicar stash (por defecto el último)
function gsp {
    param([int]$Index = 0)
    git stash pop "stash@{$Index}"
}

# Revisión de Pull Requests con Antigravity sin checkout de rama
function agy-review-pr {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Branch,
        [Parameter(Position=1)]
        [string]$Base = "develop",
        [switch]$Print
    )

    $prompt = @"
Actúa como un Senior Software Developer experimentado en calidad de software y proyectos de largo recorrido.
Analiza la rama remota '$Branch' comparada contra '$Base' sin hacer checkout ni switch de rama.
Pasos:
1. Ejecuta 'git fetch origin $Branch $Base' si hace falta.
2. Extrae el diff con 'git diff origin/$Base...origin/$Branch'.
3. Inspecciona archivos clave locales si requieres contexto de arquitectura.
4. Evalúa regresiones, bugs, consistencia y da un veredicto final: [APROBADA] / [CAMBIOS REQUERIDOS] / [RECHAZADA] con informe justificado.
"@

    if ($Print) {
        agy -p $prompt
    } else {
        agy -i $prompt
    }
}

# Abrir archivos modificados/nuevos del repositorio Git en Neovim
function vmod {
    <#
    .SYNOPSIS
        Muestra y abre en Neovim todos los archivos modificados, agregados o no rastreados en Git.
    .EXAMPLE
        vmod           # Lista los archivos en consola y los abre en pestañas con Quickfix
        vmod -List     # Solo muestra en consola qué archivos están modificados
        vmod -Splits   # Abre los archivos en divisiones verticales
        vmod -Buffers  # Abre los archivos como buffers normales sin pestañas
    #>
    [CmdletBinding()]
    param(
        [Alias('l')]
        [switch]$List,
        [switch]$Buffers,
        [switch]$Splits
    )

    $repoRoot = (git rev-parse --show-toplevel 2>$null)
    if (-not $repoRoot) {
        Write-Host "● No estás dentro de un repositorio Git." -ForegroundColor Yellow
        return
    }
    $repoRoot = $repoRoot.Trim()

    $statusLines = @(git status --porcelain 2>$null)
    if (-not $statusLines -or $statusLines.Count -eq 0) {
        Write-Host "● No hay archivos modificados en el repositorio actual." -ForegroundColor Yellow
        return
    }

    $items = @()
    foreach ($line in $statusLines) {
        if ($line -match '^(.{2})\s+(.+)$') {
            $st = $matches[1]
            $rawPath = $matches[2].Trim().Trim('"')
            if ($rawPath -match '->\s*(.+)$') {
                $rawPath = $matches[1].Trim().Trim('"')
            }
            $absPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($repoRoot, $rawPath))
            if (Test-Path -LiteralPath $absPath) {
                $desc = if ($st -eq '??') { 'Nuevo' }
                        elseif ($st -match '^M') { 'Staged' }
                        elseif ($st -match '^.M') { 'Modificado' }
                        elseif ($st -match 'A') { 'Añadido' }
                        elseif ($st -match 'D') { 'Eliminado' }
                        else { 'Modificado' }
                $items += [PSCustomObject]@{
                    Estado       = $desc
                    Codigo       = $st.Trim()
                    RutaRelativa = $rawPath
                    RutaAbsoluta = $absPath
                }
            }
        }
    }

    if ($items.Count -eq 0) {
        Write-Host "● No se encontraron archivos modificados accesibles en disco." -ForegroundColor Yellow
        return
    }

    # 1. Mostrar resumen claro y formateado en la consola
    Write-Host "`n● Archivos con cambios en el repositorio ($($items.Count)):`n" -ForegroundColor DarkCyan
    foreach ($item in $items) {
        $color = switch ($item.Estado) {
            'Nuevo'      { 'Green' }
            'Añadido'    { 'Green' }
            'Staged'     { 'Cyan' }
            'Eliminado'  { 'Red' }
            default      { 'Yellow' }
        }
        $badge = " [$($item.Estado)]".PadRight(15)
        Write-Host $badge -ForegroundColor $color -NoNewline
        Write-Host " -> " -ForegroundColor DarkGray -NoNewline
        Write-Host $item.RutaRelativa -ForegroundColor White
    }
    Write-Host ""

    # Si solo se solicitó listar, terminar aquí
    if ($List) {
        return
    }

    # 2. Generar lista Quickfix para Neovim
    $tempQf = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "vmod_qf_$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).txt")
    $qfLines = @(foreach ($item in $items) {
        "$($item.RutaAbsoluta):1:1: [$($item.Estado)] $($item.RutaRelativa)"
    })
    [System.IO.File]::WriteAllLines($tempQf, $qfLines, [System.Text.UTF8Encoding]::new($false))

    $targetFiles = @($items | Select-Object -ExpandProperty RutaAbsoluta)

    try {
        if ($Splits) {
            nvim -O @targetFiles -q $tempQf -c "copen"
        }
        elseif ($Buffers) {
            nvim @targetFiles -q $tempQf -c "copen"
        }
        else {
            # Modo por defecto: pestañas individuales visibles + Quickfix abierto
            nvim -p @targetFiles -q $tempQf -c "copen"
        }
    }
    finally {
        Remove-Item -LiteralPath $tempQf -Force -ErrorAction SilentlyContinue
    }
}
Set-Alias vdiff vmod

# Interfaz TUI interactiva de Lazygit
if (Get-Command lazygit -ErrorAction SilentlyContinue) {
    Set-Alias lg lazygit
}

# Añadir todo y crear commit en un único paso
function gcom {
    <#
    .SYNOPSIS
        Prepara todos los cambios (git add -A) y realiza el commit con el mensaje indicado.
    .EXAMPLE
        gcom "feat: implementar nuevo endpoint de clientes"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )
    git add -A
    git commit -m $Message
}

# Crear una nueva rama y posicionarse en ella inmediatamente
function gcob {
    <#
    .SYNOPSIS
        Crea y cambia a una nueva rama de Git (git checkout -b / git switch -c).
    .EXAMPLE
        gcob feature/auth-jwt
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Branch
    )
    git checkout -b $Branch
}
Set-Alias gswc gcob

# Listar ramas locales ordenadas por fecha de último commit con tiempo relativo
function gb {
    <#
    .SYNOPSIS
        Lista ramas locales ordenadas por fecha de actividad reciente.
    #>
    git branch --sort=-committerdate --format="%(color:yellow)%(refname:short)%(color:reset) %(color:cyan)(%(committerdate:relative))%(color:reset) - %(subject)"
}

# Deshacer el último commit manteniendo todos los cambios en el árbol de trabajo (soft reset)
function gundo {
    <#
    .SYNOPSIS
        Deshace el último commit pero conserva los cambios preparados (staged) en el árbol de trabajo.
    #>
    git reset --soft HEAD~1
    Write-Host "✓ Último commit deshecho (los cambios siguen en el área de preparación/staged)." -ForegroundColor Green
}

# Comparar diferencias de un archivo en Neovim con vista split (:diffsplit)
function vd {
    <#
    .SYNOPSIS
        Abre el diff de un archivo en Neovim con vista paralela split (:diffsplit).
    .EXAMPLE
        vd Program.cs
        vd
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$File
    )
    if ($File) {
        nvim -d $File
    } else {
        git difftool -t nvimdiff -y
    }
}

# Dashboard multi-entorno para repositorios SGA (RSGA, RSGA_2, RSGA_3) con salto rápido
function repo-status {
    <#
    .SYNOPSIS
        Muestra un dashboard en tiempo real de los entornos/clones Git de SGA con soporte de salto rápido.
    .EXAMPLE
        repos           # Muestra el estado de todos los clones
        repos -Fetch    # Hace git fetch silencioso antes de evaluar (alias: -f)
        repos 1         # Salta a RSGA
        repos 2         # Salta a RSGA_2
        repos 3         # Salta a RSGA_3
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Target,

        [Alias('f')]
        [switch]$Fetch,

        [Parameter()]
        [string]$Path = $script:SgaRoot
    )

    # 1. Soporte de salto directo si se pasa un identificador
    if ($Target) {
        $cleanTarget = $Target.Trim().ToLower()
        switch ($cleanTarget) {
            { $_ -in @('1', 'rsga', 'sga') } {
                rsga
                Write-Host "● Posicionado en [RSGA]" -ForegroundColor Green
                return
            }
            { $_ -in @('2', 'rsga2', 'rsga_2') } {
                rsga2
                Write-Host "● Posicionado en [RSGA_2]" -ForegroundColor Green
                return
            }
            { $_ -in @('3', 'rsga3', 'rsga_3') } {
                rsga3
                Write-Host "● Posicionado en [RSGA_3]" -ForegroundColor Green
                return
            }
        }
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "El directorio '$Path' no existe."
        return
    }

    $dirs = @(Get-ChildItem -LiteralPath $Path -Directory | Where-Object { Test-Path (Join-Path $_.FullName '.git') })
    if ($dirs.Count -eq 0) {
        Write-Host "● No se encontraron repositorios Git en $Path." -ForegroundColor Yellow
        return
    }

    if ($Fetch) {
        Write-Host "Sincronizando estado remoto (git fetch)..." -ForegroundColor DarkGray
        foreach ($d in $dirs) {
            git -C $d.FullName fetch -q 2>$null
        }
    }

    Write-Host "`n=== Estado de Entornos SGA ===`n" -ForegroundColor DarkCyan

    $idx = 1
    foreach ($d in $dirs) {
        $p = $d.FullName
        $branch = (git -C $p branch --show-current 2>$null)
        if (-not $branch) { $branch = 'DETACHED' }

        $statusLines = @(git -C $p status --porcelain 2>$null)
        $staged = @($statusLines | Where-Object { $_ -match '^[MADRC]' }).Count
        $modified = @($statusLines | Where-Object { $_ -match '^.[MD]' }).Count
        $untracked = @($statusLines | Where-Object { $_ -match '^\?\?' }).Count

        $statusParts = @()
        if ($staged -gt 0)    { $statusParts += "+$staged staged" }
        if ($modified -gt 0)  { $statusParts += "~$modified mod" }
        if ($untracked -gt 0) { $statusParts += "!$untracked new" }

        $localStatus = if ($statusParts.Count -gt 0) { $statusParts -join ', ' } else { 'Limpio' }
        $localColor  = if ($statusParts.Count -gt 0) { 'Yellow' } else { 'Green' }

        $upstreamCounts = (git -C $p rev-list --left-right --count 'HEAD...@{upstream}' 2>$null)
        $syncStatus = 'Sin tracking'
        $syncColor = 'DarkGray'
        if ($upstreamCounts) {
            $parts = $upstreamCounts.Trim().Split([char]9)
            if ($parts.Count -ge 2) {
                $ahead = [int]$parts[0]
                $behind = [int]$parts[1]
                if ($ahead -eq 0 -and $behind -eq 0) {
                    $syncStatus = 'Al día'
                    $syncColor = 'Green'
                } elseif ($ahead -gt 0 -and $behind -eq 0) {
                    $syncStatus = "↑ $ahead pendiente(s)"
                    $syncColor = 'Cyan'
                } elseif ($ahead -eq 0 -and $behind -gt 0) {
                    $syncStatus = "↓ $behind por bajar"
                    $syncColor = 'Magenta'
                } else {
                    $syncStatus = "↑ $ahead ↓ $behind (divergente)"
                    $syncColor = 'Red'
                }
            }
        }

        $lastCommit = (git -C $p log -1 --format='%h (%cr) %s' 2>$null)
        if ($lastCommit -and $lastCommit.Length -gt 60) {
            $lastCommit = $lastCommit.Substring(0, 57) + '...'
        }

        $tag = "[$idx] $($d.Name)".PadRight(12)
        Write-Host $tag -ForegroundColor Yellow -NoNewline
        Write-Host (" " + $branch).PadRight(32) -ForegroundColor Cyan -NoNewline
        Write-Host " | " -ForegroundColor DarkGray -NoNewline
        Write-Host $localStatus.PadRight(18) -ForegroundColor $localColor -NoNewline
        Write-Host " | " -ForegroundColor DarkGray -NoNewline
        Write-Host $syncStatus -ForegroundColor $syncColor
        if ($lastCommit) {
            Write-Host "     └─ $lastCommit" -ForegroundColor DarkGray
        }

        $idx++
    }

    Write-Host "`nTip: Usa 'repos <1|2|3>' para saltar directamente al clon deseado o '-f' para refrescar origin.`n" -ForegroundColor DarkGray
}
Set-Alias repos repo-status
Set-Alias sga-status repo-status

