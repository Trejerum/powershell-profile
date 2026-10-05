# ==============================================================================
# INTEGRACIÓN OPENAI CODEX CLI (CODEX & VS CODE)
# ==============================================================================
# Proporciona integración nativa con OpenAI Codex CLI (empaquetado con la extensión
# oficial de VS Code 'openai.chatgpt' o en el PATH) y acceso bidireccional a las
# conversaciones e hilos compartidos entre VS Code y PowerShell.
#
# Comandos principales:
#   codex, cx              - Invoca el CLI interactivo de Codex (o subcomandos)
#   codex-history, cxchats - Historial cronológico de hilos (VS Code & CLI)
#   codex-resume, cxresume - Reanudar hilo por índice [1], ID o selector difuso (fzf)
#   codex-review, cxreview - Revisión de código automatizada del repo Git actual
#   codex-apply, cxapply   - Aplica el diff más reciente producido por Codex
#   codex-exec, cxexec     - Ejecución no interactiva de tareas con Codex
#   codex-doctor, cxdoctor - Diagnóstico de estado, auth y sandbox de Codex
# ==============================================================================

$script:CodexExeCache = $null

function Get-CodexExe {
    <#
    .SYNOPSIS
        Localiza la ruta al ejecutable de Codex CLI (codex.exe).
    .DESCRIPTION
        Busca codex.exe con la siguiente prioridad:
        1. Caché de sesión de PowerShell.
        2. Variable de entorno personalizada $env:CODEX_EXE.
        3. Comandos disponibles en el PATH del sistema.
        4. Detección dinámica en extensiones de VS Code (~/.vscode/extensions/openai.chatgpt*).
    #>
    [CmdletBinding()]
    param()

    # 1. Caché en memoria
    if ($script:CodexExeCache -and (Test-Path -LiteralPath $script:CodexExeCache)) {
        return $script:CodexExeCache
    }

    # 2. Variable de entorno personalizada
    if ($env:CODEX_EXE -and (Test-Path -LiteralPath $env:CODEX_EXE)) {
        $script:CodexExeCache = $env:CODEX_EXE
        return $script:CodexExeCache
    }

    # 3. Comprobar si ya existe en PATH
    $cmd = Get-Command codex.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
        $script:CodexExeCache = $cmd.Source
        return $script:CodexExeCache
    }

    # 4. Búsqueda dinámica en extensiones de VS Code
    $vsExtDir = Join-Path $HOME ".vscode\extensions"
    if (Test-Path -LiteralPath $vsExtDir) {
        $extDirs = Get-ChildItem -Path $vsExtDir -Filter "openai.chatgpt*" -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending

        foreach ($dir in $extDirs) {
            $candidate = Join-Path $dir.FullName "bin\windows-x86_64\codex.exe"
            if (Test-Path -LiteralPath $candidate) {
                $script:CodexExeCache = $candidate
                
                # Exponer el directorio en el PATH del proceso para submódulos o scripts hijos
                $binDir = Split-Path -Parent $candidate
                $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Process")
                if ($currentPath -split ';' -notcontains $binDir) {
                    [Environment]::SetEnvironmentVariable("PATH", "$binDir;$currentPath", "Process")
                }
                return $candidate
            }
        }
    }

    return $null
}

function codex {
    <#
    .SYNOPSIS
        Ejecuta el CLI oficial de OpenAI Codex en modo interactivo o con argumentos.
    .EXAMPLE
        codex
        cx "Refactoriza este método para que sea asíncrono"
        cx --version
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ArgumentList
    )

    $exe = Get-CodexExe
    if (-not $exe) {
        Write-Warning "Codex CLI ('codex.exe') no se encontró."
        Write-Host "Asegúrate de tener instalada la extensión oficial 'Codex – OpenAI''s coding agent' en VS Code o añade 'codex.exe' al PATH." -ForegroundColor DarkGray
        return
    }

    if ($ArgumentList -and $ArgumentList.Count -gt 0) {
        & $exe @ArgumentList
    } else {
        & $exe
    }
}
Set-Alias cx codex

