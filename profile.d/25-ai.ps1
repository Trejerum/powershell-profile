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
