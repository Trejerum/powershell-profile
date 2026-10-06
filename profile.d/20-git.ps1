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
# Búsqueda difusa interactiva de ramas Git con fzf (fco / fbr)
function fco {
    <#
    .SYNOPSIS
        Selector interactivo difuso de ramas Git con fzf para checkout inmediato.
    #>
    [CmdletBinding()]
    param()
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Host "● fzf no está instalado. Instálalo con: winget install junegunn.fzf" -ForegroundColor Yellow
        return
    }
    $branches = git branch --all --color=never 2>$null | ForEach-Object {
        $_.Trim().Replace('* ', '').Replace('remotes/origin/', '')
    } | Where-Object { $_ -notmatch 'HEAD ->' } | Select-Object -Unique
    if (-not $branches) {
        Write-Host "● No se detectaron ramas en este repositorio." -ForegroundColor Yellow
        return
    }
    $selected = $branches | fzf --header="[Enter] Checkout a rama seleccionada | [ESC] Cancelar"
    if ($selected) {
        git checkout $selected.Trim()
    }
}
Set-Alias fbr fco

function gco {
    if ($args.Count -eq 0 -and (Get-Command fzf -ErrorAction SilentlyContinue)) {
        fco
    } else {
        git checkout @args
    }
}
function ga   { git add . $args }
function glog {
    <#
    .SYNOPSIS
        Historial gráfico compacto y coloreado de Git.
    .DESCRIPTION
        - Por defecto muestra los últimos 10 commits.
        - Si se pasa un número (ej. 'glog 50'), muestra esa cantidad de commits (-n 50).
        - Admite cualquier argumento nativo de git log (ej. 'glog 25 --all', 'glog develop 15', 'glog 30 --stat').
    .EXAMPLE
        glog
        glog 25
        glog 50 --all
        glog develop 15
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$FirstArg,

        [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
        [string[]]$ExtraArgs
    )

    $gitArgs = [System.Collections.Generic.List[string]]::new()
    $gitArgs.Add("log")
    $gitArgs.Add("--oneline")
    $gitArgs.Add("--graph")
    $gitArgs.Add("--decorate")

    $limitSet = $false

    # 1. Analizar el primer argumento
    if ($FirstArg) {
        if ($FirstArg -match '^\d+$') {
            $gitArgs.Add("-n")
            $gitArgs.Add($FirstArg)
            $limitSet = $true
        } elseif ($FirstArg -match '^-\d+$') {
            $gitArgs.Add("-n")
            $gitArgs.Add($FirstArg.Substring(1))
            $limitSet = $true
        } else {
            $gitArgs.Add($FirstArg)
            if ($FirstArg -in @('-n', '--max-count')) {
                $limitSet = $true
            }
        }
    }

    # 2. Analizar argumentos adicionales
    if ($ExtraArgs) {
        for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
            $arg = $ExtraArgs[$i]
            if ($arg -match '^\d+$' -and -not $limitSet) {
                $gitArgs.Add("-n")
                $gitArgs.Add($arg)
                $limitSet = $true
            } else {
                $gitArgs.Add($arg)
                if ($arg -in @('-n', '--max-count')) {
                    $limitSet = $true
                }
            }
        }
    }

    # 3. Si no se especificó límite numérico, aplicar el valor predeterminado (10)
    if (-not $limitSet) {
        $gitArgs.Add("-n")
        $gitArgs.Add("10")
    }

    git @gitArgs
}
function gme {
    $me = (git config user.name)
    if (-not $me) { $me = $env:USERNAME }
    git for-each-ref --format="%(committername) | %(refname:short)" refs/remotes/ | Select-String -Pattern $me -SimpleMatch
}

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
[PR Review: $Branch -> $Base]

Instrucción de título / sesión:
- Asigna o mantén como título de esta conversación: 'PR Review: $Branch'
- Asegúrate de que el identificador de la rama '$Branch' aparezca explícitamente en el título y en el resumen de la revisión.

Rol y contexto:
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
Set-Alias agy-pr-review agy-review-pr

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

# Guardado exprés de cambios pendientes en commit temporal
function gwip {
    <#
    .SYNOPSIS
        Crea un commit rápido temporal con todo el trabajo en curso para permitir cambiar de rama sin perder nada.
    .EXAMPLE
        gwip
        gwip "soporte de autenticacion"
    #>
    [CmdletBinding()]
    param([string]$Message)
    $branch = (git branch --show-current 2>$null)
    $ts = (Get-Date -Format "yyyy-MM-dd HH:mm")
    $desc = if ($Message) { "$Message ($ts)" } else { "WIP temporal ($ts)" }
    git add -A
    git commit -m "WIP: $desc [skip ci]" --no-verify
    Write-Host "✓ Trabajo guardado en commit temporal WIP en [$branch]." -ForegroundColor Green
    Write-Host "  Usa 'gunwip' cuando quieras restaurar estos cambios al árbol de trabajo." -ForegroundColor DarkGray
}

