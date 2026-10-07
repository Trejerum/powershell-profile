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
#   codex-radar, cxradar   - Monitor y digest en tiempo real del estado de agentes activos
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

    $finalArgs = @()
    if ($ArgumentList -notcontains '--no-daemon') {
        $finalArgs += '--no-daemon'
    }
    if ($ArgumentList -and $ArgumentList.Count -gt 0) {
        $finalArgs += $ArgumentList
    }

    & $exe @finalArgs
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
                    & $exe --no-daemon resume $selectedId
                    return
                }
            } else {
                Write-Host "● Cancelado por el usuario." -ForegroundColor DarkGray
                return
            }
        } else {
            Write-Host "▶ Reanudando la sesión más reciente de Codex (--last)...`n" -ForegroundColor DarkCyan
            & $exe --no-daemon resume --last
            return
        }
    }

    # Caso 2: El usuario pasó un número (ej. cxresume 1)
    if ($Target -match '^\d+$') {
        $targetIdx = [int]$Target
        $found = $convs | Where-Object { $_.Index -eq $targetIdx }
        if ($found) {
            Write-Host "▶ Reanudando hilo [$($found.Index)]: '$($found.Titulo)' ($($found.IDShort))...`n" -ForegroundColor DarkCyan
            & $exe --no-daemon resume $found.ID
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
        & $exe --no-daemon resume $first.ID
    } else {
        Write-Host "▶ Intentando reanudar sesión '$Target' en Codex...`n" -ForegroundColor DarkCyan
        & $exe --no-daemon resume $Target
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
    & $exe --no-daemon review
}
Set-Alias cxreview codex-review
Set-Alias cx-review codex-review

function codex-apply {
    <#
    .SYNOPSIS
        Aplica el diff más reciente o por Task ID generado por Codex al árbol de trabajo de Git.
    .EXAMPLE
        codex-apply
        cxapply
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$TaskId
    )

    $exe = Get-CodexExe
    if (-not $exe) {
        Write-Warning "Codex CLI ('codex.exe') no se encontró."
        return
    }

    Write-Host "▶ Aplicando parche de Codex con 'git apply'..." -ForegroundColor Cyan
    if ($TaskId) {
        & $exe --no-daemon apply $TaskId
    } else {
        & $exe --no-daemon apply
    }
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

    $callArgs = @("--no-daemon", "exec")
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

    & $exe --no-daemon doctor
}
Set-Alias cxdoctor codex-doctor

