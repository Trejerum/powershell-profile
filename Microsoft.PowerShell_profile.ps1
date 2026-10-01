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
# 1. UTILIDADES GENERALES
# ==============================================================================

# Copiar contenido al portapapeles desde tubería o parámetro
function cb {
    param(
        [Parameter(ValueFromPipeline = $true)]
        $InputObject
    )
    begin {
        $items = @()
    }
    process {
        if ($null -ne $InputObject) {
            $items += $InputObject
        }
    }
    end {
        if ($items.Count -gt 0) {
            $text = ($items | Out-String).Trim()
            if (-not [string]::IsNullOrEmpty($text)) {
                Set-Clipboard -Value $text
                Write-Host "Copiado al portapapeles." -ForegroundColor DarkGray
                return
            }
        }
        Write-Warning "No había contenido de texto para copiar."
    }
}

# Buscar y matar procesos que bloquean puertos TCP específicos (ej. 4200, 5000, 7000)
function kill-port {
    <#
    .SYNOPSIS
        Busca y finaliza los procesos que estén escuchando en uno o varios puertos TCP.
    .EXAMPLE
        kill-port 4200
        kp 5001, 7000
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [int[]]$Port
    )

    process {
        foreach ($p in $Port) {
            $conns = Get-NetTCPConnection -LocalPort $p -ErrorAction SilentlyContinue
            if (-not $conns) {
                Write-Host "● Puerto $p : No hay ningún proceso escuchando." -ForegroundColor DarkGray
                continue
            }

            $pids = @($conns | Select-Object -ExpandProperty OwningProcess -Unique)
            foreach ($procId in $pids) {
                if ($procId -le 4) {
                    Write-Warning "El puerto $p está retenido por un proceso del sistema (PID $procId)."
                    continue
                }

                $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
                $procName = if ($proc) { $proc.ProcessName } else { "Desconocido" }

                try {
                    Stop-Process -Id $procId -Force -ErrorAction Stop
                    Write-Host "✓ Puerto $p liberado: Finalizado proceso [$procName] (PID: $procId)" -ForegroundColor Green
                }
                catch {
                    taskkill /F /PID $procId 2>$null
                    Write-Host "✓ Puerto $p liberado mediante taskkill (PID: $procId)" -ForegroundColor Yellow
                }
            }
        }
    }
}
Set-Alias kp kill-port

# Wrapper inteligente para Neovim: abre archivos o consume datos de la tubería (pipeline)
function v {
    <#
    .SYNOPSIS
        Wrapper inteligente para Neovim. Abre archivos o consume la tubería (pipeline) en un buffer.
    .EXAMPLE
        v Program.cs
        v .
        gs | v
        q "SELECT TOP 10 * FROM Articulos" | v
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        $InputObject,

        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Path
    )

    begin {
        $isPipe = $PSCmdlet.MyInvocation.ExpectingInput
        $pipeItems = @()
    }
    process {
        if ($isPipe -and $null -ne $InputObject) {
            $pipeItems += $InputObject
        }
    }
    end {
        if ($isPipe -and $pipeItems.Count -gt 0) {
            $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "nvim_pipe_$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).txt")
            $text = ($pipeItems | Out-String).TrimEnd()
            [System.IO.File]::WriteAllText($tempFile, $text, [System.Text.UTF8Encoding]::new($false))
            try {
                nvim $tempFile
            }
            finally {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
        elseif ($Path -and $Path.Count -gt 0) {
            nvim @Path
        }
        else {
            nvim
        }
    }
}

# Busca texto con Ripgrep y abre los resultados en Neovim dentro de la lista Quickfix (:copen)
function vrg {
    <#
    .SYNOPSIS
        Busca texto con Ripgrep y abre los resultados en Neovim dentro de la lista Quickfix (:copen).
    .EXAMPLE
        vrg "Get-ActiveSql"
        vrg "kill-port" src/
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Pattern,

        [Parameter(Position = 1)]
        [string]$Path = "."
    )

    if (-not (Get-Command rg -ErrorAction SilentlyContinue)) {
        Write-Error "Ripgrep ('rg') no está instalado o no se encuentra en el PATH."
        return
    }

    $tempQf = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "nvim_qf_$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).txt")
    try {
        & rg --vimgrep $Pattern $Path | Out-File -FilePath $tempQf -Encoding UTF8
        if (-not (Test-Path -LiteralPath $tempQf) -or (Get-Item -LiteralPath $tempQf).Length -eq 0) {
            Write-Host "● No se encontraron coincidencias para '$Pattern'." -ForegroundColor Yellow
            return
        }
        nvim -q $tempQf -c "copen"
    }
    finally {
        Remove-Item -LiteralPath $tempQf -Force -ErrorAction SilentlyContinue
    }
}

# ==============================================================================
# 2. NAVEGACIÓN RÁPIDA (PROYECTOS)
# ==============================================================================

$script:SgaRoot = Join-Path $HOME "Documentos\Proyectos\SGA"

function sga     { Set-Location $script:SgaRoot }
function rsga    { Set-Location (Join-Path $script:SgaRoot "RSGA") }
function rsga2   { Set-Location (Join-Path $script:SgaRoot "RSGA_2") }
function rsga3   { Set-Location (Join-Path $script:SgaRoot "RSGA_3") }
function profile { Set-Location (Split-Path -Parent $PROFILE) }
function notes   { Set-Location (Join-Path $HOME "Documentos\Notes") }
function ep      { nvim $PROFILE }
function en      { nvim (Join-Path $env:LOCALAPPDATA "nvim") }
Set-Alias edit-profile ep
Set-Alias edit-nvim    en

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
function gco   { git checkout $args }
function ga    { git add . $args }
function glog  { git log --oneline --graph --decorate -n 10 $args }
function gme   { git for-each-ref --format="%(committername) | %(refname:short)" refs/remotes/ | Select-String "diego.corral" }

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

# ==============================================================================
# 4. AYUDA RÁPIDA DEL PERFIL
# ==============================================================================