# Restaura el commit temporal creado con gwip
function gunwip {
    <#
    .SYNOPSIS
        Deshace el último commit si fue creado con 'gwip' y devuelve los cambios al árbol de trabajo.
    #>
    $lastMsg = (git log -1 --format='%s' 2>$null)
    if (-not $lastMsg) {
        Write-Warning "No se pudo leer el último commit."
        return
    }
    if ($lastMsg -notlike "WIP:*") {
        Write-Warning "El último commit no es un commit temporal de tipo WIP ('$lastMsg')."
        Write-Host "Si realmente deseas deshacerlo, usa 'gundo'." -ForegroundColor Yellow
        return
    }
    git reset --soft HEAD~1
    git reset HEAD 2>$null
    Write-Host "✓ Commit WIP restaurado al árbol de trabajo (archivos sin confirmar)." -ForegroundColor Green
}

# Limpieza y poda de ramas locales huérfanas o ya eliminadas en el servidor remoto
function gclean {
    <#
    .SYNOPSIS
        Ejecuta git fetch -p y elimina de forma segura ramas locales cuyo upstream remoto ya no existe.
    .EXAMPLE
        gclean
        gclean -Force
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )
    Write-Host "Sincronizando estado y podando referencias remotas (git fetch -p)..." -ForegroundColor DarkGray
    git fetch -p -q 2>$null

    $goneBranches = @(git branch -vv 2>$null | Where-Object { $_ -match ': gone\]' } | ForEach-Object {
        $parts = $_.Trim().Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
        $bName = if ($parts[0] -eq '*') { $parts[1] } else { $parts[0] }
        $bName
    } | Where-Object { $_ -and $_ -notmatch '^(master|main|develop|staging)$' })

    if ($goneBranches.Count -eq 0) {
        Write-Host "✓ No hay ramas locales huérfanas pendientes de limpieza." -ForegroundColor Green
        return
    }

    Write-Host "`nRamas locales detectadas cuyo tracking remoto ha sido eliminado:" -ForegroundColor Yellow
    foreach ($b in $goneBranches) {
        Write-Host "  - $b" -ForegroundColor White
    }

    if (-not $Force) {
        $confirm = Read-Host "`n¿Deseas eliminar estas $($goneBranches.Count) ramas locales? (s/N)"
        if ($confirm -notmatch '^(s|y|si|yes)$') {
            Write-Host "Operación cancelada." -ForegroundColor DarkGray
            return
        }
    }

    foreach ($b in $goneBranches) {
        git branch -D $b
    }
    Write-Host "✓ Se han eliminado $($goneBranches.Count) ramas huérfanas." -ForegroundColor Green
}

# Helper para descubrir recursivamente repositorios Git en el directorio de proyectos
function Get-ProfileGitRepositories {
    <#
    .SYNOPSIS
        Descubre recursivamente repositorios Git en una ruta base hasta profundidad 3.
    #>
    param(
        [string]$BasePath = $global:ProjectsRoot,
        [int]$MaxDepth = 3
    )

    if (-not (Test-Path -LiteralPath $BasePath)) { return @() }

    $found = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()

    function _ScanDir([string]$curr, [int]$depth) {
        if ($depth -gt $MaxDepth) { return }
        $gitDir = Join-Path $curr ".git"
        if (Test-Path -LiteralPath $gitDir) {
            $found.Add([System.IO.DirectoryInfo]::new($curr))
            return
        }
        try {
            $subdirs = [System.IO.Directory]::GetDirectories($curr)
            foreach ($sub in $subdirs) {
                $name = [System.IO.Path]::GetFileName($sub)
                if ($name.StartsWith(".") -or $name -in @('node_modules', 'bin', 'obj', 'packages', 'target', '.vs', '.git')) {
                    continue
                }
                _ScanDir $sub ($depth + 1)
            }
        } catch { }
    }

    _ScanDir $BasePath 1
    return @($found | Sort-Object FullName)
}