function Get-CodexSessions {
    <#
    .SYNOPSIS
        Obtiene el listado estructurado de conversaciones registradas en ~/.codex/session_index.jsonl.
    #>
    [CmdletBinding()]
    param(
        [int]$Limit = 50
    )

    $indexPath = Join-Path $HOME ".codex\session_index.jsonl"
    if (-not (Test-Path -LiteralPath $indexPath)) {
        return @()
    }

    $lines = [System.IO.File]::ReadAllLines($indexPath, [System.Text.Encoding]::UTF8)
    $list = New-Object System.Collections.ArrayList
    $idx = 1

    # Recorrer en orden inverso (más reciente primero)
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        try {
            $data = $line | ConvertFrom-Json
            if ($data.id -and $data.thread_name) {
                $dt = [DateTime]$data.updated_at
                $localDt = $dt.ToLocalTime()
                $null = $list.Add([PSCustomObject]@{
                    Index    = $idx++
                    ID       = $data.id
                    IDShort  = $data.id.Substring(0, [Math]::Min(8, $data.id.Length))
                    Fecha    = $localDt
                    FechaStr = $localDt.ToString("yyyy-MM-dd HH:mm")
                    Titulo   = $data.thread_name.Trim()
                })
            }
        } catch {}

        if ($list.Count -ge $Limit) { break }
    }

    return ,$list.ToArray()
}

function codex-history {
    <#
    .SYNOPSIS
        Muestra el historial cronológico de hilos de Codex compartidos entre VS Code y la CLI.
    .EXAMPLE
        codex-history
        cxchats 15
        cxchats 10 "Adobe"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [int]$Count = 10,

        [Parameter(Position = 1)]
        [string]$Filter
    )

    $convs = Get-CodexSessions -Limit 100
    if ($convs.Count -eq 0) {
        Write-Host "● No se encontraron conversaciones previas de Codex en ~/.codex." -ForegroundColor DarkGray
        return
    }

    if ($Filter) {
        $convs = $convs | Where-Object { $_.Titulo -like "*$Filter*" -or $_.ID -like "*$Filter*" }
    }

    $convs = $convs | Select-Object -First $Count

    Write-Host "`n=== Historial de Conversaciones de Codex ($($convs.Count)) ===`n" -ForegroundColor DarkCyan
    foreach ($c in $convs) {
        $idxStr = "[$($c.Index)]".PadRight(5)
        Write-Host " $idxStr" -NoNewline -ForegroundColor Yellow
        Write-Host "$($c.FechaStr)  " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($c.IDShort)...  " -NoNewline -ForegroundColor DarkCyan
        Write-Host $c.Titulo -ForegroundColor White
    }
    Write-Host "`nTip: Usa 'cxresume [n]' (ej. 'cxresume 1') para reanudar cualquier hilo de VS Code o CLI en la terminal.`n" -ForegroundColor DarkGray
}
Set-Alias cxchats codex-history
Set-Alias cx-chats codex-history
Set-Alias codex-chats codex-history

function codex-resume {
    <#
    .SYNOPSIS
        Reanuda una conversación de Codex por índice, ID o selector difuso interactivo (fzf).
    .EXAMPLE
        codex-resume        # Reanuda la sesión más reciente o abre fzf si está disponible
        cxresume 1          # Reanuda el hilo más reciente
        cxresume 01a0fc19   # Reanuda por UUID
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Target
    )

    $exe = Get-CodexExe
    if (-not $exe) {
        Write-Warning "Codex CLI ('codex.exe') no se encontró."
        return
    }

    $convs = Get-CodexSessions -Limit 50
    if ($convs.Count -eq 0) {
        Write-Host "● No hay conversaciones previas de Codex registradas." -ForegroundColor DarkGray
        return
    }

    # Caso 1: Sin argumentos -> fzf o reanudar última con --last
    if (-not $Target) {
        if (Get-Command fzf -ErrorAction SilentlyContinue) {
            $fzfLines = foreach ($c in $convs) {
                "[$($c.Index)] $($c.FechaStr) | $($c.ID) | $($c.Titulo)"
            }
            $selected = $fzfLines | fzf --prompt="Codex Resume > " --height=40% --reverse --header="Selecciona un hilo de VS Code / Codex para reanudar en terminal"
            if ($selected) {
                if ($selected -match '\|\s*([a-f0-9\-]{36})\s*\|') {
                    $selectedId = $matches[1]
                    Write-Host "▶ Reanudando hilo de Codex: $selectedId`n" -ForegroundColor DarkCyan
                    & $exe resume $selectedId
                    return
                }
            } else {
                Write-Host "● Cancelado por el usuario." -ForegroundColor DarkGray
                return
            }
        } else {
            Write-Host "▶ Reanudando la sesión más reciente de Codex (--last)...`n" -ForegroundColor DarkCyan
            & $exe resume --last
            return
        }
    }

    # Caso 2: El usuario pasó un número (ej. cxresume 1)
    if ($Target -match '^\d+$') {
        $targetIdx = [int]$Target
        $found = $convs | Where-Object { $_.Index -eq $targetIdx }
        if ($found) {
            Write-Host "▶ Reanudando hilo [$($found.Index)]: '$($found.Titulo)' ($($found.IDShort))...`n" -ForegroundColor DarkCyan
            & $exe resume $found.ID
            return
        } else {
            Write-Warning "No se encontró ninguna conversación con el índice [$targetIdx]. Usa 'cxchats' para ver los índices disponibles."
            return
        }
    }

    # Caso 3: El usuario pasó un ID o prefijo de ID
    $matching = $convs | Where-Object { $_.ID -like "$Target*" -or $_.ID -eq $Target }
    if ($matching) {
        $first = $matching[0]
        Write-Host "▶ Reanudando hilo: '$($first.Titulo)' ($($first.IDShort))...`n" -ForegroundColor DarkCyan
        & $exe resume $first.ID
    } else {
        Write-Host "▶ Intentando reanudar sesión '$Target' en Codex...`n" -ForegroundColor DarkCyan
        & $exe resume $Target
    }
}
Set-Alias cxresume codex-resume
Set-Alias cx-resume codex-resume
Set-Alias codex-c codex-resume