function Show-ProfileHelp {
    [CmdletBinding()]
    param([string]$Filter)

    $commands = @(
        # Navegación
        [PSCustomObject]@{ Categoria = "Navegación"; Comando = "sga";   Descripcion = "Ir a la raíz de SGA" }
        [PSCustomObject]@{ Categoria = "Navegación"; Comando = "rsga";  Descripcion = "Ir a RSGA" }
        [PSCustomObject]@{ Categoria = "Navegación"; Comando = "rsga2"; Descripcion = "Ir a RSGA_2" }
        [PSCustomObject]@{ Categoria = "Navegación"; Comando = "rsga3";   Descripcion = "Ir a RSGA_3" }
        [PSCustomObject]@{ Categoria = "Navegación"; Comando = "profile"; Descripcion = "Ir a la carpeta del perfil de PowerShell" }
        [PSCustomObject]@{ Categoria = "Navegación"; Comando = "notes";   Descripcion = "Ir a la carpeta de Notas" }
        [PSCustomObject]@{ Categoria = "Navegación"; Comando = "ep";      Descripcion = "Abre `$PROFILE en Neovim (alias: edit-profile)" }
        [PSCustomObject]@{ Categoria = "Navegación"; Comando = "en";      Descripcion = "Abre config de Neovim en Neovim (alias: edit-nvim)" }

        # Utilidades
        [PSCustomObject]@{ Categoria = "General";    Comando = "v";         Descripcion = "Wrapper Neovim: abre archivo o consume pipeline (<salida> | v)" }
        [PSCustomObject]@{ Categoria = "General";    Comando = "vrg";       Descripcion = "Busca con Ripgrep y abre resultados en Neovim Quickfix" }
        [PSCustomObject]@{ Categoria = "General";    Comando = "cb";        Descripcion = "Copia texto o pipeline al portapapeles" }
        [PSCustomObject]@{ Categoria = "General";    Comando = "kill-port"; Descripcion = "Libera puertos TCP bloqueados (alias: kp, ej. kp 4200)" }

        # Atajos Git
        [PSCustomObject]@{ Categoria = "Git";        Comando = "g";            Descripcion = "Atajo directo a 'git'" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "posh-git";     Descripcion = "Autocompletado git con <Tab> y estado en prompt [rama +~-]" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gs";           Descripcion = "git status -sb" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "ga";    Descripcion = "git add ." }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gp/gf"; Descripcion = "git pull / git fetch" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gpush"; Descripcion = "git push" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gpsup"; Descripcion = "git push --set-upstream origin <rama> (alias: gpu, gpushu)" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gco";   Descripcion = "git checkout <rama/archivo>" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "glog";  Descripcion = "Historial gráfico compacto (últimos 10)" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gme";   Descripcion = "Commits remotos de Diego Corral" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gss";   Descripcion = "Stash con timestamp y rama (incluye untracked)" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gsl";   Descripcion = "Listar stashes coloreados" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gsp";           Descripcion = "Aplicar stash (ej. 'gsp' o 'gsp 2')" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "vmod";          Descripcion = "Lista cambios y abre modificados en Neovim (alias: vdiff, -List, -Splits)" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "agy-review-pr"; Descripcion = "Revisa PR con Antigravity (ej. agy-review-pr <rama> [base] [-Print])" }

        # SQL Server Toolkit
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "q";          Descripcion = "Ejecuta SQL/.sql (switches: -Grid, -Clip, -Csv, -Json, -DryRun, -Timeout N)" }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "qconnect";   Descripcion = "Conecta sesión persistente en BD (ej. qconnect [Serv] [BD])" }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "qdisc";      Descripcion = "Desconecta sesión persistente (alias de qdisconnect)" }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "use";        Descripcion = "Cambia BD activa y refresca caché (ej. use <BD>)" }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "desc";       Descripcion = "Describe columnas y tipos de una tabla (ej. desc <tabla>)" }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "find-table"; Descripcion = "Busca tablas/vistas por patrón (ej. find-table <patrón>)" }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "count";      Descripcion = "Recuento ultrarrápido sin scan (sys.dm_db_partition_stats)" }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "who";        Descripcion = "Monitor de sesiones activas y bloqueos (sys.dm_exec_requests)" }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "see";        Descripcion = "Inspecciona DDL/código de vista/SP/función (ej. see <objeto> [-Clip])" }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "see-idx";    Descripcion = "Inspecciona índices y columnas clave (ej. see-idx <tabla>)" }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "find-col";   Descripcion = "Busca en qué tablas existe una columna (ej. find-col <col>)" }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "find-code";  Descripcion = "Busca texto en SPs, vistas, funciones y triggers (alias: find-sp)" }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "q2excel";    Descripcion = "Ejecuta consulta SQL y la abre directamente en Excel (alias: qexcel)" }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "open-sql";   Descripcion = "Abre DDL de SP/vista directamente en Neovim (ej. open-sql <obj>)" }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "vsql";       Descripcion = "Scratchpad SQL en Neovim con opción de ejecución con 'q'" }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "qfmt";       Descripcion = "Formatea consulta SQL con indentaciones (ej. qfmt <query> [-Clip])" }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "qlog";       Descripcion = "Historial persistente de consultas (ej. qlog [filtro] [-Last 20])" }
    )

    if ($Filter) {
        $commands = $commands | Where-Object {
            $_.Comando -like "*$Filter*" -or $_.Descripcion -like "*$Filter*" -or $_.Categoria -like "*$Filter*"
        }
    }

    Write-Host "`n=== Comandos del `$PROFILE ===`n" -ForegroundColor DarkCyan

    $groups = $commands | Group-Object Categoria
    foreach ($group in $groups) {
        Write-Host " [$($group.Name)]" -ForegroundColor Yellow
        foreach ($item in $group.Group) {
            $cmd = $item.Comando.PadRight(14)
             Write-Host "   $cmd" -NoNewline -ForegroundColor Green
             Write-Host " -> " -NoNewline -ForegroundColor DarkGray
             Write-Host $item.Descripcion -ForegroundColor White
         }
         Write-Host ""
     }
 }
 
 Set-Alias phelp Show-ProfileHelp
 Set-Alias '?p'  Show-ProfileHelp
 
 # ==============================================================================
 # 5. SQL SERVER TOOLKIT (ADO.NET + PowerShell)
 # ==============================================================================

# Variables de entorno y defaults de conexión
$global:SqlDefaultServer   = 'PORT1220\SQL_SERVER'
$global:SqlDefaultDatabase = 'SGA'
$global:SqlSession         = $null
$global:SqlTableCache      = @()

# Configuración por si alguna vez usas Invoke-Sqlcmd directamente
$PSDefaultParameterValues['Invoke-Sqlcmd:ServerInstance']         = $global:SqlDefaultServer
$PSDefaultParameterValues['Invoke-Sqlcmd:Database']               = $global:SqlDefaultDatabase
$PSDefaultParameterValues['Invoke-Sqlcmd:TrustServerCertificate'] = $true
$PSDefaultParameterValues['Invoke-Sqlcmd:QueryTimeout']           = 120
$PSDefaultParameterValues['Invoke-Sqlcmd:ConnectionTimeout']      = 30

function Update-SqlTableCache {
    <#
    .SYNOPSIS
        Actualiza la caché en memoria con los nombres de tablas y vistas de SQL Server.
    #>
    [CmdletBinding()]
    param()

    $conn = $null
    $needClose = $false

    if ($global:SqlSession -and $global:SqlSession.State -eq 'Open') {
        $conn = $global:SqlSession
    }
    else {
        $cs = "Server=$global:SqlDefaultServer;Database=$global:SqlDefaultDatabase;Integrated Security=True;TrustServerCertificate=True;Connection Timeout=5;"
        $conn = New-Object System.Data.SqlClient.SqlConnection($cs)
        try {
            $conn.Open()
            $needClose = $true
        }
        catch {
            Write-Warning "No se pudo conectar a SQL Server para actualizar la caché de tablas: $_"
            return
        }
    }

    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
SELECT 
    TABLE_SCHEMA + '.' + TABLE_NAME AS FullName,
    TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_SCHEMA NOT IN ('sys', 'INFORMATION_SCHEMA')
  AND TABLE_TYPE IN ('BASE TABLE', 'VIEW')
ORDER BY TABLE_SCHEMA, TABLE_NAME
"@
        $cmd.CommandTimeout = 15

        $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
        $dt = New-Object System.Data.DataTable
        [void]$da.Fill($dt)

        $list = New-Object System.Collections.Generic.List[string]($dt.Rows.Count * 2)
        if ($dt.Rows.Count -gt 5000) {
            foreach ($row in $dt.Rows) {
                $list.Add($row['FullName'])
            }
        }
        else {
            foreach ($row in $dt.Rows) {
                $list.Add($row['FullName'])
                $list.Add($row['TABLE_NAME'])
            }
        }
        $global:SqlTableCache = @($list | Sort-Object -Unique)
    }
    catch {
        Write-Warning "Error al consultar INFORMATION_SCHEMA.TABLES: $_"
    }
    finally {
        if ($needClose -and $conn) {
            try {
                if ($conn.State -eq 'Open') { $conn.Close() }
            }
            catch { }
            finally {
                $conn.Dispose()
            }
        }
    }
}

function qdisconnect {
    <#
    .SYNOPSIS
        Cierra y destruye la conexión persistente activa.
    #>
    [CmdletBinding()]
    param(
        [switch]$Quiet
    )

    if ($global:SqlSession) {
        try {
            if ($global:SqlSession.State -eq 'Open') {
                $global:SqlSession.Close()
            }
        }
        catch { }
        finally {
            $global:SqlSession.Dispose()
            $global:SqlSession = $null
        }
        if (-not $Quiet) {
            Write-Host "[INFO] Sesión desconectada. Modo transitorio activado." -ForegroundColor Yellow
        }
    }
}

Set-Alias -Name qdisc -Value qdisconnect