function Get-CodexRadar {
    <#
    .SYNOPSIS
        Monitor y digest en tiempo real del estado de los agentes de Codex activos (VS Code / CLI).
    .DESCRIPTION
        Inspecciona de forma pasiva y no bloqueante los rollouts más recientes en ~/.codex/sessions/,
        extrayendo el estado actual (Completado / En progreso), último prompt del usuario,
        última respuesta del asistente y tokens consumidos.
        
        Diseñado con tolerancia a fallos completa: si ~/.codex no existe o no hay sesiones,
        retorna limpiamente sin generar excepciones ni alterar el rendimiento del perfil.
    .PARAMETER Count
        Número de agentes / sesiones recientes a inspeccionar (por defecto 3).
    .PARAMETER Filter
        Filtro opcional por título o UUID de la conversación.
    .PARAMETER Full
        Muestra los textos completos sin truncar.
    .PARAMETER Json
        Retorna la salida como cadena JSON estructurada (ideal para orquestadores y Antigravity).
    .PARAMETER Raw
        Retorna los objetos PSCustomObject directamente en el pipeline de PowerShell.
    .EXAMPLE
        Get-CodexRadar
        cxradar
        cxradar 5
        cxradar -Json
        cxradar "Service Principal" -Full
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [int]$Count = 3,

        [Parameter(Position = 1)]
        [string]$Filter,

        [switch]$Full,
        [switch]$Json,
        [switch]$Raw
    )

    $codexDir = Join-Path $HOME ".codex"
    $sessionsDir = Join-Path $codexDir "sessions"
    if (-not (Test-Path -LiteralPath $sessionsDir)) {
        if ($Json) { return "[]" }
        if ($Raw) { return @() }
        Write-Host "● No se encontraron sesiones activas de Codex en ~/.codex/sessions." -ForegroundColor DarkGray
        return
    }

    $indexMap = @{}
    $indexPath = Join-Path $codexDir "session_index.jsonl"
    if (Test-Path -LiteralPath $indexPath) {
        try {
            [System.IO.File]::ReadAllLines($indexPath, [System.Text.Encoding]::UTF8) | ForEach-Object {
                try {
                    $d = $_ | ConvertFrom-Json
                    if ($d.id -and $d.thread_name) { $indexMap[$d.id] = $d.thread_name.Trim() }
                } catch {}
            }
        } catch {}
    }

    try {
        $files = [System.IO.Directory]::EnumerateFiles($sessionsDir, "rollout-*.jsonl", [System.IO.SearchOption]::AllDirectories)
        $fileList = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        foreach ($f in $files) {
            $fileList.Add([System.IO.FileInfo]::new($f))
        }
        $fileList.Sort({ param($a, $b) $b.LastWriteTimeUtc.CompareTo($a.LastWriteTimeUtc) })
    } catch {
        if ($Json) { return "[]" }
        if ($Raw) { return @() }
        return
    }

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $idx = 1

    foreach ($f in $fileList) {
        $threadId = $null
        if ($f.Name -match 'rollout-.*-([0-9a-fA-F\-]{36})\.jsonl$') {
            $threadId = $matches[1]
        }

        $title = if ($threadId -and $indexMap.ContainsKey($threadId)) { $indexMap[$threadId] } else { "(Sin título)" }

        # Aplicar filtro si se especificó
        if ($Filter) {
            $matchFilter = ($title -like "*$Filter*") -or ($threadId -like "*$Filter*")
            if (-not $matchFilter) { continue }
        }

        $lastAssistant = ""
        $lastUser = ""
        $status = "Completado"
        $tokens = 0

        try {
            $fs = [System.IO.File]::Open($f.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $bytesToRead = [Math]::Min($fs.Length, 262144)
                $fs.Seek(-$bytesToRead, [System.IO.SeekOrigin]::End) | Out-Null
                $buffer = New-Object byte[] $bytesToRead
                $read = $fs.Read($buffer, 0, $bytesToRead)
                $text = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
                $rawLines = $text -split "`r?`n"

                $foundComplete = $false
                $foundStarted = $false

                for ($i = $rawLines.Count - 1; $i -ge 0; $i--) {
                    $line = $rawLines[$i].Trim()
                    if (-not $line -or -not $line.StartsWith("{")) { continue }
                    try {
                        $j = $line | ConvertFrom-Json
                        if (-not $foundComplete -and -not $foundStarted) {
                            if ($j.payload.type -eq "task_complete") {
                                $foundComplete = $true
                                $status = "Completado"
                            } elseif ($j.payload.type -eq "task_started") {
                                $foundStarted = $true
                                $status = "En progreso..."
                            }
                        }
                        if (-not $lastAssistant -and $j.payload.type -eq "message" -and $j.payload.role -eq "assistant") {
                            $lastAssistant = (($j.payload.content | ForEach-Object { $_.text }) -join "`n").Trim()
                        }
                        if (-not $lastUser -and $j.payload.type -eq "message" -and $j.payload.role -eq "user") {
                            $rawU = (($j.payload.content | ForEach-Object { $_.text }) -join "`n").Trim()
                            if ($rawU -match '(?s)## My request:\s*(.*)') {
                                $lastUser = $matches[1].Trim()
                            } else {
                                $lastUser = $rawU
                            }
                        }
                        if ($tokens -eq 0 -and $j.type -eq "token_usage_record") {
                            $tokens = $j.payload.usage.total_tokens
                        }
                    } catch {}
                    if ($lastAssistant -and $lastUser -and ($foundComplete -or $foundStarted)) { break }
                }
            } finally {
                $fs.Dispose()
            }
        } catch {}

        $diff = (Get-Date) - $f.LastWriteTime
        $relTime = if ($diff.TotalMinutes -lt 1) { "hace unos seg" }
                   elseif ($diff.TotalMinutes -lt 60) { "hace $([int]$diff.TotalMinutes)m" }
                   elseif ($diff.TotalHours -lt 24) { "hace $([int]$diff.TotalHours)h" }
                   else { "hace $([int]$diff.TotalDays)d" }

        $item = [PSCustomObject]@{
            Index          = $idx
            ID             = $threadId
            IDShort        = if ($threadId) { $threadId.Substring(0, 8) } else { "N/A" }
            Titulo         = $title
            Estado         = $status
            Modificado     = $f.LastWriteTime
            ModificadoStr  = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            TiempoRelativo = $relTime
            Tokens         = $tokens
            UltimoPrompt   = $lastUser
            UltimaResp     = $lastAssistant
            Archivo        = $f.FullName
        }

        $results.Add($item)
        $idx++
        if ($results.Count -ge $Count) { break }
    }

    if ($Json) {
        return ($results | ConvertTo-Json -Depth 5)
    }

    if ($Raw) {
        return ,$results.ToArray()
    }

    if ($results.Count -eq 0) {
        Write-Host "● No se encontraron conversaciones coincidentes en ~/.codex." -ForegroundColor DarkGray
        return
    }

    Write-Host "`n=== [ Codex Radar ] - Agentes Activos ($($results.Count)) ===`n" -ForegroundColor DarkCyan
    foreach ($r in $results) {
        $idxStr = " [$($r.Index)]".PadRight(5)
        Write-Host $idxStr -NoNewline -ForegroundColor Yellow

        if ($r.Estado -eq "Completado") {
            Write-Host "✔ $($r.Estado) " -NoNewline -ForegroundColor Green
        } elseif ($r.Estado -eq "En progreso...") {
            Write-Host "◐ $($r.Estado) " -NoNewline -ForegroundColor Yellow
        } else {
            Write-Host "○ $($r.Estado) " -NoNewline -ForegroundColor DarkGray
        }

        Write-Host "| $($r.Titulo)" -ForegroundColor White
        Write-Host "     ID: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($r.IDShort)... " -NoNewline -ForegroundColor DarkCyan
        Write-Host "($($r.TiempoRelativo) - $($r.Modificado.ToString('HH:mm:ss'))) " -NoNewline -ForegroundColor DarkGray
        if ($r.Tokens -gt 0) {
            Write-Host "Tokens: $($r.Tokens)" -ForegroundColor DarkMagenta
        } else {
            Write-Host ""
        }

        if ($r.UltimoPrompt) {
            Write-Host "     Usuario:   " -NoNewline -ForegroundColor DarkYellow
            if ($Full) {
                Write-Host $r.UltimoPrompt -ForegroundColor Gray
            } else {
                $pClean = ($r.UltimoPrompt -replace '\s+', ' ').Trim()
                $pLen = [Math]::Min(110, $pClean.Length)
                Write-Host ($pClean.Substring(0, $pLen) + $(if ($pClean.Length -gt 110) { "..." } else { "" })) -ForegroundColor Gray
            }
        }

        if ($r.UltimaResp) {
            Write-Host "     Respuesta: " -NoNewline -ForegroundColor Cyan
            if ($Full) {
                Write-Host $r.UltimaResp -ForegroundColor White
            } else {
                $rClean = ($r.UltimaResp -replace '\s+', ' ').Trim()
                $rLen = [Math]::Min(140, $rClean.Length)
                Write-Host ($rClean.Substring(0, $rLen) + $(if ($rClean.Length -gt 140) { "..." } else { "" })) -ForegroundColor White
            }
        }
        Write-Host ""
    }

    Write-Host "Tip: Usa 'cxresume [n]' para reanudar cualquier hilo en tu terminal.`n" -ForegroundColor DarkGray
}
Set-Alias cxradar Get-CodexRadar
Set-Alias cx-radar Get-CodexRadar
Set-Alias codex-radar Get-CodexRadar
Set-Alias cxstatus Get-CodexRadar

# Inicializar resolución en segundo plano para registrar ruta en PATH
$null = Get-CodexExe
