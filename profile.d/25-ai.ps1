# ==============================================================================
# 25-AI: ASISTENTE DE IA EN TERMINAL (DESACOPLADO)
# ==============================================================================
# Este módulo proporciona comandos de asistencia en lenguaje natural en la terminal.
# Está diseñado con un backend desacoplado (Invoke-AICompletion) para que el proveedor
# de IA (actualmente Antigravity CLI / agy) pueda intercambiarse fácilmente por
# cualquier otro servicio en el futuro (OpenAI, Ollama, Claude, etc.) sin tocar
# la interfaz de usuario.
# Consulta 'docs/ai-setup.md' para detalles de configuración y autenticación.
# ==============================================================================

# Proveedor configurado: "agy" (por defecto) u otros en el futuro
$global:AIProvider = if ($env:AI_PROVIDER) { $env:AI_PROVIDER } else { "agy" }

function Invoke-AICompletion {
    <#
    .SYNOPSIS
        Función adaptadora de backend de IA desacoplada.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [string]$SystemInstruction,

        [switch]$Fast
    )

    if ($global:AIProvider -ieq "agy") {
        if (-not (Get-Command agy -ErrorAction SilentlyContinue)) {
            Write-Warning "Antigravity CLI ('agy.exe') no se encuentra instalado o en el PATH."
            Write-Host "Consulta la guía de instalación y autenticación en 'docs/ai-setup.md'." -ForegroundColor DarkGray
            return $null
        }

        $fullPrompt = if ($SystemInstruction) {
            "$SystemInstruction`n`nConsulta:`n$Prompt"
        } else {
            $Prompt
        }

        $effort = if ($Fast) { "low" } else { "medium" }
        try {
            $output = agy -p $fullPrompt --effort $effort
            return ($output -join "`r`n").Trim()
        } catch {
            Write-Error "Error al invocar el proveedor de IA (agy): $_"
            return $null
        }
    } else {
        Write-Warning "Proveedor de IA '$global:AIProvider' no soportado actualmente."
        return $null
    }
}

function ask-cmd {
    <#
    .SYNOPSIS
        Traduce una consulta en lenguaje natural al comando exacto de PowerShell.
    .EXAMPLE
        ?? como listar archivos de mas de 100MB modificados hoy
        ?? buscar procesos que consumen mas memoria
        ask-cmd "como exportar un objeto a json formateado"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true, Position = 0)]
        [string[]]$Query
    )

    $queryText = $Query -join " "
    if (-not $queryText.Trim()) { return }

    Write-Host "🤖 Consultando asistente IA..." -ForegroundColor Cyan

    $system = "Eres un experto en PowerShell 5.1 en Windows. El usuario te pedirá una acción en lenguaje natural. Tu tarea es devolver ÚNICAMENTE el comando o bloque de código de PowerShell ejecutable correspondiente. NO agregues explicaciones, NO agregues introducciones, y NO uses bloques de código markdown (```). Devuelve exclusivamente el código PowerShell puro y limpio."

    $result = Invoke-AICompletion -Prompt $queryText -SystemInstruction $system -Fast
    if (-not $result) { return }

    $cleanCmd = $result -replace '^```(powershell)?\r?\n?', '' -replace '\r?\n?```$', ''
    $cleanCmd = $cleanCmd.Trim()

    Write-Host "`n┌─ 💡 Comando sugerido ─────────────────────────────────────┐" -ForegroundColor Green
    Write-Host "  $cleanCmd" -ForegroundColor Yellow
    Write-Host "└───────────────────────────────────────────────────────────┘`n" -ForegroundColor Green

    Write-Host "¿Qué deseas hacer? " -NoNewline -ForegroundColor Cyan
    Write-Host "[E]jecutar  " -NoNewline -ForegroundColor Green
    Write-Host "[C]opiar al portapapeles  " -NoNewline -ForegroundColor Yellow
    Write-Host "[S]alir (por defecto): " -NoNewline -ForegroundColor DarkGray

    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
    Write-Host "$key`n"

    if ($key -ieq 'e') {
        Write-Host "▶ Ejecutando: $cleanCmd`n" -ForegroundColor DarkCyan
        Invoke-Expression $cleanCmd
    } elseif ($key -ieq 'c') {
        Set-Clipboard -Value $cleanCmd
        Write-Host "[OK] Comando copiado al portapapeles listo para pegar." -ForegroundColor Green
    }
}
Set-Alias '??' ask-cmd