function qconnect {
    <#
    .SYNOPSIS
        Abre una conexión persistente ultra rápida con SQL Server.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Server = $global:SqlDefaultServer,

        [Parameter(Position = 1)]
        [string]$Database = $global:SqlDefaultDatabase
    )

    qdisconnect -Quiet

    $cs = "Server=$Server;Database=$Database;Integrated Security=True;TrustServerCertificate=True;Connection Timeout=10;"
    try {
        $global:SqlSession = New-Object System.Data.SqlClient.SqlConnection($cs)
        $global:SqlSession.Open()

        # Prevención de transacciones huérfanas
        $initCmd = $global:SqlSession.CreateCommand()
        $initCmd.CommandText = "SET XACT_ABORT ON;"
        $initCmd.CommandTimeout = 5
        [void]$initCmd.ExecuteNonQuery()

        Write-Host "[OK] Conectado a [$Database] en [$Server]" -ForegroundColor Green
        Update-SqlTableCache
    }
    catch {
        $global:SqlSession = $null
        Write-Error "No se pudo conectar a SQL Server: $_"
    }
}

function use {
    <#
    .SYNOPSIS
        Cambia rápidamente de base de datos activa y actualiza la caché de tablas.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Database
    )

    $cleanDb = ($Database.Trim().Trim('"', "'").Trim('[]') -replace '[\0\r\n\t]', '').Replace(']', ']]')

    if ($global:SqlSession -and $global:SqlSession.State -eq 'Open') {
        try {
            $cmd = $global:SqlSession.CreateCommand()
            $cmd.CommandText = "USE [$cleanDb]"
            [void]$cmd.ExecuteNonQuery()
            $global:SqlDefaultDatabase = $cleanDb.Replace(']]', ']')
            Update-SqlTableCache
            Write-Host "● Contexto cambiado a [$($global:SqlDefaultDatabase)]" -ForegroundColor Green
        }
        catch {
            Write-Error "No se pudo cambiar a la base de datos [$cleanDb]: $_"
        }
    }
    else {
        $global:SqlDefaultDatabase = $cleanDb.Replace(']]', ']')
        Write-Host "● Contexto cambiado a [$($global:SqlDefaultDatabase)]" -ForegroundColor Green
    }
}

Register-ArgumentCompleter -CommandName use -ParameterName Database -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $dbs = @()
    try {
        $conn = $null
        $needClose = $false
        if ($global:SqlSession -and $global:SqlSession.State -eq 'Open') {
            $conn = $global:SqlSession
        }
        else {
            $cs = "Server=$global:SqlDefaultServer;Database=master;Integrated Security=True;TrustServerCertificate=True;Connection Timeout=3;"
            $conn = New-Object System.Data.SqlClient.SqlConnection($cs)
            $conn.Open()
            $needClose = $true
        }

        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT name FROM sys.databases WHERE state = 0 ORDER BY name"
        $cmd.CommandTimeout = 5
        $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
        $dt = New-Object System.Data.DataTable
        [void]$da.Fill($dt)

        foreach ($r in $dt.Rows) {
            $dbs += $r['name']
        }

        if ($needClose -and $conn) {
            $conn.Close()
            $conn.Dispose()
        }
    }
    catch { }

    $cleanWord = $wordToComplete.TrimStart('"', "'", '[')
    $dbs | Where-Object { $_ -like "$cleanWord*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
            $_,
            $_,
            'ParameterValue',
            "Base de datos: $_"
        )
    }
}

