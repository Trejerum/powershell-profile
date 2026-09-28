# ==============================================================================
# 0. CONFIGURACIÓN DEL ENTORNO & CODIFICACIÓN
# ==============================================================================
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

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

# ==============================================================================
# 3. ATAJOS DE GIT
# ==============================================================================

function g     { git $args }
function gs    { git status -sb $args }
function gp    { git pull $args }
function gf    { git fetch $args }
function gpush { git push $args }
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

        # Utilidades
        [PSCustomObject]@{ Categoria = "General";    Comando = "cb";    Descripcion = "Copia texto o pipeline al portapapeles" }

        # Atajos Git
        [PSCustomObject]@{ Categoria = "Git";        Comando = "g";     Descripcion = "Atajo directo a 'git'" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gs";    Descripcion = "git status -sb" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "ga";    Descripcion = "git add ." }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gp/gf"; Descripcion = "git pull / git fetch" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gpush"; Descripcion = "git push" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gco";   Descripcion = "git checkout <rama/archivo>" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "glog";  Descripcion = "Historial gráfico compacto (últimos 10)" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gme";   Descripcion = "Commits remotos de Diego Corral" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gss";   Descripcion = "Stash con timestamp y rama (incluye untracked)" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gsl";   Descripcion = "Listar stashes coloreados" }
        [PSCustomObject]@{ Categoria = "Git";        Comando = "gsp";   Descripcion = "Aplicar stash (ej. 'gsp' o 'gsp 2')" }
 
         # SQL Server Toolkit
         [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "q";          Descripcion = "Ejecuta SQL/.sql (switches: -Grid, -Clip, -Csv, -Json, -DryRun)" }
         [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "qconnect";   Descripcion = "Conecta sesión persistente en BD (ej. qconnect [Serv] [BD])" }
         [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "qdisc";      Descripcion = "Desconecta sesión persistente (alias de qdisconnect)" }
         [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "use";        Descripcion = "Cambia BD activa y refresca caché (ej. use <BD>)" }
         [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "desc";       Descripcion = "Describe columnas y tipos de una tabla (ej. desc <tabla>)" }
         [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "find-table"; Descripcion = "Busca tablas/vistas por patrón (ej. find-table <patrón>)" }
         [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "count";      Descripcion = "Recuento ultrarrápido sin scan (sys.dm_db_partition_stats)" }
         [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "who";        Descripcion = "Monitor de sesiones activas y bloqueos (sys.dm_exec_requests)" }
         [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "see";        Descripcion = "Inspecciona DDL/código de vista/SP/función (ej. see <objeto> [-Clip])" }
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
             $cmd = $item.Comando.PadRight(12)
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
        $cmd.CommandText = "SELECT TABLE_SCHEMA + '.' + TABLE_NAME AS FullName, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE IN ('BASE TABLE', 'VIEW')"
        $cmd.CommandTimeout = 15

        $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
        $dt = New-Object System.Data.DataTable
        [void]$da.Fill($dt)

        $items = @()
        foreach ($row in $dt.Rows) {
            $items += $row['FullName']
            $items += $row['TABLE_NAME']
        }
        $global:SqlTableCache = @($items | Sort-Object -Unique)
    }
    catch {
        Write-Warning "Error al consultar INFORMATION_SCHEMA.TABLES: $_"
    }
    finally {
        if ($needClose -and $conn) {
            $conn.Close()
            $conn.Dispose()
        }
    }
}