function explain-error {
    <#
    .SYNOPSIS
        Analiza el último error ocurrido en la sesión de PowerShell y explica causa y solución.
    .EXAMPLE
        explain-error
        why-error
    #>
    [CmdletBinding()]
    param()

    if ($global:Error.Count -eq 0) {
        Write-Host "[OK] No hay ningún error registrado en la sesión actual." -ForegroundColor Green
        return
    }

    $lastErr = $global:Error[0]
    $errSummary = "Mensaje: $($lastErr.Exception.Message)`nCategoría: $($lastErr.CategoryInfo)`nLínea: $($lastErr.InvocationInfo.Line)`nScript: $($lastErr.InvocationInfo.ScriptName)"

    Write-Host "🔍 Analizando último error con IA..." -ForegroundColor Cyan

    $system = "Eres un asistente de depuración para Windows PowerShell 5.1. Analiza el error proporcionado y responde en español en MÁXIMO 3 líneas concisas: 1) Causa directa del error, 2) Solución recomendada exacta."

    $diagnosis = Invoke-AICompletion -Prompt $errSummary -SystemInstruction $system -Fast
    if (-not $diagnosis) { return }

    Write-Host "`n┌─ 🩺 Diagnóstico del Error ────────────────────────────────┐" -ForegroundColor Red
    Write-Host $diagnosis -ForegroundColor White
    Write-Host "└───────────────────────────────────────────────────────────┘`n" -ForegroundColor Red
}
Set-Alias why-error explain-error
Set-Alias perror explain-error

function gai {
    <#
    .SYNOPSIS
        Analiza los cambios en stage de Git (git diff --staged) y propone un commit convencional.
    .EXAMPLE
        gai
    #>
    [CmdletBinding()]
    param()

    $isRepo = git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $isRepo -ne "true") {
        Write-Warning "El directorio actual no es un repositorio de Git."
        return
    }

    $stagedDiff = git diff --staged
    if (-not $stagedDiff -or -not ($stagedDiff -join "").Trim()) {
        Write-Warning "No hay cambios en el stage (usa 'ga <archivos>' primero antes de ejecutar 'gai')."
        return
    }

    $diffText = ($stagedDiff -join "`n")
    if ($diffText.Length -gt 4000) {
        $diffText = $diffText.Substring(0, 4000) + "`n... (diff truncado por longitud)"
    }

    Write-Host "🤖 Analizando cambios staged con IA..." -ForegroundColor Cyan

    $system = "Eres un generador de mensajes de commit bajo la convención 'Conventional Commits' (feat, fix, docs, style, refactor, test, chore). Analiza el git diff proporcionado y devuelve ÚNICAMENTE una propuesta de mensaje de commit en español en formato 'tipo(alcance): descripción breve'. NO incluyas markdown, NO incluyas explicaciones."

    $commitMsg = Invoke-AICompletion -Prompt $diffText -SystemInstruction $system -Fast
    if (-not $commitMsg) { return }

    $cleanMsg = ($commitMsg -replace '^```\r?\n?', '' -replace '\r?\n?```$', '').Trim()

    Write-Host "`n┌─ 📝 Propuesta de Commit ──────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "  $cleanMsg" -ForegroundColor Yellow
    Write-Host "└───────────────────────────────────────────────────────────┘`n" -ForegroundColor Cyan

    Write-Host "¿Qué deseas hacer? " -NoNewline -ForegroundColor Cyan
    Write-Host "[A]ceptar y commitear  " -NoNewline -ForegroundColor Green
    Write-Host "[C]opiar al portapapeles  " -NoNewline -ForegroundColor Yellow
    Write-Host "[S]alir (por defecto): " -NoNewline -ForegroundColor DarkGray

    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
    Write-Host "$key`n"

    if ($key -ieq 'a') {
        git commit -m "$cleanMsg"
    } elseif ($key -ieq 'c') {
        Set-Clipboard -Value $cleanMsg
        Write-Host "[OK] Mensaje copiado al portapapeles listo para usar." -ForegroundColor Green
    }
}

# ==============================================================================
# GESTIÓN Y HISTORIAL DE CONVERSACIONES (ANTIGRAVITY CLI)
# ==============================================================================
function Get-AgyBrainDir {
    $brain = Join-Path $HOME ".gemini\antigravity-cli\brain"
    if (Test-Path -LiteralPath $brain) { return $brain }
    return $null
}

function Get-AgyConversations {
    param([int]$Limit = 30)

    $brainDir = Get-AgyBrainDir
    if (-not $brainDir) { return @() }

    $dirs = Get-ChildItem -LiteralPath $brainDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $Limit

    $list = @()
    foreach ($d in $dirs) {
        $id = $d.Name
        $date = $d.LastWriteTime
        $logPath = Join-Path $d.FullName ".system_generated\logs\transcript.jsonl"
        $title = "Sin mensaje inicial"

        if (Test-Path -LiteralPath $logPath) {
            $firstLine = Get-Content -LiteralPath $logPath -TotalCount 1 -ErrorAction SilentlyContinue
            if ($firstLine) {
                try {
                    $jsonObj = ConvertFrom-Json $firstLine
                    if ($jsonObj.content -match '(?s)<USER_REQUEST>\s*(.*?)\s*</USER_REQUEST>') {
                        $raw = $matches[1] -replace '\r?\n', ' '
                        $title = if ($raw.Length -gt 70) { $raw.Substring(0, 67) + "..." } else { $raw }
                    } elseif ($jsonObj.content) {
                        $raw = $jsonObj.content -replace '\r?\n', ' '
                        $title = if ($raw.Length -gt 70) { $raw.Substring(0, 67) + "..." } else { $raw }
                    }
                } catch { }
            }
        }

        $list += [PSCustomObject]@{
            Index    = $list.Count + 1
            ID       = $id
            Fecha    = $date
            FechaStr = $date.ToString("yyyy-MM-dd HH:mm")
            Titulo   = $title
        }
    }
    return $list
}