function q {
    <#
    .SYNOPSIS
        Ejecuta consultas SQL o archivos de script .sql en milisegundos con salvaguardas de salida y exportación.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [Alias('Query', 'Path', 'File', 'Script')]
        [ValidateNotNullOrEmpty()]
        [string]$QueryOrPath,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$RemainingArgs,

        [Parameter()]
        [Alias('Params')]
        [System.Collections.IDictionary]$Parameters,

        [switch]$Grid,          # Abre la ventana gráfica interactiva Out-GridView
        [switch]$Clip,          # Copia el resultado al portapapeles en formato TSV (para Excel)
        [Alias('Csv')]
        [string]$ExportCsv,     # Exporta el resultado a un archivo CSV delimitado por ';'
        [switch]$Json,          # Devuelve los datos en formato JSON (ConvertTo-Json -Depth 3)
        [Alias('DryRun')]
        [switch]$Rollback,      # Ejecuta dentro de BEGIN TRAN...ROLLBACK TRAN reportando filas afectadas sin persistir
        [switch]$All,           # Ignora el límite de seguridad de filas
        [int]$MaxRows = 100,    # Límite por defecto para no congelar la consola
        [int]$Timeout = 120     # Tiempo máximo de espera en segundos para la ejecución de la consulta
    )

    process {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        # 1. Detección automática: archivo en disco vs sentencia SQL en texto plano
        # Recomponer la ruta o consulta si contenía espacios y no se usaron comillas
        $candidate = if ($RemainingArgs -and $RemainingArgs.Count -gt 0) {
            ($QueryOrPath, ($RemainingArgs -join ' ')) -join ' '
        } else {
            $QueryOrPath
        }

        $isFilePath = $false
        $resolvedPath = $null
        $sqlContent = $null
        $gridTitle = $candidate

        # Comprobar si $candidate (o $QueryOrPath) es una ruta válida en disco
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf -ErrorAction SilentlyContinue)) {
            $isFilePath = $true
            $resolvedPath = (Resolve-Path -LiteralPath $candidate).ProviderPath
            $sqlContent = [System.IO.File]::ReadAllText($resolvedPath, [System.Text.Encoding]::UTF8)
            $gridTitle = [System.IO.Path]::GetFileName($resolvedPath)
        }
        elseif ($QueryOrPath -and (Test-Path -LiteralPath $QueryOrPath -PathType Leaf -ErrorAction SilentlyContinue)) {
            $isFilePath = $true
            $resolvedPath = (Resolve-Path -LiteralPath $QueryOrPath).ProviderPath
            $sqlContent = [System.IO.File]::ReadAllText($resolvedPath, [System.Text.Encoding]::UTF8)
            $gridTitle = [System.IO.Path]::GetFileName($resolvedPath)
        }
        elseif ($candidate -and (Test-Path -Path $candidate -PathType Leaf -ErrorAction SilentlyContinue)) {
            $isFilePath = $true
            $resolvedPath = (Resolve-Path -Path $candidate).ProviderPath
            $sqlContent = [System.IO.File]::ReadAllText($resolvedPath, [System.Text.Encoding]::UTF8)
            $gridTitle = [System.IO.Path]::GetFileName($resolvedPath)
        }
        elseif ($QueryOrPath -and (Test-Path -Path $QueryOrPath -PathType Leaf -ErrorAction SilentlyContinue)) {
            $isFilePath = $true
            $resolvedPath = (Resolve-Path -Path $QueryOrPath).ProviderPath
            $sqlContent = [System.IO.File]::ReadAllText($resolvedPath, [System.Text.Encoding]::UTF8)
            $gridTitle = [System.IO.Path]::GetFileName($resolvedPath)
        }
        else {
            # Si parece claramente una ruta a un archivo (.sql o inicio con unidad/carpeta) pero no existe en disco
            $looksLikePath = ($candidate -match '^(?:[a-zA-Z]:\\|\\\\\w+|\.{1,2}[\\/])' -or $candidate.EndsWith('.sql', [System.StringComparison]::OrdinalIgnoreCase)) -and
                             ($candidate -notmatch '(?i)\b(?:SELECT|INSERT|UPDATE|DELETE|EXEC|CREATE|ALTER|DROP|SET|DECLARE|BEGIN)\b')
            if ($looksLikePath) {
                Write-Error "No se encontró el archivo SQL en la ruta: '$candidate'. Verifica que la ruta exista en disco."
                return
            }

            $sqlContent = $candidate
            $gridTitle = $candidate
        }

        if ([string]::IsNullOrWhiteSpace($sqlContent)) {
            Write-Warning "El contenido SQL a ejecutar está vacío."
            return
        }

        # 2. Separador de lotes 'GO' (Crucial en archivos .sql)
        $batches = @([regex]::Split($sqlContent, '(?mi)^\s*GO\s*(?:--.*)?$') |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

        if ($batches.Count -eq 0) {
            Write-Warning "No se encontró ninguna instrucción SQL válida para ejecutar."
            return
        }

        # 2.1 Envoltura DryRun / Rollback
        if ($Rollback) {
            if ($batches.Count -eq 1) {
                $dryRunBatch = @"
SET NOCOUNT OFF;
SET XACT_ABORT ON;
BEGIN TRANSACTION;

$($batches[0])
;

DECLARE @__dryrun_affected INT = @@ROWCOUNT;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
SELECT @__dryrun_affected AS [__DryRunRows__];
"@
                $batches = @($dryRunBatch)
            }
            else {
                # Multi-lote con GO: abrimos transacción en el primer lote y cerramos/capturamos en el último
                $batches[0] = "SET NOCOUNT OFF;`nSET XACT_ABORT ON;`nBEGIN TRANSACTION;`n" + $batches[0]
                $lastIdx = $batches.Count - 1
                $batches[$lastIdx] = $batches[$lastIdx] + ";`nDECLARE @__dryrun_affected INT = @@ROWCOUNT;`nIF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;`nSELECT @__dryrun_affected AS [__DryRunRows__];"
            }
        }

        # 3. Preparación de conexión y salvaguarda contra sockets zombies
        $isTransient = $false
        $conn = $null
        $savedServer = $global:SqlDefaultServer
        $savedDb     = $global:SqlDefaultDatabase
        $isPersistent = ($global:SqlSession -and $global:SqlSession.State -eq 'Open')

        if ($isPersistent) {
            $conn = $global:SqlSession
            if ($conn.DataSource) { $savedServer = $conn.DataSource }
            if ($conn.Database)   { $savedDb     = $conn.Database }
        }
        else {
            $isTransient = $true
            $cs = "Server=$global:SqlDefaultServer;Database=$global:SqlDefaultDatabase;Integrated Security=True;TrustServerCertificate=True;Connection Timeout=10;"
            try {
                $conn = New-Object System.Data.SqlClient.SqlConnection($cs)
                $conn.Open()
                # Prevención de transacciones huérfanas
                $initCmd = $conn.CreateCommand()
                $initCmd.CommandText = "SET XACT_ABORT ON;"
                $initCmd.CommandTimeout = 5
                [void]$initCmd.ExecuteNonQuery()
            }
            catch {
                Write-Error "No se pudo conectar a SQL Server ($global:SqlDefaultServer): $($_.Exception.Message)"
                return
            }
        }

        $dt = New-Object System.Data.DataTable
        $executedSuccessfully = $false
        $maxAttempts = if ($isPersistent) { 2 } else { 1 }

        try {
            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                try {
                    $cmd = $conn.CreateCommand()
                    $cmd.CommandTimeout = $Timeout

                    for ($i = 0; $i -lt $batches.Count; $i++) {
                        $batch = $batches[$i]
                        $cmd.CommandText = $batch
                        $isLastBatch = ($i -eq ($batches.Count - 1))

                        # Cargar parámetros SqlParameter si fueron provistos
                        if ($Parameters -and $Parameters.Count -gt 0) {
                            $cmd.Parameters.Clear()
                            foreach ($pKey in $Parameters.Keys) {
                                $pName = if ($pKey.ToString().StartsWith('@')) { $pKey.ToString() } else { "@$pKey" }
                                $pVal = $Parameters[$pKey]
                                if ($null -eq $pVal) { $pVal = [System.DBNull]::Value }
                                [void]$cmd.Parameters.AddWithValue($pName, $pVal)
                            }
                        }

                        # Detectar si el lote contiene sentencias SELECT que retornan datos
                        $cleanBatch = $batch -replace '(?ms)/\*.*?\*/', '' -replace '(?m)--.*?$', ''
                        $hasSelect = ($cleanBatch -match '(?i)^\s*(?:WITH\s+[\s\S]+?AS\s*\([\s\S]+?\)\s*)?SELECT\b') -or
                                     ($cleanBatch -match '(?i)\bSELECT\b' -and $cleanBatch -notmatch '(?i)^\s*(?:INSERT|UPDATE|DELETE|MERGE|CREATE|ALTER|DROP|SET|USE|TRUNCATE|GRANT|REVOKE)\b') -or
                                     ($cleanBatch -match '(?i);\s*SELECT\b')

                        if ($isLastBatch -or $hasSelect) {
                            $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
                            [void]$da.Fill($dt)
                        }
                        else {
                            [void]$cmd.ExecuteNonQuery()
                        }
                    }

                    $executedSuccessfully = $true
                    break
                }
                catch {
                    $ex = $_.Exception

                    # 1. Rollback preventivo si la conexión sigue abierta y hay transacción activa
                    if ($conn -and $conn.State -eq 'Open') {
                        try {
                            $rbCmd = $conn.CreateCommand()
                            $rbCmd.CommandText = "IF @@TRANCOUNT > 0 ROLLBACK TRAN;"
                            $rbCmd.CommandTimeout = 5
                            [void]$rbCmd.ExecuteNonQuery()
                        }
                        catch { }
                    }

                    # 2. Detección de Socket Zombie / fallo de red/transporte
                    $isNetError = $false
                    $fullErr = if ($ex) { $ex.ToString() } else { "" }
                    if ($fullErr -match '(?i)transport-level|TCP Provider|broken and recovery is not possible|comunicaci[oó]n|10054|10053|10060|semaphore timeout|communication link') {
                        $isNetError = $true
                    }
                    elseif ($ex -is [System.Data.SqlClient.SqlException]) {
                        $netCodes = @(10054, 10053, 233, 64, 121, 10060, 2, 53)
                        foreach ($sqlErr in $ex.Errors) {
                            if ($netCodes -contains $sqlErr.Number) {
                                $isNetError = $true
                                break
                            }
                        }
                    }

                    # Si es error de socket TCP y usamos sesión persistente: reconectar silenciosamente una sola vez
                    if ($isNetError -and $isPersistent -and $attempt -lt $maxAttempts) {
                        qdisconnect -Quiet
                        try {
                            $cs = "Server=$savedServer;Database=$savedDb;Integrated Security=True;TrustServerCertificate=True;Connection Timeout=10;"
                            $global:SqlSession = New-Object System.Data.SqlClient.SqlConnection($cs)
                            $global:SqlSession.Open()

                            $initCmd = $global:SqlSession.CreateCommand()
                            $initCmd.CommandText = "SET XACT_ABORT ON;"
                            $initCmd.CommandTimeout = 5
                            [void]$initCmd.ExecuteNonQuery()

                            $conn = $global:SqlSession
                            $dt.Clear()
                            continue
                        }
                        catch {
                            $global:SqlSession = $null
                            Write-Error "Fallo en reconexión automática tras error de socket TCP: $($_.Exception.Message)"
                            return
                        }
                    }

                    # Si no es un socket zombi o falló el reintento:
                    Write-Error "Error de SQL Server: $($ex.Message)"
                    return
                }
            }
        }
        finally {
            if ($Rollback) {
                if ($conn -and $conn.State -eq 'Open') {
                    try {
                        $cleanCmd = $conn.CreateCommand()
                        $cleanCmd.CommandText = "IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;"
                        $cleanCmd.CommandTimeout = 5
                        [void]$cleanCmd.ExecuteNonQuery()
                    }
                    catch { }
                }
            }
            if ($isTransient -and $conn) {
                try {
                    if ($conn.State -eq 'Open') {
                        $conn.Close()
                    }
                }
                catch { }
                finally {
                    $conn.Dispose()
                }
            }
        }

        if (-not $executedSuccessfully) {
            return
        }

        # 3.1 Historial persistente en segundo plano ($HOME\.sql_history.tsv)
        $sw.Stop()
        $durationMs = $sw.ElapsedMilliseconds
        try {
            $serverLogged = if ($conn -and $conn.DataSource) { $conn.DataSource } else { $global:SqlDefaultServer }
            $dbLogged     = if ($conn -and $conn.Database)   { $conn.Database }   else { $global:SqlDefaultDatabase }
            $sanitizedSql = ($sqlContent -replace "[\r\n\t]+", " ").Trim()
            if ($sanitizedSql.Length -gt 3000) {
                $sanitizedSql = $sanitizedSql.Substring(0, 3000) + " ... [TRUNCATED]"
            }
            $historyFile = Join-Path $HOME ".sql_history.tsv"
            $timestamp   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $logLine     = "$timestamp`t$serverLogged`t$dbLogged`t$durationMs`t$sanitizedSql"
            [System.IO.File]::AppendAllLines($historyFile, [string[]]@($logLine), [System.Text.Encoding]::UTF8)
        }
        catch { }

        # 4. Exportación y renderizado de resultados
        if ($Rollback) {
            $affected = 0
            if ($dt.Rows.Count -gt 0 -and $dt.Columns.Contains('__DryRunRows__')) {
                $val = $dt.Rows[0]['__DryRunRows__']
                if ($null -ne $val -and -not [System.DBNull]::Value.Equals($val)) {
                    $affected = [int]$val
                }
            }
            Write-Host "Modo DryRun: La sentencia afectaría a $affected filas (Cambios revertidos)." -ForegroundColor Yellow
            return
        }

        if ($Json) {
            if ($dt.Rows.Count -eq 0) {
                Write-Warning "La consulta no devolvió filas para convertir a JSON."
                return
            }

            $rows = @(foreach ($row in $dt.Rows) {
                $obj = [ordered]@{}
                foreach ($col in $dt.Columns) {
                    $val = $row[$col]
                    $obj[$col.ColumnName] = if ($null -eq $val -or [System.DBNull]::Value.Equals($val)) { $null } else { $val }
                }
                [pscustomobject]$obj
            })

            return ($rows | ConvertTo-Json -Depth 3)
        }

        if ($Clip) {
            if ($dt.Columns.Count -eq 0) {
                Write-Warning "La consulta no devolvió filas ni columnas para copiar al portapapeles."
                return
            }

            $colNames = @($dt.Columns | ForEach-Object { $_.ColumnName })
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.AppendLine(($colNames -join "`t"))
            foreach ($row in $dt.Rows) {
                $rowVals = foreach ($col in $dt.Columns) {
                    $v = $row[$col]
                    if ($null -eq $v -or [System.DBNull]::Value.Equals($v)) {
                        ""
                    }
                    else {
                        $s = $v.ToString()
                        if ($s -match "[\t\r\n`"]") {
                            '"' + $s.Replace('"', '""') + '"'
                        } else {
                            $s
                        }
                    }
                }
                [void]$sb.AppendLine(($rowVals -join "`t"))
            }
            $clipText = $sb.ToString().TrimEnd()
            try {
                Set-Clipboard -Value $clipText -ErrorAction Stop
            }
            catch {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
                [System.Windows.Forms.Clipboard]::SetText($clipText)
            }
            Write-Host "✓ Copiado al portapapeles (listo para Ctrl+V en Excel)" -ForegroundColor Cyan
            return
        }

        if ($ExportCsv) {
            if ($dt.Columns.Count -eq 0) {
                Write-Warning "La consulta no devolvió filas ni columnas para exportar a CSV."
                return
            }

            $parent = Split-Path $ExportCsv -Parent
            if ($parent -and -not (Test-Path $parent)) {
                [void](New-Item -ItemType Directory -Path $parent -Force)
            }

            $dt | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8 -Delimiter ';'
            Write-Host "✓ Exportado a $ExportCsv" -ForegroundColor Cyan
            return
        }

        if ($Grid) {
            if ($dt.Columns.Count -gt 0) {
                $dt | Out-GridView -Title $gridTitle
            }
            else {
                Write-Host "[OK] Instrucción ejecutada con éxito (sin filas que mostrar en GridView)." -ForegroundColor Green
            }
            return
        }

        if ($dt.Columns.Count -eq 0) {
            Write-Host "[OK] Instrucción(es) ejecutada(s) correctamente." -ForegroundColor Green
            return
        }

        if ($All -or $dt.Rows.Count -le $MaxRows) {
            $dt
        }
        else {
            Write-Warning "Se recuperaron $($dt.Rows.Count) filas. Mostrando las primeras $MaxRows para no saturar la consola."
            Write-Host "Tip: Usa 'q ... -All' para verlas todas o '-Grid' para verlas en ventana interactiva.`n" -ForegroundColor DarkGray
            $dt | Select-Object -First $MaxRows
        }
    }
}

