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
}
