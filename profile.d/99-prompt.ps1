# ==============================================================================
# 7. PROMPT PERSONALIZADO (Estado de Git + SQL Server + Cronómetro + Diagnóstico)
# ==============================================================================

$global:PromptLastHistoryId = -1

function prompt {
    $lastSuccess  = $?
    $lastExitCode = $LASTEXITCODE

    # 1. Ruta acortada con soporte para carpeta de usuario (~) y compactación de niveles profundos
    $loc = $ExecutionContext.SessionState.Path.CurrentLocation.ProviderPath
    $homeDir = $HOME.TrimEnd('\', '/')
    $displayPath = $loc
    if ($displayPath.StartsWith($homeDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        $displayPath = "~" + $displayPath.Substring($homeDir.Length)
    }

    # Si la ruta tiene más de 38 caracteres y más de 4 niveles, colapsar niveles intermedios con '…'
    $parts = $displayPath -split '[\\/]'
    if ($displayPath.Length -gt 38 -and $parts.Count -gt 4) {
        $prefix = $parts[0]
        $leafs  = $parts[($parts.Count - 3)..($parts.Count - 1)] -join '\'
        $displayPath = "$prefix\…\$leafs"
    }

    Write-Host "PS " -NoNewline -ForegroundColor DarkCyan
    Write-Host $displayPath -NoNewline -ForegroundColor White

    # 2. Indicador de estado de Git en vivo (posh-git)
    if (Get-Command Write-VcsStatus -ErrorAction SilentlyContinue) {
        $gitStatus = Write-VcsStatus
        if ($gitStatus) {
            Write-Host $gitStatus -NoNewline
        }
    }

    # 3. Indicador de estado de conexión persistente a SQL Server
    if ($global:SqlSession -and $global:SqlSession.State -eq 'Open') {
        $db = $global:SqlSession.Database
        $profileTag = if ($global:SqlActiveProfile) { "$($global:SqlActiveProfile):$db" } else { $db }
        Write-Host " [$profileTag ⚡]" -ForegroundColor Green -NoNewline
    }

    # 4. Cronómetro de ejecución para comandos largos (>= 2 segundos)
    $lastHist = Get-History -Count 1 -ErrorAction SilentlyContinue
    if ($lastHist -and $lastHist.Id -ne $global:PromptLastHistoryId) {
        $global:PromptLastHistoryId = $lastHist.Id
        $elapsed = $lastHist.EndExecutionTime - $lastHist.StartExecutionTime
        if ($elapsed.TotalSeconds -ge 2.0) {
            $secStr = if ($elapsed.TotalSeconds -lt 60) {
                "{0:N1}s" -f $elapsed.TotalSeconds
            } else {
                "{0}m {1:N0}s" -f [int]$elapsed.TotalMinutes, ($elapsed.TotalSeconds % 60)
            }
            Write-Host " [⏱ $secStr]" -ForegroundColor DarkYellow -NoNewline
        }
    }

    # 5. Indicador de fallo en el comando anterior
    if (-not $lastSuccess) {
        $codeTag = if ($lastExitCode -and $lastExitCode -ne 0) { " $lastExitCode" } else { "" }
        Write-Host " [✖$codeTag]" -ForegroundColor Red -NoNewline
    }

    # 6. Símbolo del prompt con color según estado
    if ($lastSuccess) {
        Write-Host " >" -NoNewline -ForegroundColor DarkCyan
    } else {
        Write-Host " >" -NoNewline -ForegroundColor Red
    }

    return " "
}