function desc {
    <#
    .SYNOPSIS
        Describe la estructura y columnas de una tabla o vista de SQL Server.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Table,

        [switch]$Grid,
        [switch]$Clip,
        [Alias('Csv')]
        [string]$ExportCsv,
        [switch]$Json
    )

    $clean = ($Table.Trim().Trim('"', "'") -replace '[\0\r\n\t;]', '').Replace("'", "''")
    $schema = $null
    $tableName = $null

    if ($clean -match '^\[?([^.\]]+)\]?\.\[?([^.\]]+)\]?$') {
        $schema = $matches[1].Trim('[]')
        $tableName = $matches[2].Trim('[]')
    }
    else {
        $tableName = $clean.Trim('[]')
    }

    $query = @"
SELECT 
    COLUMN_NAME AS [Columna],
    CASE 
        WHEN DATA_TYPE IN ('varchar', 'nvarchar', 'char', 'nchar', 'binary', 'varbinary') THEN
            DATA_TYPE + '(' + CASE WHEN CHARACTER_MAXIMUM_LENGTH = -1 THEN 'MAX' ELSE CAST(CHARACTER_MAXIMUM_LENGTH AS VARCHAR(10)) END + ')'
        WHEN DATA_TYPE IN ('decimal', 'numeric') THEN
            DATA_TYPE + '(' + CAST(NUMERIC_PRECISION AS VARCHAR(10)) + ',' + CAST(NUMERIC_SCALE AS VARCHAR(10)) + ')'
        WHEN DATA_TYPE IN ('time', 'datetime2', 'datetimeoffset') THEN
            DATA_TYPE + '(' + CAST(DATETIME_PRECISION AS VARCHAR(10)) + ')'
        ELSE DATA_TYPE
    END AS [Tipo],
    IS_NULLABLE AS [Nullable],
    ISNULL(COLUMN_DEFAULT, '') AS [Default]
FROM INFORMATION_SCHEMA.COLUMNS
WHERE (@Schema IS NULL OR TABLE_SCHEMA = @Schema)
  AND TABLE_NAME = @Table
ORDER BY ORDINAL_POSITION
"@

    $qParams = @{
        QueryOrPath = $query
        Parameters  = @{
            Schema = if ($schema) { $schema } else { $null }
            Table  = $tableName
        }
        All         = $true
    }
    if ($Grid)      { $qParams['Grid'] = $true }
    if ($Clip)      { $qParams['Clip'] = $true }
    if ($ExportCsv) { $qParams['ExportCsv'] = $ExportCsv }
    if ($Json)      { $qParams['Json'] = $true }

    q @qParams
}

Register-ArgumentCompleter -CommandName desc -ParameterName Table -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    if ($null -eq $global:SqlTableCache -or $global:SqlTableCache.Count -eq 0) {
        Update-SqlTableCache
    }

    $cleanWord = $wordToComplete.TrimStart('"', "'", '[')
    $global:SqlTableCache | Where-Object { $_ -like "$cleanWord*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
            $_,
            $_,
            'ParameterValue',
            "Tabla/Vista: $_"
        )
    }
}

function find-table {
    <#
    .SYNOPSIS
        Busca tablas y vistas en SQL Server por patrón de nombre.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Pattern,

        [switch]$Grid,
        [switch]$Clip,
        [Alias('Csv')]
        [string]$ExportCsv,
        [switch]$Json
    )

    $cleanPattern = ($Pattern.Trim().Trim('"', "'", '%') -replace '[\0\r\n\t;]', '').Replace("'", "''")
    $query = @"
SELECT 
    TABLE_SCHEMA AS [Esquema],
    TABLE_NAME AS [Tabla],
    TABLE_TYPE AS [Tipo]
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA NOT IN ('sys', 'INFORMATION_SCHEMA')
  AND TABLE_NAME LIKE @Pattern
ORDER BY TABLE_SCHEMA, TABLE_NAME
"@

    $qParams = @{
        QueryOrPath = $query
        Parameters  = @{
            Pattern = "%$cleanPattern%"
        }
        All         = $true
    }
    if ($Grid)      { $qParams['Grid'] = $true }
    if ($Clip)      { $qParams['Clip'] = $true }
    if ($ExportCsv) { $qParams['ExportCsv'] = $ExportCsv }
    if ($Json)      { $qParams['Json'] = $true }

    q @qParams
}