function agy-history {
    <#
    .SYNOPSIS
        Muestra la lista de conversaciones recientes de Antigravity CLI (agy).
    .EXAMPLE
        agy-history
        agy-history 15
        achats
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [int]$Count = 10,

        [Parameter(Position = 1)]
        [string]$Filter
    )

    $convs = Get-AgyConversations -Limit 50
    if ($convs.Count -eq 0) {
        Write-Host "● No se encontraron conversaciones previas de Antigravity." -ForegroundColor DarkGray
        return
    }

    if ($Filter) {
        $convs = $convs | Where-Object { $_.Titulo -like "*$Filter*" -or $_.ID -like "*$Filter*" }
    }

    $convs = $convs | Select-Object -First $Count

    Write-Host "`n=== Historial de Conversaciones de Antigravity ($($convs.Count)) ===`n" -ForegroundColor DarkCyan
    foreach ($c in $convs) {
        $idxStr = "[$($c.Index)]".PadRight(5)
        Write-Host " $idxStr" -NoNewline -ForegroundColor Yellow
        Write-Host "$($c.FechaStr)  " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($c.ID.Substring(0, 8))...  " -NoNewline -ForegroundColor DarkCyan
        Write-Host $c.Titulo -ForegroundColor White
    }
    Write-Host "`nTip: Usa 'agy-resume [n]' (ej. 'aresume 1') para reanudar cualquier conversación.`n" -ForegroundColor DarkGray
}
Set-Alias achats agy-history
Set-Alias agy-chats agy-history

function agy-resume {
    <#
    .SYNOPSIS
        Reanuda una conversación de Antigravity CLI por índice, ID o menú difuso.
    .EXAMPLE
        agy-resume          # Abre selector fzf o reanuda la última
        agy-resume 1        # Reanuda la conversación más reciente
        agy-resume 8f79c406 # Reanuda por ID parcial o completo
        aresume
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Target
    )

    if (-not (Get-Command agy -ErrorAction SilentlyContinue)) {
        Write-Warning "Antigravity CLI ('agy.exe') no se encuentra en el PATH."
        return
    }

    $convs = Get-AgyConversations -Limit 40
    if ($convs.Count -eq 0) {
        Write-Host "● No hay conversaciones previas registradas." -ForegroundColor DarkGray
        return
    }

    # Caso 1: Sin argumentos -> fzf o reanudar última
    if (-not $Target) {
        if (Get-Command fzf -ErrorAction SilentlyContinue) {
            $lines = foreach ($c in $convs) {
                "[$($c.Index.ToString().PadLeft(2))] $($c.FechaStr) | $($c.ID) | $($c.Titulo)"
            }
            $selected = $lines | fzf --prompt="Reanudar Conversación > " --height=40% --reverse
            if ($selected) {
                if ($selected -match '\|\s*([a-f0-9\-]{36})\s*\|') {
                    $targetId = $matches[1]
                    Write-Host "🚀 Reanudando conversación: $targetId" -ForegroundColor Cyan
                    agy --conversation $targetId
                    return
                }
            } else {
                return
            }
        } else {
            Write-Host "🚀 Reanudando la conversación más reciente (agy -c)..." -ForegroundColor Cyan
            agy -c
            return
        }
    }

    # Caso 2: Argumento numérico (índice 1, 2, 3...)
    if ($Target -match '^\d+$') {
        $idx = [int]$Target
        $match = $convs | Where-Object { $_.Index -eq $idx }
        if ($match) {
            Write-Host "🚀 Reanudando conversación [$idx]: $($match.ID)" -ForegroundColor Cyan
            agy --conversation $match.ID
            return
        } else {
            Write-Warning "No existe ninguna conversación con el índice [$idx]."
            return
        }
    }

    # Caso 3: Argumento de texto (ID completo o parcial)
    $match = $convs | Where-Object { $_.ID -like "$Target*" } | Select-Object -First 1
    if ($match) {
        Write-Host "🚀 Reanudando conversación: $($match.ID)" -ForegroundColor Cyan
        agy --conversation $match.ID
    } else {
        Write-Warning "No se encontró ninguna conversación que coincida con '$Target'."
    }
}
Set-Alias aresume agy-resume
Set-Alias agy-c agy-resume
