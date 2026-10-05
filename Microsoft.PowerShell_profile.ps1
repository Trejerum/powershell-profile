# ==============================================================================
# PERFIL DE POWERSHELL (BOOTSTRAP MODULAR)
# ==============================================================================
# Este archivo actua como cargador principal. El perfil esta modularizado en la
# carpeta 'profile.d/' para garantizar maxima mantenibilidad y aislamiento:
#
#   profile.d/00-env.ps1         - Codificacion UTF-8, variables de entorno y PSReadLine
#   profile.d/10-navigation.ps1  - Atajos de carpetas, proyectos y recarga
#   profile.d/15-notes.ps1       - Gestor de notas, diario developer, captura y Ripgrep
#   profile.d/20-git.ps1         - Alias de Git, posh-git, vmod, vd y hub de repos (repos)
#   profile.d/25-ai.ps1          - Asistente IA (Gemini / Antigravity CLI), gai, ask-cmd
#   profile.d/26-codex.ps1       - Integración OpenAI Codex CLI y sesiones VS Code (cx, cxchats, cxresume)
#   profile.d/30-sql.ps1         - ADO.NET SQL Toolkit, q, sesiones y autocompletado
#   profile.d/40-utils.ps1       - Herramientas de sistema, red, procesos e historial
#   profile.d/50-help.ps1        - Centro de mando interactivo (phelp, ?p)
#   profile.d/99-prompt.ps1      - Prompt interactivo (estado Git + SQL Server)
# ==============================================================================

$script:ProfileDir = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} elseif ($PROFILE -and [string]::IsNullOrWhiteSpace($PROFILE) -eq $false -and (Test-Path -LiteralPath $PROFILE)) {
    Split-Path -Parent $PROFILE
} else {
    Join-Path ([Environment]::GetFolderPath('MyDocuments')) "WindowsPowerShell"
}
$global:ProfileDir = $script:ProfileDir
$script:ProfileD   = Join-Path -Path $script:ProfileDir -ChildPath "profile.d"

if (Test-Path -Path $script:ProfileD) {
    Get-ChildItem -Path "$script:ProfileD\*.ps1" | Sort-Object Name | ForEach-Object {
        try {
            . $_.FullName
        }
        catch {
            Write-Warning "Error al cargar modulo $($_.Name): $_"
        }
    }
}

# Carga de perfil local opcional (personalizaciones y atajos de máquina, no rastreados en Git)
$script:LocalProfile = Join-Path -Path $script:ProfileDir -ChildPath "profile.local.ps1"
if (Test-Path -LiteralPath $script:LocalProfile) {
    try {
        . $script:LocalProfile
    }
    catch {
        Write-Warning "Error al cargar modulo local profile.local.ps1: $_"
    }
}