function count {
    <#
    .SYNOPSIS
        Recuento ultrarrápido de filas de una tabla usando metadatos y particiones (0 ms, sin scan).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Table,

        [switch]$Grid,
        [switch]$Clip,
        [Alias('Csv')]
        [string]$ExportCsv,
        [switch]$Json
    )

    $clean = ($Table.Trim().Trim('"', "'") -replace '[\0\r\n\t;]', '').Replace("'", "''")
    $schema = $null
    $tableName = $null

    if ($clean -match '^\[?([^.\]]+)\]?\.\[?([^.\]]+)\]?$') {
        $schema = $matches[1].Trim('[]')
        $tableName = $matches[2].Trim('[]')
    }
    else {
        $tableName = $clean.Trim('[]')
    }

    $query = @"
SELECT 
    s.name AS [Esquema],
    t.name AS [Tabla],
    SUM(p.row_count) AS [TotalFilas]
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.dm_db_partition_stats p ON t.object_id = p.object_id
WHERE p.index_id IN (0, 1)
  AND (@Schema IS NULL OR s.name = @Schema)
  AND t.name = @Table
GROUP BY s.name, t.name
"@

    $qParams = @{
        QueryOrPath = $query
        Parameters  = @{
            Schema = if ($schema) { $schema } else { $null }
            Table  = $tableName
        }
        All         = $true
    }
    if ($Grid)      { $qParams['Grid'] = $true }
    if ($Clip)      { $qParams['Clip'] = $true }
    if ($ExportCsv) { $qParams['ExportCsv'] = $ExportCsv }
    if ($Json)      { $qParams['Json'] = $true }

    q @qParams
}

Register-ArgumentCompleter -CommandName count -ParameterName Table -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    if ($null -eq $global:SqlTableCache -or $global:SqlTableCache.Count -eq 0) {
        Update-SqlTableCache
    }

    $cleanWord = $wordToComplete.TrimStart('"', "'", '[')
    $global:SqlTableCache | Where-Object { $_ -like "$cleanWord*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
            $_,
            $_,
            'ParameterValue',
            "Tabla: $_"
        )
    }
}

function who {
    <#
    .SYNOPSIS
        Monitor de sesiones activas de usuario, bloqueos y consultas en ejecución en SQL Server.
    #>
    [CmdletBinding()]
    param(
        [switch]$Grid,
        [switch]$Clip,
        [Alias('Csv')]
        [string]$ExportCsv,
        [switch]$Json
    )

    $query = @"
SELECT 
    r.session_id AS [SPID],
    r.status AS [Status],
    r.blocking_session_id AS [BlockingSPID],
    ISNULL(r.wait_type, '') AS [WaitType],
    r.wait_time AS [WaitTime (ms)],
    r.cpu_time AS [CPU],
    LEFT(REPLACE(REPLACE(ISNULL(t.text, ''), CHAR(13), ' '), CHAR(10), ' '), 100) AS [SqlText]
FROM sys.dm_exec_requests r
INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.is_user_process = 1
  AND r.session_id <> @@SPID
ORDER BY r.cpu_time DESC
"@

    if ($Grid -or $Clip -or $ExportCsv -or $Json) {
        $qParams = @{ QueryOrPath = $query; All = $true }
        if ($Grid)      { $qParams['Grid'] = $true }
        if ($Clip)      { $qParams['Clip'] = $true }
        if ($ExportCsv) { $qParams['ExportCsv'] = $ExportCsv }
        if ($Json)      { $qParams['Json'] = $true }
        q @qParams
        return
    }

    $res = q $query -All
    if ($null -eq $res -or ($res -is [System.Array] -and $res.Count -eq 0)) {
        Write-Host "● Sin bloqueos ni consultas activas de usuario en este momento." -ForegroundColor DarkGray
        return
    }

    $res
}

function see {
    <#
    .SYNOPSIS
        Inspecciona el código fuente (DDL) de vistas, procedimientos almacenados, funciones y triggers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ObjectName,

        [switch]$Clip
    )

    $clean = ($ObjectName.Trim().Trim('"', "'") -replace '[\0\r\n\t;]', '').Replace("'", "''")
    $query = @"
SELECT OBJECT_DEFINITION(OBJECT_ID(@ObjectName)) AS [Definition]
"@

    $res = q -QueryOrPath $query -Parameters @{ ObjectName = $clean } -All
    $code = $null

    if ($res -is [System.Data.DataTable] -and $res.Rows.Count -gt 0) {
        $val = $res.Rows[0]['Definition']
        if ($val -ne [System.DBNull]::Value) { $code = [string]$val }
    }
    elseif ($res -is [System.Array] -and $res.Count -gt 0) {
        $val = $res[0].Definition
        if ($val) { $code = [string]$val }
    }
    elseif ($res -and $res.PSObject.Properties['Definition']) {
        $val = $res.Definition
        if ($val) { $code = [string]$val }
    }
    elseif ($res -is [System.Data.DataRow]) {
        $val = $res['Definition']
        if ($val -ne [System.DBNull]::Value) { $code = [string]$val }
    }

    if ([string]::IsNullOrWhiteSpace($code)) {
        Write-Host "No se encontró definición para [$ObjectName]" -ForegroundColor Yellow
        return
    }

    if ($Clip) {
        try {
            Set-Clipboard -Value $code -ErrorAction Stop
        }
        catch {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            [System.Windows.Forms.Clipboard]::SetText($code)
        }
        Write-Host "✓ Definición de [$ObjectName] copiada al portapapeles" -ForegroundColor Cyan
        return
    }

    $code
}

Register-ArgumentCompleter -CommandName see -ParameterName ObjectName -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    if ($null -eq $global:SqlTableCache -or $global:SqlTableCache.Count -eq 0) {
        Update-SqlTableCache
    }

    $cleanWord = $wordToComplete.TrimStart('"', "'", '[')
    $global:SqlTableCache | Where-Object { $_ -like "$cleanWord*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
            $_,
            $_,
            'ParameterValue',
            "Objeto SQL: $_"
        )
    }
}

function qlog {
    <#
    .SYNOPSIS
        Consulta el historial persistente de sentencias SQL ejecutadas ($HOME\.sql_history.tsv).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Filter,

        [Parameter(Position = 1)]
        [int]$Last = 20,

        [switch]$All,
        [switch]$Clip
    )

    $historyPath = Join-Path $HOME ".sql_history.tsv"
    if (-not (Test-Path -LiteralPath $historyPath)) {
        Write-Host "● El historial de consultas está vacío ($historyPath)." -ForegroundColor DarkGray
        return
    }

    try {
        $lines = [System.IO.File]::ReadAllLines($historyPath, [System.Text.Encoding]::UTF8)
    }
    catch {
        Write-Warning "No se pudo leer el archivo de historial: $_"
        return
    }

    if ($null -eq $lines -or $lines.Count -eq 0) {
        Write-Host "● El historial de consultas está vacío." -ForegroundColor DarkGray
        return
    }

    $records = foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line.Split("`t")
        if ($parts.Count -lt 5) { continue }

        $recDate   = $parts[0]
        $recServer = $parts[1]
        $recDb     = $parts[2]
        $recMs     = $parts[3]
        $recSql    = $parts[4..($parts.Count - 1)] -join "`t"

        if ($Filter -and ($recSql -notlike "*$Filter*" -and $recDb -notlike "*$Filter*" -and $recServer -notlike "*$Filter*")) {
            continue
        }

        [PSCustomObject]@{
            Fecha       = $recDate
            BaseDatos   = $recDb
            'Duración'  = "${recMs} ms"
            Query       = if ($recSql.Length -gt 70) { $recSql.Substring(0, 67) + "..." } else { $recSql }
            QueryFull   = $recSql
        }
    }

    if ($null -eq $records -or $records.Count -eq 0) {
        Write-Host "● No se encontraron consultas que coincidan con '$Filter'." -ForegroundColor DarkGray
        return
    }

    $out = if ($All) { @($records) } else { @($records | Select-Object -Last $Last) }

    if ($Clip) {
        $clipText = ($out | ForEach-Object { $_.QueryFull }) -join "`n`n"
        try {
            Set-Clipboard -Value $clipText -ErrorAction Stop
        }
        catch {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            [System.Windows.Forms.Clipboard]::SetText($clipText)
        }
        Write-Host "✓ Consultas copiadas al portapapeles." -ForegroundColor Cyan
        return
    }

    $out | Format-Table -Property Fecha, BaseDatos, 'Duración', Query -AutoSize
}

