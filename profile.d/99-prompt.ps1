# ==============================================================================
# 7. PROMPT PERSONALIZADO (Estado de Git + SQL Server)
# ==============================================================================

function prompt {
    $loc = $ExecutionContext.SessionState.Path.CurrentLocation
    Write-Host "PS $loc" -NoNewline

    # Indicador de estado de Git (posh-git)
    if (Get-Command Write-VcsStatus -ErrorAction SilentlyContinue) {
        $gitStatus = Write-VcsStatus
        if ($gitStatus) {
            Write-Host $gitStatus -NoNewline
        }
    }

    # Indicador de estado de conexión persistente a SQL Server
    if ($global:SqlSession -and $global:SqlSession.State -eq 'Open') {
        $db = $global:SqlSession.Database
        $profileTag = if ($global:SqlActiveProfile) { "$($global:SqlActiveProfile):$db" } else { $db }
        Write-Host " [$profileTag ⚡]" -ForegroundColor Green -NoNewline
    }

    return "> "
}