function codex-review {
    <#
    .SYNOPSIS
        Ejecuta una revisión automatizada de código con Codex contra los cambios del repo Git actual.
    .EXAMPLE
        codex-review
        cxreview
    #>
    [CmdletBinding()]
    param()

    $exe = Get-CodexExe
    if (-not $exe) {
        Write-Warning "Codex CLI ('codex.exe') no se encontró."
        return
    }

    $gitCheck = git rev-parse --is-inside-work-tree 2>$null
    if ($gitCheck -ne 'true') {
        Write-Warning "El directorio actual no es un repositorio Git. 'codex review' requiere un repo Git."
        return
    }

    Write-Host "🔍 Iniciando revisión de código con Codex..." -ForegroundColor Cyan
    & $exe review
}
Set-Alias cxreview codex-review
Set-Alias cx-review codex-review

function codex-apply {
    <#
    .SYNOPSIS
        Aplica el diff más reciente generado por Codex al árbol de trabajo de Git.
    .EXAMPLE
        codex-apply
        cxapply
    #>
    [CmdletBinding()]
    param()

    $exe = Get-CodexExe
    if (-not $exe) {
        Write-Warning "Codex CLI ('codex.exe') no se encontró."
        return
    }

    Write-Host "▶ Aplicando último parche de Codex con 'git apply'..." -ForegroundColor Cyan
    & $exe apply
}
Set-Alias cxapply codex-apply
Set-Alias cx-apply codex-apply

function codex-exec {
    <#
    .SYNOPSIS
        Ejecuta instrucciones en modo no interactivo con Codex.
    .EXAMPLE
        cxexec "Genera una prueba unitaria para este script"
        cxexec -Json "Analiza este archivo"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Prompt,

        [switch]$Json
    )

    $exe = Get-CodexExe
    if (-not $exe) {
        Write-Warning "Codex CLI ('codex.exe') no se encontró."
        return
    }

    $callArgs = @("exec")
    if ($Json) { $callArgs += "--json" }
    $callArgs += $Prompt

    & $exe @callArgs
}
Set-Alias cxexec codex-exec
Set-Alias cx-exec codex-exec

function codex-doctor {
    <#
    .SYNOPSIS
        Ejecuta el diagnóstico de salud, autenticación, base de datos y sandbox de Codex.
    .EXAMPLE
        codex-doctor
        cxdoctor
    #>
    [CmdletBinding()]
    param()

    $exe = Get-CodexExe
    if (-not $exe) {
        Write-Warning "Codex CLI ('codex.exe') no se encontró."
        return
    }

    & $exe doctor
}
Set-Alias cxdoctor codex-doctor

# Inicializar resolución en segundo plano para registrar ruta en PATH
$null = Get-CodexExe