function see-idx {
    <#
    .SYNOPSIS
        Inspecciona los índices y columnas clave de una tabla de SQL Server.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Table,

        [switch]$Grid,
        [switch]$Clip,
        [Alias('Csv')]
        [string]$ExportCsv,
        [switch]$Json
    )

    $clean = ($Table.Trim().Trim('"', "'") -replace '[\0\r\n\t;]', '').Replace("'", "''")
    $schema = $null
    $tableName = $null

    if ($clean -match '^\[?([^.\]]+)\]?\.\[?([^.\]]+)\]?$') {
        $schema = $matches[1].Trim('[]')
        $tableName = $matches[2].Trim('[]')
    }
    else {
        $tableName = $clean.Trim('[]')
    }

    $query = @"
SELECT 
    i.name AS [Indice],
    i.type_desc AS [Tipo],
    CASE WHEN i.is_unique = 1 THEN 'Sí' ELSE 'No' END AS [Unique],
    STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS [Columnas]
FROM sys.indexes i
INNER JOIN sys.tables t ON i.object_id = t.object_id
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE ic.is_included_column = 0
  AND i.type > 0
  AND (@Schema IS NULL OR s.name = @Schema)
  AND t.name = @Table
GROUP BY i.name, i.type_desc, i.is_unique
ORDER BY i.type_desc, i.name
"@

    $qParams = @{
        QueryOrPath = $query
        Parameters  = @{
            Schema = if ($schema) { $schema } else { $null }
            Table  = $tableName
        }
        All         = $true
    }
    if ($Grid)      { $qParams['Grid'] = $true }
    if ($Clip)      { $qParams['Clip'] = $true }
    if ($ExportCsv) { $qParams['ExportCsv'] = $ExportCsv }
    if ($Json)      { $qParams['Json'] = $true }

    q @qParams
}

Register-ArgumentCompleter -CommandName see-idx -ParameterName Table -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    if ($null -eq $global:SqlTableCache -or $global:SqlTableCache.Count -eq 0) {
        Update-SqlTableCache
    }

    $cleanWord = $wordToComplete.TrimStart('"', "'", '[')
    $global:SqlTableCache | Where-Object { $_ -like "$cleanWord*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
            $_,
            $_,
            'ParameterValue',
            "Tabla: $_"
        )
    }
}

function find-col {
    <#
    .SYNOPSIS
        Busca en qué tablas existe una columna según un patrón de nombre.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Pattern,

        [switch]$Grid,
        [switch]$Clip,
        [Alias('Csv')]
        [string]$ExportCsv,
        [switch]$Json
    )

    $cleanPattern = ($Pattern.Trim().Trim('"', "'", '%') -replace '[\0\r\n\t;]', '').Replace("'", "''")
    $query = @"
SELECT 
    TABLE_SCHEMA AS [Esquema],
    TABLE_NAME AS [Tabla],
    COLUMN_NAME AS [Columna],
    CASE 
        WHEN DATA_TYPE IN ('varchar', 'nvarchar', 'char', 'nchar', 'binary', 'varbinary') THEN
            DATA_TYPE + '(' + CASE WHEN CHARACTER_MAXIMUM_LENGTH = -1 THEN 'MAX' ELSE CAST(CHARACTER_MAXIMUM_LENGTH AS VARCHAR(10)) END + ')'
        WHEN DATA_TYPE IN ('decimal', 'numeric') THEN
            DATA_TYPE + '(' + CAST(NUMERIC_PRECISION AS VARCHAR(10)) + ',' + CAST(NUMERIC_SCALE AS VARCHAR(10)) + ')'
        WHEN DATA_TYPE IN ('time', 'datetime2', 'datetimeoffset') THEN
            DATA_TYPE + '(' + CAST(DATETIME_PRECISION AS VARCHAR(10)) + ')'
        ELSE DATA_TYPE
    END AS [Tipo],
    IS_NULLABLE AS [Nullable]
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA NOT IN ('sys', 'INFORMATION_SCHEMA')
  AND COLUMN_NAME LIKE @Pattern
ORDER BY TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME
"@

    $qParams = @{
        QueryOrPath = $query
        Parameters  = @{
            Pattern = "%$cleanPattern%"
        }
        All         = $true
    }
    if ($Grid)      { $qParams['Grid'] = $true }
    if ($Clip)      { $qParams['Clip'] = $true }
    if ($ExportCsv) { $qParams['ExportCsv'] = $ExportCsv }
    if ($Json)      { $qParams['Json'] = $true }

    q @qParams
}

function find-code {
    <#
    .SYNOPSIS
        Busca texto dentro del código DDL de Procedimientos Almacenados, Vistas, Funciones y Triggers.
    .EXAMPLE
        find-code "Clientes"
        find-sp "usp_CalcularDescuento" -Grid
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Pattern,

        [switch]$Grid,
        [switch]$Clip,
        [Alias('Csv')]
        [string]$ExportCsv,
        [switch]$Json
    )

    $cleanPattern = ($Pattern.Trim().Trim('"', "'", '%') -replace '[\0\r\n\t;]', '').Replace("'", "''")
    $query = @"
SELECT 
    SCHEMA_NAME(o.schema_id) AS [Esquema],
    o.name AS [Objeto],
    CASE o.type
        WHEN 'P'  THEN 'Stored Procedure'
        WHEN 'V'  THEN 'View'
        WHEN 'FN' THEN 'Scalar Function'
        WHEN 'IF' THEN 'Inline Table Function'
        WHEN 'TF' THEN 'Table Function'
        WHEN 'TR' THEN 'Trigger'
        ELSE o.type_desc
    END AS [Tipo],
    o.modify_date AS [UltimaModificacion]
FROM sys.sql_modules m
INNER JOIN sys.objects o ON m.object_id = o.object_id
WHERE m.definition LIKE @Pattern
ORDER BY [Esquema], [Tipo], o.name
"@

    $qParams = @{
        QueryOrPath = $query
        Parameters  = @{ Pattern = "%$cleanPattern%" }
        All         = $true
    }
    if ($Grid)      { $qParams['Grid'] = $true }
    if ($Clip)      { $qParams['Clip'] = $true }
    if ($ExportCsv) { $qParams['ExportCsv'] = $ExportCsv }
    if ($Json)      { $qParams['Json'] = $true }

    q @qParams
}
Set-Alias find-sp  find-code
Set-Alias grep-sql find-code

function q2excel {
    <#
    .SYNOPSIS
        Ejecuta una consulta SQL y abre el resultado directamente en Excel.
    .EXAMPLE
        q2excel "SELECT TOP 100 * FROM Articulos WHERE Activo = 1"
        q2excel ./reporte.sql
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$QueryOrPath,

        [Parameter()]
        [Alias('Params')]
        [System.Collections.IDictionary]$Parameters,

        [int]$Timeout = 120
    )

    $tempCsv = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "sql_export_$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).csv")
    $qParams = @{
        QueryOrPath = $QueryOrPath
        ExportCsv   = $tempCsv
        All         = $true
        Timeout     = $Timeout
    }
    if ($Parameters) { $qParams['Parameters'] = $Parameters }

    q @qParams

    if (Test-Path -LiteralPath $tempCsv) {
        Write-Host "Abriendo en Excel..." -ForegroundColor Cyan
        Start-Process $tempCsv
    }
}
Set-Alias qexcel q2excel