function qdisconnect {
    <#
    .SYNOPSIS
        Cierra y destruye la conexión persistente activa.
    #>
    [CmdletBinding()]
    param()

    if ($global:SqlSession) {
        if ($global:SqlSession.State -eq 'Open') {
            $global:SqlSession.Close()
        }
        $global:SqlSession.Dispose()
        $global:SqlSession = $null
        Write-Host "[INFO] Sesión desconectada. Modo transitorio activado." -ForegroundColor Yellow
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

    qdisconnect

    $cs = "Server=$Server;Database=$Database;Integrated Security=True;TrustServerCertificate=True;Connection Timeout=15;"
    try {
        $global:SqlSession = New-Object System.Data.SqlClient.SqlConnection($cs)
        $global:SqlSession.Open()
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

    $cleanDb = $Database.Trim().Trim('"', "'").Trim('[]')

    if ($global:SqlSession -and $global:SqlSession.State -eq 'Open') {
        try {
            $cmd = $global:SqlSession.CreateCommand()
            $cmd.CommandText = "USE [$cleanDb]"
            [void]$cmd.ExecuteNonQuery()
            $global:SqlDefaultDatabase = $cleanDb
            Update-SqlTableCache
            Write-Host "● Contexto cambiado a [$cleanDb]" -ForegroundColor Green
        }
        catch {
            Write-Error "No se pudo cambiar a la base de datos [$cleanDb]: $_"
        }
    }
    else {
        $global:SqlDefaultDatabase = $cleanDb
        Write-Host "● Contexto cambiado a [$cleanDb]" -ForegroundColor Green
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

        [switch]$Grid,          # Abre la ventana gráfica interactiva Out-GridView
        [switch]$Clip,          # Copia el resultado al portapapeles en formato TSV (para Excel)
        [Alias('Csv')]
        [string]$ExportCsv,     # Exporta el resultado a un archivo CSV delimitado por ';'
        [switch]$Json,          # Devuelve los datos en formato JSON (ConvertTo-Json -Depth 3)
        [Alias('DryRun')]
        [switch]$Rollback,      # Ejecuta dentro de BEGIN TRAN...ROLLBACK TRAN reportando filas afectadas sin persistir
        [switch]$All,           # Ignora el límite de seguridad de filas
        [int]$MaxRows = 100     # Límite por defecto para no congelar la consola
    )

    process {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        # 1. Detección automática: archivo en disco vs sentencia SQL en texto plano
        $isFilePath = $false
        $resolvedPath = $null
        $sqlContent = $QueryOrPath
        $gridTitle = $QueryOrPath

        if ($QueryOrPath -and (Test-Path -LiteralPath $QueryOrPath -PathType Leaf -ErrorAction SilentlyContinue)) {
            $isFilePath = $true
            $resolvedPath = (Resolve-Path -LiteralPath $QueryOrPath).ProviderPath
            $sqlContent = Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8
            $gridTitle = [System.IO.Path]::GetFileName($resolvedPath)
        }
        elseif ($QueryOrPath -and (Test-Path -Path $QueryOrPath -PathType Leaf -ErrorAction SilentlyContinue)) {
            $isFilePath = $true
            $resolvedPath = (Resolve-Path -Path $QueryOrPath).ProviderPath
            $sqlContent = Get-Content -Path $resolvedPath -Raw -Encoding UTF8
            $gridTitle = [System.IO.Path]::GetFileName($resolvedPath)
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

        $isTransient = $false
        $conn = $null

        # 3. Comprobar si existe sesión persistente viva o abrir conexión transitoria
        if ($global:SqlSession -and $global:SqlSession.State -eq 'Open') {
            $conn = $global:SqlSession
        }
        else {
            $isTransient = $true
            $cs = "Server=$global:SqlDefaultServer;Database=$global:SqlDefaultDatabase;Integrated Security=True;TrustServerCertificate=True;Connection Timeout=15;"
            $conn = New-Object System.Data.SqlClient.SqlConnection($cs)
            $conn.Open()
        }

        try {
            $cmd = $conn.CreateCommand()
            $cmd.CommandTimeout = 120
            $dt = New-Object System.Data.DataTable

            for ($i = 0; $i -lt $batches.Count; $i++) {
                $batch = $batches[$i]
                $cmd.CommandText = $batch
                $isLastBatch = ($i -eq ($batches.Count - 1))

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
        finally {
            if ($Rollback) {
                if ($conn -and $conn.State -eq 'Open') {
                    try {
                        $cleanCmd = $conn.CreateCommand()
                        $cleanCmd.CommandText = "IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;"
                        [void]$cleanCmd.ExecuteNonQuery()
                    }
                    catch { }
                }
            }
            if ($isTransient -and $conn) {
                $conn.Close()
                $conn.Dispose()
            }
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

    $clean = $Table.Trim().Trim('"', "'")
    if ($clean -match '^\[?([^.\]]+)\]?\.\[?([^.\]]+)\]?$') {
        $schema = $matches[1]
        $tableName = $matches[2]
        $filter = "TABLE_SCHEMA = '$schema' AND TABLE_NAME = '$tableName'"
    }
    else {
        $tableName = $clean.Trim('[]')
        $filter = "TABLE_NAME = '$tableName'"
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
WHERE $filter
ORDER BY ORDINAL_POSITION
"@

    $qParams = @{
        QueryOrPath = $query
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

    $cleanPattern = $Pattern.Trim().Trim('"', "'", '%')
    $query = @"
SELECT 
    TABLE_SCHEMA AS [Esquema],
    TABLE_NAME AS [Tabla],
    TABLE_TYPE AS [Tipo]
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME LIKE '%$cleanPattern%'
ORDER BY TABLE_SCHEMA, TABLE_NAME
"@

    $qParams = @{
        QueryOrPath = $query
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

    $clean = $Table.Trim().Trim('"', "'")
    if ($clean -match '^\[?([^.\]]+)\]?\.\[?([^.\]]+)\]?$') {
        $schema = $matches[1]
        $tableName = $matches[2]
        $filter = "s.name = '$schema' AND t.name = '$tableName'"
    }
    else {
        $tableName = $clean.Trim('[]')
        $filter = "t.name = '$tableName'"
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
  AND $filter
GROUP BY s.name, t.name
"@

    $qParams = @{
        QueryOrPath = $query
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

    $clean = $ObjectName.Trim().Trim('"', "'")
    $query = @"
SELECT OBJECT_DEFINITION(OBJECT_ID('$clean')) AS [Definition]
"@

    $res = q $query -All
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
}

# ==============================================================================
# 7. PROMPT PERSONALIZADO (Estado de SQL Server)
# ==============================================================================

function prompt {
    $loc = $ExecutionContext.SessionState.Path.CurrentLocation
    Write-Host "PS $loc" -NoNewline

    # Indicador de estado de conexión persistente a SQL Server
    if ($global:SqlSession -and $global:SqlSession.State -eq 'Open') {
        $db = $global:SqlSession.Database
        Write-Host " [$db ⚡]" -ForegroundColor Green -NoNewline
    }

    return "> "
}


