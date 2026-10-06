# ==============================================================================
# 0. CONFIGURACIÓN DEL ENTORNO & CODIFICACIÓN
# ==============================================================================
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# Editor predeterminado (Neovim) para Git y herramientas de consola
if (Get-Command nvim -ErrorAction SilentlyContinue) {
    $env:EDITOR     = 'nvim'
    $env:VISUAL     = 'nvim'
    $env:GIT_EDITOR = 'nvim'
}

# Priorizar módulos locales de dotfiles y purgar rutas de OneDrive de PSModulePath
if ($global:ProfileDir) {
    $localMods = Join-Path $global:ProfileDir "Modules"
    if (Test-Path -LiteralPath $localMods) {
        $cleanPaths = $env:PSModulePath -split ';' | Where-Object { $_ -notmatch 'OneDrive.*WindowsPowerShell\\Modules' -and $_ -ne $localMods }
        $env:PSModulePath = (($localMods, $cleanPaths) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) -join ';'
    }
}

# ==============================================================================
# INTEGRACIÓN CON PSREADLINE (HISTORIAL & ATAJOS DE CONSOLA)
# ==============================================================================
if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue

    # Búsqueda contextual en el historial de comandos (filtrar por prefijo escrito)
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

    # Edición visual de la línea de comandos con Neovim (Ctrl+X, Ctrl+E)
    Set-PSReadLineKeyHandler -Chord 'Ctrl+x,Ctrl+e' -Function ViEditVisually

    # Atajos mejorados de navegación y edición de palabras
    Set-PSReadLineKeyHandler -Chord 'Ctrl+Backspace' -Function BackwardKillWord -ErrorAction SilentlyContinue
    Set-PSReadLineKeyHandler -Chord 'Ctrl+Delete'    -Function KillWord -ErrorAction SilentlyContinue

    # Predictive IntelliSense & Autosuggestions (requiere PSReadLine 2.2+)
    $psrlModule = Get-Module PSReadLine
    if ($psrlModule -and $psrlModule.Version -ge [Version]'2.2.0') {
        try {
            Set-PSReadLineOption -PredictionSource History
            Set-PSReadLineOption -PredictionViewStyle InlineView
            Set-PSReadLineKeyHandler -Key F2 -Function SwitchPredictionView
        } catch { }
    }
}