function open-sql {
    <#
    .SYNOPSIS
        Extrae el DDL de un objeto SQL y lo abre directamente en Neovim.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ObjectName
    )

    $clean = ($ObjectName.Trim().Trim('"', "'") -replace '[\0\r\n\t;]', '').Replace("'", "''")
    $query = "SELECT OBJECT_DEFINITION(OBJECT_ID(@ObjectName)) AS [Definition]"

    $res = q -QueryOrPath $query -Parameters @{ ObjectName = $clean } -All
    $code = $null

    if ($res -is [System.Data.DataTable] -and $res.Rows.Count -gt 0) {
        $val = $res.Rows[0]['Definition']
        if ($val -ne [System.DBNull]::Value) { $code = [string]$val }
    }
    elseif ($res -is [System.Array] -and $res.Count -gt 0) {
        $val = $res[0].Definition
        if ($val) { $code = [string]$val }
    }
    elseif ($res -and $res.PSObject.Properties['Definition']) {
        $val = $res.Definition
        if ($val) { $code = [string]$val }
    }
    elseif ($res -is [System.Data.DataRow]) {
        $val = $res['Definition']
        if ($val -ne [System.DBNull]::Value) { $code = [string]$val }
    }

    if ([string]::IsNullOrWhiteSpace($code)) {
        Write-Host "No se encontró definición para [$ObjectName]" -ForegroundColor Yellow
        return
    }

    $safeName = ($clean.Trim('[]') -replace '[^\w\.\-]', '_')
    $tempFile = Join-Path $env:TEMP "$safeName.sql"

    [System.IO.File]::WriteAllText($tempFile, $code, [System.Text.UTF8Encoding]::new($true))
    nvim $tempFile
}

Register-ArgumentCompleter -CommandName open-sql -ParameterName ObjectName -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    if ($null -eq $global:SqlTableCache -or $global:SqlTableCache.Count -eq 0) {
        Update-SqlTableCache
    }

    $cleanWord = $wordToComplete.TrimStart('"', "'", '[')
    $global:SqlTableCache | Where-Object { $_ -like "$cleanWord*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
            $_,
            $_,
            'ParameterValue',
            "Objeto SQL: $_"
        )
    }
}

# Scratchpad SQL en Neovim con opción de ejecución directa
function vsql {
    <#
    .SYNOPSIS
        Abre un buffer SQL temporal en Neovim y opcionalmente ejecuta la consulta con 'q'.
    .EXAMPLE
        vsql
    #>
    [CmdletBinding()]
    param()

    $tempSql = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "scratch_$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).sql")
    $header = "-- Scratchpad SQL en [$global:SqlDefaultDatabase]@[$global:SqlDefaultServer]`r`n-- Escribe tu consulta y guarda con :wq`r`n`r`n"
    [System.IO.File]::WriteAllText($tempSql, $header, [System.Text.UTF8Encoding]::new($true))

    try {
        nvim $tempSql
        if (Test-Path -LiteralPath $tempSql) {
            $rawContent = [System.IO.File]::ReadAllText($tempSql)
            $clean = ($rawContent -replace '(?m)^--.*$', '').Trim()
            if (-not [string]::IsNullOrWhiteSpace($clean)) {
                Write-Host ""
                $answer = Read-Host "¿Deseas ejecutar la consulta con 'q'? (S/n)"
                if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^(s|si|y|yes)$') {
                    q -QueryOrPath $tempSql
                }
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $tempSql -Force -ErrorAction SilentlyContinue
    }
}

function qfmt {
    <#
    .SYNOPSIS
        Formatea una consulta SQL con saltos de línea e indentaciones estándar.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Query,

        [switch]$Clip
    )

    process {
        $nl = [Environment]::NewLine
        $ind = '  '

        # 1. Normalizar espacios duplicados
        $text = ($Query.Trim() -replace '[ \t]+', ' ')

        # 2. Cláusulas principales (salto de línea a nivel raíz)
        $text = [regex]::Replace($text, '(?mi)\bSELECT\b', 'SELECT')
        $text = [regex]::Replace($text, '(?mi)\bFROM\b', ($nl + 'FROM'))
        $text = [regex]::Replace($text, '(?mi)\bWHERE\b', ($nl + 'WHERE'))
        $text = [regex]::Replace($text, '(?mi)\bGROUP\s+BY\b', ($nl + 'GROUP BY'))
        $text = [regex]::Replace($text, '(?mi)\bHAVING\b', ($nl + 'HAVING'))
        $text = [regex]::Replace($text, '(?mi)\bORDER\s+BY\b', ($nl + 'ORDER BY'))
        $text = [regex]::Replace($text, '(?mi)\bUNION\s+ALL\b', ($nl + $nl + 'UNION ALL' + $nl))
        $text = [regex]::Replace($text, '(?mi)\bUNION\b', ($nl + $nl + 'UNION' + $nl))

        # 3. Joins (salto de línea con 2 espacios de indentación)
        $text = [regex]::Replace($text, '(?mi)\bINNER\s+JOIN\b', ($nl + $ind + 'INNER JOIN'))
        $text = [regex]::Replace($text, '(?mi)\bLEFT\s+(?:OUTER\s+)?JOIN\b', ($nl + $ind + 'LEFT JOIN'))
        $text = [regex]::Replace($text, '(?mi)\bRIGHT\s+(?:OUTER\s+)?JOIN\b', ($nl + $ind + 'RIGHT JOIN'))
        $text = [regex]::Replace($text, '(?mi)\bFULL\s+(?:OUTER\s+)?JOIN\b', ($nl + $ind + 'FULL JOIN'))
        $text = [regex]::Replace($text, '(?mi)\bCROSS\s+JOIN\b', ($nl + $ind + 'CROSS JOIN'))
        $text = [regex]::Replace($text, '(?mi)(?<!(?:INNER|LEFT|RIGHT|FULL|CROSS)\s+)\bJOIN\b', ($nl + $ind + 'JOIN'))

        # 4. Operadores lógicos (salto de línea con 2 espacios de indentación)
        $text = [regex]::Replace($text, '(?mi)\bAND\b', ($nl + $ind + 'AND'))
        $text = [regex]::Replace($text, '(?mi)\bOR\b', ($nl + $ind + 'OR'))

        $result = $text.Trim()

        if ($Clip) {
            try {
                Set-Clipboard -Value $result -ErrorAction Stop
            }
            catch {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
                [System.Windows.Forms.Clipboard]::SetText($result)
            }
            Write-Host "✓ Consulta formateada copiada al portapapeles" -ForegroundColor Cyan
            return
        }

        $result
    }
}

# ==============================================================================
# 6. AUTOCOMPLETADO SQL (PSReadLine KeyHandler: Ctrl+Space)
# ==============================================================================

if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue

    Set-PSReadLineKeyHandler -Chord @('Ctrl+Spacebar', 'Ctrl+@') -BriefDescription 'SqlTableCompletion' -ScriptBlock {
        # 1. Cargar caché si está vacía
        if ($null -eq $global:SqlTableCache -or $global:SqlTableCache.Count -eq 0) {
            Update-SqlTableCache
        }
        if ($null -eq $global:SqlTableCache -or $global:SqlTableCache.Count -eq 0) {
            return
        }

        # 2. Inspeccionar el búfer de la consola y la posición del cursor
        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        if ($cursor -le 0) {
            return
        }

        # 3. Extraer la palabra o token actual a la izquierda del cursor (dentro o fuera de comillas)
        $leftText = $line.Substring(0, $cursor)
        if ($leftText -match '([\w\.]+)$') {
            $token = $matches[1]
        }
        else {
            return
        }

        # 4. Buscar coincidencias en la caché
        $candidates = @($global:SqlTableCache | Where-Object { $_ -like "$token*" })
        if ($candidates.Count -eq 0) {
            return
        }

        # Si hay múltiples coincidencias, calcular el prefijo común
        $match = $candidates[0]
        if ($candidates.Count -gt 1) {
            for ($i = 1; $i -lt $candidates.Count; $i++) {
                $curr = $candidates[$i]
                $len = [Math]::Min($match.Length, $curr.Length)
                $j = 0
                while ($j -lt $len -and $match[$j] -eq $curr[$j]) {
                    $j++
                }
                $match = $match.Substring(0, $j)
            }
            # Si el prefijo común coincide con lo ya escrito, tomar el primer candidato
            if ($match.Length -le $token.Length) {
                $match = $candidates[0]
            }
        }

        # 5. Insertar únicamente el sufijo restante
        if ($match.Length -gt $token.Length) {
            $suffix = $match.Substring($token.Length)
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($suffix)
        }
    }

    # Edición visual de la línea de comandos con Neovim (Ctrl+X, Ctrl+E)
    Set-PSReadLineKeyHandler -Chord 'Ctrl+x,Ctrl+e' -Function ViEditVisually
}

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
        Write-Host " [$db ⚡]" -ForegroundColor Green -NoNewline
    }

    return "> "
}