# Hub universal de proyectos y dashboard de repositorios Git
function repo-status {
    <#
    .SYNOPSIS
        Dashboard interactivo de repositorios Git y saltador rápido de proyectos.
    .EXAMPLE
        repos           # Muestra el estado de todos los repositorios en Proyectos
        repos -Fetch    # Hace git fetch silencioso en todos antes de evaluar (-f)
        repos 1         # Salta directamente al repositorio #1 del listado
        repos rsga      # Salta al repositorio que coincida con 'rsga'
        repos nts -Nvim # Salta al repositorio 'nts' y lo abre en Neovim (-v)
        repos 2 -Open   # Salta al repositorio #2 y abre el Explorador de Windows (-o)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Target,

        [Alias('f')]
        [switch]$Fetch,

        [Alias('v')]
        [switch]$Nvim,

        [Alias('o')]
        [switch]$Open,

        [switch]$Code,

        [Alias('i')]
        [switch]$Interactive,

        [Parameter()]
        [string]$Path = $global:ProjectsRoot
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "El directorio de proyectos '$Path' no existe. Configura `$global:ProjectsRoot o `$env:PROJECTS_DIR."
        return
    }

    $allRepos = @(Get-ProfileGitRepositories -BasePath $Path)
    if ($allRepos.Count -eq 0) {
        $dirs = @(Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue)
        if ($dirs.Count -eq 0) {
            Write-Host "● No se encontraron repositorios ni carpetas en $Path." -ForegroundColor Yellow
            return
        }
    }

    $doNavigate = {
        param([string]$targetPath, [string]$displayName)
        Set-Location $targetPath
        Write-Host "● Posicionado en [$displayName]" -ForegroundColor Green

        if ($Nvim) {
            nvim .
        } elseif ($Open) {
            Invoke-Item $targetPath
        } elseif ($Code) {
            code .
        }
    }

    # Modo interactivo con fzf (-i)
    if ($Interactive) {
        if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
            Write-Host "● fzf no está instalado. Instálalo con: winget install junegunn.fzf" -ForegroundColor Yellow
        } else {
            $fzfItems = @(foreach ($r in $allRepos) {
                $rel = ($r.FullName.Substring($Path.Length).TrimStart('\', '/')).Replace('\', '/')
                $branch = (git -C $r.FullName branch --show-current 2>$null)
                if (-not $branch) { $branch = 'DETACHED' }
                "$rel [$branch]"
            })
            $selected = $fzfItems | fzf --header="[Enter] Navegar al repositorio | [ESC] Salir"
            if ($selected) {
                $cleanRel = ($selected -split '\s+\[')[0]
                $matchRepo = $allRepos | Where-Object {
                    $rel = ($_.FullName.Substring($Path.Length).TrimStart('\', '/')).Replace('\', '/')
                    $rel -eq $cleanRel
                } | Select-Object -First 1
                if ($matchRepo) {
                    & $doNavigate $matchRepo.FullName $matchRepo.Name
                    return
                }
            }
            return
        }
    }

    # 1. Si se pasa un objetivo (Target)
    if (-not [string]::IsNullOrWhiteSpace($Target)) {
        $cleanTarget = $Target.Trim()

        # A. Si es un número (índice 1-based)
        if ($cleanTarget -match '^\d+$') {
            $num = [int]$cleanTarget
            if ($num -ge 1 -and $num -le $allRepos.Count) {
                $sel = $allRepos[$num - 1]
                $relName = ($sel.FullName.Substring($Path.Length).TrimStart('\', '/')).Replace('\', '/')
                & $doNavigate $sel.FullName $relName
                return
            } else {
                Write-Error "Índice $num fuera de rango (hay $($allRepos.Count) repositorios disponibles)."
                return
            }
        }

        # B. Búsqueda por nombre de repositorio (exacta o parcial)
        $normalized = $cleanTarget.Replace('/', '\').ToLower()
        $matchesList = @($allRepos | Where-Object {
            $rel = ($_.FullName.Substring($Path.Length).TrimStart('\', '/')).ToLower()
            $leaf = $_.Name.ToLower()
            $rel -eq $normalized -or $leaf -eq $normalized -or $rel.Contains($normalized) -or $leaf.Contains($normalized)
        })

        if ($matchesList.Count -eq 1) {
            $sel = $matchesList[0]
            $relName = ($sel.FullName.Substring($Path.Length).TrimStart('\', '/')).Replace('\', '/')
            & $doNavigate $sel.FullName $relName
            return
        }
        elseif ($matchesList.Count -gt 1) {
            $exact = @($matchesList | Where-Object { $_.Name.ToLower() -eq $normalized })
            if ($exact.Count -eq 1) {
                $sel = $exact[0]
                $relName = ($sel.FullName.Substring($Path.Length).TrimStart('\', '/')).Replace('\', '/')
                & $doNavigate $sel.FullName $relName
                return
            }

            Write-Host "`nCoincidencias encontradas para '$cleanTarget':" -ForegroundColor Cyan
            for ($i = 0; $i -lt $matchesList.Count; $i++) {
                $m = $matchesList[$i]
                $origIdx = $allRepos.IndexOf($m) + 1
                $rel = ($m.FullName.Substring($Path.Length).TrimStart('\', '/')).Replace('\', '/')
                Write-Host "  [$origIdx] $rel" -ForegroundColor White
            }
            Write-Host "`nUsa 'repos <#>' para saltar al deseado.`n" -ForegroundColor DarkGray
            return
        }
        else {
            $plainMatch = Get-ChildItem -LiteralPath $Path -Directory -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                          Where-Object { $_.Name -like "*$cleanTarget*" } | Select-Object -First 1
            if ($plainMatch) {
                & $doNavigate $plainMatch.FullName $plainMatch.Name
                return
            }

            Write-Host "● No se encontró ningún repositorio o proyecto que coincida con '$cleanTarget' en $Path" -ForegroundColor Yellow
            return
        }
    }

    # 2. Renderizado del Dashboard de repositorios
    if ($Fetch) {
        Write-Host "Sincronizando estado remoto en $($allRepos.Count) repositorios (git fetch)..." -ForegroundColor DarkGray
        foreach ($d in $allRepos) {
            git -C $d.FullName fetch -q 2>$null
        }
    }

    Write-Host "`n=== Repositorios de Proyectos ($Path) ===`n" -ForegroundColor DarkCyan

    $idx = 1
    foreach ($d in $allRepos) {
        $p = $d.FullName
        $relName = ($p.Substring($Path.Length).TrimStart('\', '/')).Replace('\', '/')
        if ($relName.Length -gt 28) {
            $relName = $relName.Substring(0, 25) + '...'
        }

        $branch = (git -C $p branch --show-current 2>$null)
        if (-not $branch) { $branch = 'DETACHED' }
        if ($branch.Length -gt 22) {
            $branch = $branch.Substring(0, 19) + '...'
        }

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
        if ($lastCommit -and $lastCommit.Length -gt 65) {
            $lastCommit = $lastCommit.Substring(0, 62) + '...'
        }

        $numTag = "[$idx]".PadLeft(4)
        Write-Host "$numTag " -ForegroundColor DarkGray -NoNewline
        Write-Host $relName.PadRight(29) -ForegroundColor Yellow -NoNewline
        Write-Host (" " + $branch).PadRight(24) -ForegroundColor Cyan -NoNewline
        Write-Host " | " -ForegroundColor DarkGray -NoNewline
        Write-Host $localStatus.PadRight(18) -ForegroundColor $localColor -NoNewline
        Write-Host " | " -ForegroundColor DarkGray -NoNewline
        Write-Host $syncStatus -ForegroundColor $syncColor
        if ($lastCommit) {
            Write-Host "       └─ $lastCommit" -ForegroundColor DarkGray
        }

        $idx++
    }

    Write-Host "`nTip: Usa 'repos <#>' o 'repos <nombre>' para saltar a un repositorio (-f para refrescar origin).`n" -ForegroundColor DarkGray
}
Set-Alias repos repo-status
Set-Alias proj  repo-status

Register-ArgumentCompleter -CommandName repos,repo-status,proj -ParameterName Target -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $basePath = $global:ProjectsRoot
    $all = @(Get-ProfileGitRepositories -BasePath $basePath)
    foreach ($r in $all) {
        $relName = ($r.FullName.Substring($basePath.Length).TrimStart('\', '/')).Replace('\', '/')
        $leafName = $r.Name
        if ($relName -like "$wordToComplete*" -or $leafName -like "$wordToComplete*") {
            [System.Management.Automation.CompletionResult]::new($leafName, $leafName, 'ParameterValue', "Repo: $relName")
            if ($relName -ne $leafName) {
                [System.Management.Automation.CompletionResult]::new($relName, $relName, 'ParameterValue', "Repo: $relName")
            }
        }
    }
}

# ==============================================================================
# COMPARACIÓN DE RAMAS: gcompare (alias: gcomp, branch-diff)
# ==============================================================================
function gcompare {
    <#
    .SYNOPSIS
        Compara la rama actual contra otra rama (por defecto develop, main o master) mostrando commits por delante, por detrás y archivos modificados.
    .DESCRIPTION
        Calcula qué commits tienes pendientes de merge (Ahead / develop..HEAD), qué commits te faltan por traerte (Behind / HEAD..develop) y el resumen de archivos cambiados.
    .EXAMPLE
        gcompare
        gcompare develop
        gcompare main
        gcompare origin/develop -Fetch
        gcompare -Stat
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Target,

        [Alias('f')]
        [switch]$Fetch,

        [switch]$Stat
    )

    $gitCheck = git rev-parse --is-inside-work-tree 2>$null
    if ($gitCheck -ne 'true') {
        Write-Warning "El directorio actual no es un repositorio Git."
        return
    }

    $currentBranch = (git branch --show-current 2>$null)
    if ([string]::IsNullOrWhiteSpace($currentBranch)) {
        $currentBranch = (git rev-parse --short HEAD 2>$null)
    }

    if ($Fetch) {
        Write-Host "● Sincronizando referencias remotas (git fetch -q)..." -ForegroundColor DarkGray
        git fetch -q 2>$null
    }

    # Si no se indica rama destino, buscar candidatas por orden habitual
    if (-not $Target) {
        $candidates = @('develop', 'origin/develop', 'main', 'origin/main', 'master', 'origin/master')
        foreach ($cand in $candidates) {
            if ($cand -ne $currentBranch -and (git rev-parse --verify --quiet $cand 2>$null)) {
                $Target = $cand
                break
            }
        }
    }

    if (-not $Target) {
        Write-Warning "No se especificó rama de destino y no se detectó develop, main ni master."
        return
    }

    # Validar que la rama destino existe
    $targetHash = git rev-parse --verify --quiet $Target 2>$null
    if (-not $targetHash) {
        Write-Error "No se encontró la rama o referencia '$Target'."
        return
    }

    $aheadCommits  = @(git log "$Target..HEAD" --format="format:%h|%s|%an|%cr" 2>$null | Where-Object { $_ })
    $behindCommits = @(git log "HEAD..$Target" --format="format:%h|%s|%an|%cr" 2>$null | Where-Object { $_ })
    $diffStat = (git diff --shortstat "$Target...HEAD" 2>$null)

    Write-Host "`n=== Comparación de Ramas ===" -ForegroundColor DarkCyan
    Write-Host "  Rama actual:  " -NoNewline -ForegroundColor DarkGray
    Write-Host $currentBranch -ForegroundColor Cyan
    Write-Host "  Rama destino: " -NoNewline -ForegroundColor DarkGray
    Write-Host $Target -ForegroundColor Yellow
    Write-Host ""

    # Commits por delante (tuyos pendientes de merge)
    if ($aheadCommits.Count -gt 0) {
        Write-Host "  ▲ Ahead: $($aheadCommits.Count) commit(s) pendientes de merge en $Target" -ForegroundColor Green
        foreach ($c in $aheadCommits) {
            $parts = $c -split '\|', 4
            $h = $parts[0]
            $msg = $parts[1]
            $author = $parts[2]
            $relTime = $parts[3]
            Write-Host "    • [$h] " -NoNewline -ForegroundColor White
            Write-Host "$msg " -NoNewline -ForegroundColor Gray
            Write-Host "($author, $relTime)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  ▲ Ahead: 0 commits pendientes (tu rama no tiene commits nuevos sobre $Target)" -ForegroundColor DarkGray
    }

    Write-Host ""

    # Commits por detrás (te faltan de la rama destino)
    if ($behindCommits.Count -gt 0) {
        Write-Host "  ▼ Behind: $($behindCommits.Count) commit(s) en $Target que te faltan por incorporar" -ForegroundColor Yellow
        foreach ($c in $behindCommits) {
            $parts = $c -split '\|', 4
            $h = $parts[0]
            $msg = $parts[1]
            $author = $parts[2]
            $relTime = $parts[3]
            Write-Host "    • [$h] " -NoNewline -ForegroundColor White
            Write-Host "$msg " -NoNewline -ForegroundColor Gray
            Write-Host "($author, $relTime)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  ▼ Behind: 0 commits (tu rama está al día con $Target)" -ForegroundColor DarkGray
    }

    Write-Host ""

    # Resumen de cambios
    if ($diffStat) {
        Write-Host "  Resumen de cambios: $diffStat" -ForegroundColor Cyan
        if ($Stat) {
            Write-Host "`nArchivos detallados:" -ForegroundColor DarkGray
            git diff --stat "$Target...HEAD"
        } else {
            Write-Host "  Tip: Usa 'gcompare $Target -Stat' para ver la lista detallada de archivos.`n" -ForegroundColor DarkGray
        }
    } elseif ($aheadCommits.Count -eq 0 -and $behindCommits.Count -eq 0) {
        Write-Host "  ✓ Ambas ramas están perfectamente sincronizadas.`n" -ForegroundColor Green
    }
}
Set-Alias gcomp gcompare
Set-Alias branch-diff gcompare

# Autocompletado de ramas para gcompare
if (Get-Command Register-ArgumentCompleter -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -CommandName gcompare,gcomp -ParameterName Target -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $branches = git branch --all --color=never 2>$null | ForEach-Object {
            $_.Trim().Replace('* ', '').Replace('remotes/', '')
        } | Where-Object { $_ -notmatch 'HEAD ->' } | Select-Object -Unique

        $branches |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Rama: $_")
            }
    }
}

# ==============================================================================
# RESOLUCIÓN RÁPIDA DE CONFLICTOS: gconflict (alias: vconflict, conflicts)
# ==============================================================================
function gconflict {
    <#
    .SYNOPSIS
        Detecta archivos con conflictos de merge o rebase activos y los abre en Neovim con Quickfix posicionándose en el primer conflicto.
    .EXAMPLE
        gconflict
        gconflict -List
    #>
    [CmdletBinding()]
    param(
        [switch]$List
    )

    $gitCheck = git rev-parse --is-inside-work-tree 2>$null
    if ($gitCheck -ne 'true') {
        Write-Warning "El directorio actual no es un repositorio Git."
        return
    }

    $repoRoot = (git rev-parse --show-toplevel 2>$null)
    $unmerged = @(git diff --name-only --diff-filter=U 2>$null)

    if ($unmerged.Count -eq 0) {
        Write-Host "✓ No hay conflictos activos de merge, rebase o cherry-pick." -ForegroundColor Green
        return
    }

    Write-Host "`n● Archivos con conflictos activos ($($unmerged.Count)):`n" -ForegroundColor Red

    $items = @()
    $qfLines = @()

    foreach ($relPath in $unmerged) {
        $absPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($repoRoot, $relPath))
        $conflictCount = 0

        if (Test-Path -LiteralPath $absPath) {
            $lines = [System.IO.File]::ReadAllLines($absPath, [System.Text.Encoding]::UTF8)
            for ($i = 0; $i -lt $lines.Length; $i++) {
                if ($lines[$i] -match '^<{7}(\s|$)') {
                    $conflictCount++
                    $qfLines += "$($absPath):$($i + 1):1: Conflicto #$conflictCount en $relPath"
                }
            }
        }

        $tag = if ($conflictCount -eq 1) { "1 conflicto" } else { "$conflictCount conflictos" }
        Write-Host "  [$tag] ".PadRight(18) -ForegroundColor Yellow -NoNewline
        Write-Host "-> " -ForegroundColor DarkGray -NoNewline
        Write-Host $relPath -ForegroundColor White

        $items += [PSCustomObject]@{
            RutaRelativa = $relPath
            RutaAbsoluta = $absPath
            Conflictos   = $conflictCount
        }
    }

    Write-Host ""

    if ($List) {
        return
    }

    # Crear lista Quickfix temporal para Neovim
    $tempQf = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "conflict_qf_$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).txt")
    try {
        [System.IO.File]::WriteAllLines($tempQf, $qfLines, [System.Text.UTF8Encoding]::new($false))
        $targetFiles = @($items | Select-Object -ExpandProperty RutaAbsoluta)

        # Abrir Neovim con pestañas para cada archivo, lista Quickfix (:copen) y cursor en el primer conflicto
        nvim -p @targetFiles -q $tempQf -c "copen" "+/^[<]\{7\}"
    }
    finally {
        Remove-Item -LiteralPath $tempQf -Force -ErrorAction SilentlyContinue
    }
}
Set-Alias vconflict gconflict
Set-Alias conflicts gconflict

# ==============================================================================
# INSPECTOR Y VISUALIZADOR DE COMMITS: gshow y vshow
# ==============================================================================
function gshow {
    <#
    .SYNOPSIS
        Inspecciona los cambios incluidos en un commit específico (o abre un selector difuso interactivo si no se indica commit).
    .DESCRIPTION
        - Sin parámetros: abre un selector difuso interactivo (fzf) con previsualización del diff en vivo en pantalla dividida (o muestra HEAD si fzf no está instalado).
        - Con <commit>: muestra autor, fecha, mensaje y diff completo del commit indicado.
        - Con -Stat: muestra únicamente la lista de archivos modificados y líneas alteradas (+/-).
        - Con -Files / -NameOnly: muestra únicamente las rutas de los archivos tocados en el commit.
        - Con -Nvim / -v: abre el commit directamente en Neovim con resaltado de sintaxis diff y plegado de código.
    .EXAMPLE
        gshow
        gshow 447686c
        gshow HEAD~1 -Stat
        gshow ae887bf -v
        vshow 447686c
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Commit,

        [switch]$Stat,

        [Alias('NameOnly')]
        [switch]$Files,

        [Alias('v', 'Open')]
        [switch]$Nvim
    )

    $gitCheck = git rev-parse --is-inside-work-tree 2>$null
    if ($gitCheck -ne 'true') {
        Write-Warning "El directorio actual no es un repositorio Git."
        return
    }

    # Si no se indica commit: selector interactivo fzf con preview en vivo o fallback a HEAD
    if (-not $Commit) {
        if (Get-Command fzf -ErrorAction SilentlyContinue) {
            $selected = git log --oneline --color=always -n 60 2>$null |
                fzf --ansi --preview "git show --stat --color=always {1}; echo ''; git show --color=always {1}" --preview-window=right:65%:wrap --header="[Enter] Ver en detalle | [ESC] Salir"
            if (-not $selected) {
                return
            }
            $Commit = ($selected.Trim() -split '\s+')[0]
        } else {
            $Commit = "HEAD"
        }
    }

    # Validar que el commit o referencia existe
    $fullHash = git rev-parse --verify --quiet "$Commit^{commit}" 2>$null
    if (-not $fullHash) {
        Write-Error "No se encontró el commit o referencia Git: '$Commit'"
        return
    }

    # Si se pide abrir en Neovim (-Nvim o alias vshow)
    if ($Nvim) {
        $shortHash = $fullHash.Substring(0, 8)
        $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "commit_$shortHash.diff")
        try {
            $diffText = git show --stat -p $fullHash 2>$null
            [System.IO.File]::WriteAllText($tempFile, ($diffText -join "`r`n"), [System.Text.Encoding]::UTF8)
            nvim -R -c "setfiletype git" $tempFile
        }
        finally {
            if (Test-Path -LiteralPath $tempFile) {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
        return
    }

    # Solo nombres de archivo
    if ($Files) {
        git show --name-only --format="" $fullHash 2>$null | Where-Object { $_ }
        return
    }

    # Solo estadísticas de archivos
    if ($Stat) {
        git show --stat --color=always $fullHash
        return
    }

    # Vista completa con pager nativo de Git
    git show --color=always $fullHash
}
Set-Alias git-show gshow

# vshow: abre el commit directamente en Neovim
function vshow {
    <#
    .SYNOPSIS
        Abre el diff y contenido completo de un commit directamente en Neovim (alias directo de gshow -Nvim).
    .EXAMPLE
        vshow
        vshow 447686c
        vshow HEAD~1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Commit
    )

    gshow -Commit $Commit -Nvim
}

# Autocompletado de commits para gshow y vshow
if (Get-Command Register-ArgumentCompleter -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -CommandName gshow,vshow,git-show -ParameterName Commit -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $commits = git log --format="format:%h|%s" -n 25 2>$null
        foreach ($c in $commits) {
            $parts = $c -split '\|', 2
            $h = $parts[0]
            $msg = $parts[1]
            if ($h -like "$wordToComplete*") {
                [System.Management.Automation.CompletionResult]::new($h, $h, 'ParameterValue', "$($h): $msg")
            }
        }
    }
}

# ==============================================================================
# BUSCADOR DE COMMITS EN TODO EL HISTORIAL: gfind / gsearch
# ==============================================================================
function gfind {
    <#
    .SYNOPSIS
        Busca commits en todo el historial de Git (en todas las ramas) por número de ticket, texto del mensaje o cambios en el código.
    .DESCRIPTION
        - Con <Query>: busca coincidencias en los mensajes de commit de todas las ramas (--all --grep -i).
        - Sin <Query>: si fzf está disponible, abre un explorador interactivo difuso con preview en vivo del diff. Si no, solicita el texto a buscar.
        - Con -Code (-S, -Diff): busca dentro del contenido del código o diffs (pickaxe: qué commit añadió o eliminó ese texto).
        - Con -Stat: muestra estadísticas de archivos modificados (+/-).
        - Con -Files / -NameOnly: muestra las rutas de los archivos modificados.
        - Con -v / -Nvim: abre el commit directamente en Neovim (si hay varios, permite seleccionar con fzf).
        - Con -Interactive / -fzf: abre el selector fzf con vista previa interactiva del diff en tiempo real.
    .EXAMPLE
        gfind 181865
        gfind "NUMEROS DE SERIE"
        gfind 181865 -Stat
        gfind 181865 -v
        gfind "MiClase" -Code
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Query,

        [Alias('S', 'Diff')]
        [switch]$Code,

        [switch]$Stat,

        [Alias('NameOnly')]
        [switch]$Files,

        [Alias('v', 'Open')]
        [switch]$Nvim,

        [Alias('i', 'fzf')]
        [switch]$Interactive
    )

    $gitCheck = git rev-parse --is-inside-work-tree 2>$null
    if ($gitCheck -ne 'true') {
        Write-Warning "El directorio actual no es un repositorio Git."
        return
    }

    # Si no se indica Query: explorador interactivo fzf en todo el historial o solicitar texto
    if (-not $Query) {
        if (Get-Command fzf -ErrorAction SilentlyContinue) {
            $selected = git log --all --oneline --color=always -n 250 2>$null |
                fzf --ansi --preview "git show --stat --color=always {1}; echo ''; git show --color=always {1}" --preview-window=right:65%:wrap --header="[Enter] Ver en detalle | [ESC] Salir | Escribe para filtrar"
            if (-not $selected) {
                return
            }
            $hash = ($selected.Trim() -split '\s+')[0]
            if ($Nvim) {
                vshow $hash
            } else {
                gshow $hash
            }
            return
        } else {
            $Query = Read-Host "Introduce número de ticket o texto a buscar en Git"
            if (-not $Query) { return }
        }
    }

    # Obtener hashes coincidentes en todas las ramas
    $matchingHashes = if ($Code) {
        @(git log --all -S "$Query" --format="%h" 2>$null)
    } else {
        @(git log --all -i "--grep=$Query" --format="%h" 2>$null)
    }

    if ($matchingHashes.Count -eq 0) {
        Write-Host "● No se encontraron commits con '$Query' $(if ($Code) { "en el código" } else { "en los mensajes" }) (buscado en todas las ramas)." -ForegroundColor Yellow
        if (-not $Code) {
            Write-Host "Tip: Si el texto está dentro de los archivos modificados, prueba con: gfind '$Query' -Code" -ForegroundColor DarkGray
        }
        return
    }

    # Abrir directamente en Neovim (-v / -Nvim)
    if ($Nvim) {
        if ($matchingHashes.Count -eq 1) {
            vshow $matchingHashes[0]
            return
        }
        if (Get-Command fzf -ErrorAction SilentlyContinue) {
            $logCmd = if ($Code) {
                git log --all -S "$Query" --oneline --color=always 2>$null
            } else {
                git log --all -i "--grep=$Query" --oneline --color=always 2>$null
            }
            $selected = $logCmd | fzf --ansi --preview "git show --stat --color=always {1}; echo ''; git show --color=always {1}" --preview-window=right:65%:wrap --header="Selecciona commit para abrir en Neovim"
            if ($selected) {
                $h = ($selected.Trim() -split '\s+')[0]
                vshow $h
            }
            return
        } else {
            Write-Host "Se encontraron $($matchingHashes.Count) commits. Abriendo el más reciente ($($matchingHashes[0])) en Neovim..." -ForegroundColor Cyan
            vshow $matchingHashes[0]
            return
        }
    }

    # Modo interactivo fzf (-Interactive / -fzf)
    if ($Interactive) {
        if (Get-Command fzf -ErrorAction SilentlyContinue) {
            $logCmd = if ($Code) {
                git log --all -S "$Query" --oneline --color=always 2>$null
            } else {
                git log --all -i "--grep=$Query" --oneline --color=always 2>$null
            }
            $selected = $logCmd | fzf --ansi --preview "git show --stat --color=always {1}; echo ''; git show --color=always {1}" --preview-window=right:65%:wrap --header="[Enter] Ver en detalle | [ESC] Salir"
            if ($selected) {
                $hash = ($selected.Trim() -split '\s+')[0]
                gshow $hash
            }
            return
        }
    }

    # Solo nombres de archivo modificados
    if ($Files) {
        if ($Code) {
            git log --all -S "$Query" --name-only --format="%C(yellow)commit %h%C(reset) %s" --color=always
        } else {
            git log --all -i "--grep=$Query" --name-only --format="%C(yellow)commit %h%C(reset) %s" --color=always
        }
        return
    }

    # Estadísticas de líneas (+/-) y archivos
    if ($Stat) {
        if ($Code) {
            git log --all -S "$Query" --stat --color=always
        } else {
            git log --all -i "--grep=$Query" --stat --color=always
        }
        return
    }

    # Salida por defecto en consola: lista formateada y coloreada
    Write-Host "`n┌─ Commits encontrados para " -NoNewline -ForegroundColor Cyan
    Write-Host "'$Query'" -NoNewline -ForegroundColor Yellow
    Write-Host " ($(if ($Code) { "en código" } else { "en mensajes" }) - todas las ramas) ─┐" -ForegroundColor Cyan

    if ($Code) {
        git log --all -S "$Query" --color=always --format="%C(auto)%h%d %C(yellow)%ad %C(green)%an%C(reset) %s" --date=short
    } else {
        git log --all -i "--grep=$Query" --color=always --format="%C(auto)%h%d %C(yellow)%ad %C(green)%an%C(reset) %s" --date=short
    }

    Write-Host "└──────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
    Write-Host "Tip: Usa 'gshow <hash>' para ver cambios detallados o 'vshow <hash>' para abrir en Neovim.`n" -ForegroundColor DarkGray
}

Set-Alias gsearch    gfind
Set-Alias git-find   gfind
Set-Alias git-search gfind


