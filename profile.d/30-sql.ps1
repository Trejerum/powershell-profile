 # ==============================================================================
 # 5. SQL SERVER TOOLKIT (ADO.NET + PowerShell)
 # ==============================================================================

# Variables globales de conexión y sesión
$global:SqlSession         = $null
$global:SqlTableCache      = @()
$global:SqlConfig          = $null
$global:SqlConnections     = $null
$global:SqlActiveProfile   = 'local'
$global:SqlDefaultServer   = 'localhost'
$global:SqlDefaultDatabase = 'master'

function Get-SqlProfileDirectory {
    if ($global:ProfileDir -and (Test-Path -LiteralPath $global:ProfileDir)) {
        return $global:ProfileDir
    }
    if ($PROFILE -and [string]::IsNullOrWhiteSpace($PROFILE) -eq $false) {
        $parent = Split-Path -Parent $PROFILE -ErrorAction SilentlyContinue
        if ($parent -and (Test-Path -LiteralPath $parent)) { return $parent }
    }
    if ($PSScriptRoot) {
        $parent = if ((Split-Path -Leaf $PSScriptRoot) -ieq "profile.d") { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot }
        if ($parent -and (Test-Path -LiteralPath $parent)) { return $parent }
    }
    $myDocs = [Environment]::GetFolderPath('MyDocuments')
    foreach ($sub in @("PowerShell", "WindowsPowerShell")) {
        $candidate = Join-Path $myDocs $sub
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return (Get-Location).Path
}

# ==============================================================================
# FABRICA ADO.NET (Compatible nativamente con PS 5.1 y PS 7)
# ==============================================================================
function New-SqlConnectionStringBuilder {
    return [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
}

function New-SqlConnection {
    param([string]$ConnectionString)
    if ($ConnectionString) {
        return [System.Data.SqlClient.SqlConnection]::new($ConnectionString)
    }
    return [System.Data.SqlClient.SqlConnection]::new()
}

function New-SqlDataAdapter {
    param($Command)
    if ($Command) {
        return [System.Data.SqlClient.SqlDataAdapter]::new($Command)
    }
    return [System.Data.SqlClient.SqlDataAdapter]::new()
}

function Load-SqlConnectionsConfig {
    <#
    .SYNOPSIS
        Carga los perfiles de conexión desde sql-connections.json (o genera plantilla si no existe).
    #>
    $profDir = Get-SqlProfileDirectory
    $configFile = Join-Path $profDir "sql-connections.json"
    $exampleFile = Join-Path $profDir "sql-connections.example.json"

    if (Test-Path -LiteralPath $configFile) {
        try {
            $jsonContent = [System.IO.File]::ReadAllText($configFile, [System.Text.Encoding]::UTF8)
            $cfg = $jsonContent | ConvertFrom-Json
            $global:SqlConfig = $cfg
            $global:SqlConnections = $cfg.connections

            $defaultName = if ($cfg.default) { $cfg.default } else { "local" }
            Set-SqlProfile -Name $defaultName -Quiet
            return
        }
        catch {
            Write-Warning "Error leyendo sql-connections.json: $_. Usando valores de fallback."
        }
    }

    if (-not (Test-Path -LiteralPath $configFile) -and (Test-Path -LiteralPath $exampleFile)) {
        try {
            Copy-Item -LiteralPath $exampleFile -Destination $configFile -ErrorAction SilentlyContinue
            Write-Host "● Creado sql-connections.json a partir de la plantilla de ejemplo." -ForegroundColor Cyan
            Load-SqlConnectionsConfig
            return
        } catch { }
    }

    $global:SqlActiveProfile   = "local"
    $global:SqlDefaultServer   = "localhost"
    $global:SqlDefaultDatabase = "master"
    $global:SqlConnections = [PSCustomObject]@{
        "local" = [PSCustomObject]@{
            server = "localhost"
            database = "master"
            integratedSecurity = $true
            description = "Conexión local por defecto"
        }
    }
}

function Get-SqlConnectionString {
    <#
    .SYNOPSIS
        Genera la cadena de conexión ADO.NET para SQL Server según el perfil o parámetros dados.
    #>
    param(
        [string]$Server = $global:SqlDefaultServer,
        [string]$Database = $global:SqlDefaultDatabase,
        [int]$Timeout = 10,
        [string]$ProfileName
    )

    $targetProfile = if ($ProfileName) { $ProfileName } else { $global:SqlActiveProfile }
    $pData = $null
    if ($global:SqlConnections -and $targetProfile) {
        $prop = $global:SqlConnections.PSObject.Properties[$targetProfile]
        if ($prop) { $pData = $prop.Value }
    }

    $srv = if ($Server) { $Server } elseif ($pData -and $pData.server) { $pData.server } else { "localhost" }
    $db  = if ($Database) { $Database } elseif ($pData -and $pData.database) { $pData.database } else { "master" }

    $builder = New-SqlConnectionStringBuilder
    $builder['Data Source'] = $srv
    $builder['Initial Catalog'] = $db
    $builder['Connect Timeout'] = $Timeout
    $builder['TrustServerCertificate'] = $true

    if ($pData -and $pData.integratedSecurity -eq $false -and $pData.user) {
        $builder['Integrated Security'] = $false
        $builder['User ID'] = $pData.user
        if ($pData.password) {
            $builder['Password'] = $pData.password
        }
    } else {
        $builder['Integrated Security'] = $true
    }

    return $builder.ConnectionString
}

function Set-SqlProfile {
    <#
    .SYNOPSIS
        Cambia el perfil de conexión SQL Server activo para todos los comandos del toolkit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name,

        [Parameter()]
        [switch]$Quiet
    )

    if ($null -eq $global:SqlConnections) {
        Load-SqlConnectionsConfig
    }

    $prop = $global:SqlConnections.PSObject.Properties[$Name]
    if (-not $prop) {
        $match = $global:SqlConnections.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
        if ($match) {
            $prop = $match
            $Name = $match.Name
        }
    }

    if (-not $prop) {
        Write-Error "El perfil SQL '$Name' no existe en sql-connections.json. Usa 'qenv' para ver los perfiles disponibles."
        return
    }

    $profileData = $prop.Value
    $global:SqlActiveProfile   = $Name
    $global:SqlDefaultServer   = $profileData.server
    $global:SqlDefaultDatabase = $profileData.database

    if ($global:SqlSession -and $global:SqlSession.State -eq 'Open') {
        qconnect -Server $global:SqlDefaultServer -Database $global:SqlDefaultDatabase -Quiet
    }

    $PSDefaultParameterValues['Invoke-Sqlcmd:ServerInstance'] = $global:SqlDefaultServer
    $PSDefaultParameterValues['Invoke-Sqlcmd:Database']       = $global:SqlDefaultDatabase

    $global:SqlTableCache = @()

    if (-not $Quiet) {
        Write-Host "● Perfil SQL cambiado a " -NoNewline -ForegroundColor Green
        Write-Host "[$Name] " -ForegroundColor Yellow -NoNewline
        Write-Host "($global:SqlDefaultServer / $global:SqlDefaultDatabase)" -ForegroundColor White
    }
}

function qenv {
    <#
    .SYNOPSIS
        Muestra o cambia el entorno de conexión SQL Server configurado en sql-connections.json.
    .EXAMPLE
        qenv
        qenv pre
        qenv local
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Profile
    )

    if ($Profile) {
        Set-SqlProfile -Name $Profile
        return
    }

    if ($null -eq $global:SqlConnections) {
        Load-SqlConnectionsConfig
    }

    $profDir = Get-SqlProfileDirectory
    $configFile = Join-Path $profDir "sql-connections.json"

    Write-Host "`n=== Entornos SQL Server ($configFile) ===`n" -ForegroundColor DarkCyan

    $defaultName = if ($global:SqlConfig -and $global:SqlConfig.default) { $global:SqlConfig.default } else { "local" }

    $rows = @()
    foreach ($p in $global:SqlConnections.PSObject.Properties) {
        $pName = $p.Name
        $val   = $p.Value
        $isDefault = ($pName -ieq $defaultName)
        $isActive  = ($pName -ieq $global:SqlActiveProfile)

        $statusMark = if ($isActive -and $isDefault) { "* (Activo)" }
                      elseif ($isActive) { "(Activo)" }
                      elseif ($isDefault) { "*" }
                      else { "" }

        $auth = if ($val.integratedSecurity -eq $false) { "SQL ($($val.user))" } else { "Windows Auth" }

        $rows += [PSCustomObject]@{
            Perfil     = $pName
            Servidor   = $val.server
            BaseDatos  = $val.database
            Default    = $statusMark
            Autentic   = $auth
            Descrip    = $val.description
        }
    }

    $rows | Format-Table Perfil, Servidor, BaseDatos, Default, Autentic, Descrip -AutoSize

    Write-Host "Tip: Usa 'qenv <perfil>' o 'qconnect <perfil>' (ej. 'qenv pre') para activar un entorno.`n" -ForegroundColor DarkGray
}
Set-Alias qprofiles qenv
Set-Alias qconns qenv

# Comprobación de conectividad y latencia multi-perfil (sql-ping / qping)
function sql-ping {
    <#
    .SYNOPSIS
        Comprueba la conectividad, latencia y estado de todos los perfiles de SQL Server o uno específico.
    .EXAMPLE
        sql-ping
        sql-ping local
        qping
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Profile,

        [int]$Timeout = 3
    )

    if ($null -eq $global:SqlConnections) {
        Load-SqlConnectionsConfig
    }

    $profilesToTest = if ($Profile) {
        $p = $global:SqlConnections.PSObject.Properties[$Profile]
        if (-not $p) {
            Write-Warning "El perfil '$Profile' no existe en sql-connections.json."
            return
        }
        @($p)
    } else {
        @($global:SqlConnections.PSObject.Properties)
    }

    Write-Host "`n=== Diagnóstico de Conectividad SQL ($($profilesToTest.Count) perfiles, timeout ${Timeout}s) ===`n" -ForegroundColor DarkCyan

    $results = @()
    foreach ($prop in $profilesToTest) {
        $pName = $prop.Name
        $data  = $prop.Value
        $srv   = if ($data.server) { $data.server } else { "localhost" }
        $db    = if ($data.database) { $data.database } else { "master" }

        $connStr = Get-SqlConnectionString -ProfileName $pName -Timeout $Timeout

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $conn = New-SqlConnection -ConnectionString $connStr
        $status = "Online"
        $statusText = "✓ En línea"
        $statusColor = "Green"
        $version = ""
        $errorMsg = ""

        try {
            $conn.Open()
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "SELECT SERVERPROPERTY('ProductVersion') AS Ver, SERVERPROPERTY('ProductLevel') AS Lvl"
            $cmd.CommandTimeout = $Timeout
            $reader = $cmd.ExecuteReader()
            if ($reader.Read()) {
                $version = "$($reader['Ver']) ($($reader['Lvl']))"
            }
            $reader.Close()
            $conn.Close()
        }
        catch {
            $status = "Offline"
            $statusText = "✖ Inaccesible"
            $statusColor = "Red"
            $errorMsg = $_.Exception.Message
            if ($errorMsg.Length -gt 45) { $errorMsg = $errorMsg.Substring(0, 42) + '...' }
        }
        finally {
            $sw.Stop()
            if ($conn -and $conn.State -eq 'Open') { $conn.Dispose() }
        }

        $latencyMs = [Math]::Round($sw.Elapsed.TotalMilliseconds, 0)
        $latencyStr = if ($status -eq "Online") { "$latencyMs ms" } else { "Timeout" }

        $results += [PSCustomObject]@{
            Perfil    = $pName
            Servidor  = $srv
            BaseDatos = $db
            Estado    = $statusText
            Color     = $statusColor
            Latencia  = $latencyStr
            Detalle   = if ($version) { $version } else { $errorMsg }
        }
    }

    foreach ($r in $results) {
        $pCol   = "[$($r.Perfil)]".PadRight(14)
        $srvCol = $r.Servidor.PadRight(22)
        $dbCol  = $r.BaseDatos.PadRight(18)
        $latCol = $r.Latencia.PadLeft(8)

        Write-Host "  $pCol" -NoNewline -ForegroundColor Yellow
        Write-Host "$srvCol" -NoNewline -ForegroundColor White
        Write-Host "$dbCol" -NoNewline -ForegroundColor DarkGray
        Write-Host " | " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($r.Estado)".PadRight(14) -NoNewline -ForegroundColor $r.Color
        Write-Host " | Latencia: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$latCol" -NoNewline -ForegroundColor Cyan
        Write-Host " | $($r.Detalle)" -ForegroundColor DarkGray
    }
    Write-Host ""
}
Set-Alias qping sql-ping

Load-SqlConnectionsConfig

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
        $cs = Get-SqlConnectionString -Server $global:SqlDefaultServer -Database $global:SqlDefaultDatabase -Timeout 5
        $conn = New-SqlConnection -ConnectionString $cs
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

        $da = New-SqlDataAdapter -Command $cmd
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
        Abre una conexión persistente ultra rápida con SQL Server (soporta nombre de perfil o servidor/bd).
    .EXAMPLE
        qconnect
        qconnect pre
        qconnect local
        qconnect 'SRV\INST' 'MiBaseDatos'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Server,

        [Parameter(Position = 1)]
        [string]$Database,

        [switch]$Quiet
    )

    if ($Server -and -not $Database -and $global:SqlConnections) {
        $match = $global:SqlConnections.PSObject.Properties | Where-Object { $_.Name -ieq $Server } | Select-Object -First 1
        if ($match) {
            Set-SqlProfile -Name $match.Name -Quiet
            $Server   = $global:SqlDefaultServer
            $Database = $global:SqlDefaultDatabase
        }
    }

    if (-not $Server)   { $Server   = $global:SqlDefaultServer }
    if (-not $Database) { $Database = $global:SqlDefaultDatabase }

    qdisconnect -Quiet

    $cs = Get-SqlConnectionString -Server $Server -Database $Database -Timeout 10
    try {
        $global:SqlSession = New-SqlConnection -ConnectionString $cs
        $global:SqlSession.Open()

        # Prevención de transacciones huérfanas
        $initCmd = $global:SqlSession.CreateCommand()
        $initCmd.CommandText = "SET XACT_ABORT ON;"
        $initCmd.CommandTimeout = 5
        [void]$initCmd.ExecuteNonQuery()

        if (-not $Quiet) {
            Write-Host "[OK] Conectado a [$Database] en [$Server]" -ForegroundColor Green
            if ($global:SqlActiveProfile) {
                Write-Host "     Perfil activo: [$global:SqlActiveProfile]" -ForegroundColor DarkGray
            }
        }
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

    $newDb = $cleanDb.Replace(']]', ']')
    if ($global:SqlSession -and $global:SqlSession.State -eq 'Open') {
        try {
            $cmd = $global:SqlSession.CreateCommand()
            $cmd.CommandText = "USE [$cleanDb]"
            [void]$cmd.ExecuteNonQuery()
            $global:SqlDefaultDatabase = $newDb
            if ($global:SqlConnections -and $global:SqlActiveProfile) {
                $prop = $global:SqlConnections.PSObject.Properties[$global:SqlActiveProfile]
                if ($prop) { $prop.Value.database = $newDb }
            }
            Update-SqlTableCache
            Write-Host "● Contexto cambiado a [$($global:SqlDefaultDatabase)]" -ForegroundColor Green
        }
        catch {
            Write-Error "No se pudo cambiar a la base de datos [$cleanDb]: $_"
        }
    }
    else {
        $global:SqlDefaultDatabase = $newDb
        if ($global:SqlConnections -and $global:SqlActiveProfile) {
            $prop = $global:SqlConnections.PSObject.Properties[$global:SqlActiveProfile]
            if ($prop) { $prop.Value.database = $newDb }
        }
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
            $cs = Get-SqlConnectionString -Server $global:SqlDefaultServer -Database "master" -Timeout 3
            $conn = New-SqlConnection -ConnectionString $cs
            $conn.Open()
            $needClose = $true
        }

        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT name FROM sys.databases WHERE state = 0 ORDER BY name"
        $cmd.CommandTimeout = 5
        $da = New-SqlDataAdapter -Command $cmd
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
            $cs = Get-SqlConnectionString -Server $global:SqlDefaultServer -Database $global:SqlDefaultDatabase -Timeout 10
            try {
                $conn = New-SqlConnection -ConnectionString $cs
                $conn.Open()
                # Prevención de transacciones huérfanas
                $initCmd = $conn.CreateCommand()
                $initCmd.CommandText = "SET XACT_ABORT ON;"
                $initCmd.CommandTimeout = 5
                [void]$initCmd.ExecuteNonQuery()
            }
            catch {
                Write-Error "No se pudo conectar a SQL Server ($global:SqlDefaultServer / $global:SqlDefaultDatabase): $($_.Exception.Message)"
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
                            $da = New-SqlDataAdapter -Command $cmd
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
                    elseif ($ex.GetType().Name -eq 'SqlException') {
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
                            $cs = Get-SqlConnectionString -Server $savedServer -Database $savedDb -Timeout 10
                            $global:SqlSession = New-SqlConnection -ConnectionString $cs
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
Set-Alias locks who
Set-Alias sql-who who

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
    $profTag = if ($global:SqlActiveProfile) { " ($global:SqlActiveProfile)" } else { "" }
    $header = "-- Scratchpad SQL en [$global:SqlDefaultDatabase]@[$global:SqlDefaultServer]$profTag`r`n-- Escribe tu consulta y guarda con :wq`r`n`r`n"
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

# Lista todas las bases de datos de la instancia SQL actual con su tamaño y estado
function dbs {
    <#
    .SYNOPSIS
        Lista todas las bases de datos de la instancia SQL actual con tamaño en MB y estado.
    .EXAMPLE
        dbs
        dbs -Grid
    #>
    [CmdletBinding()]
    param(
        [switch]$Grid,
        [switch]$Clip
    )
    $query = @"
SELECT 
    d.name AS [BaseDatos],
    d.state_desc AS [Estado],
    d.recovery_model_desc AS [RecoveryModel],
    CAST(ROUND(SUM(mf.size) * 8.0 / 1024.0, 2) AS NUMERIC(10,2)) AS [TamanoMB]
FROM sys.databases d
LEFT JOIN sys.master_files mf ON d.database_id = mf.database_id
GROUP BY d.name, d.state_desc, d.recovery_model_desc
ORDER BY d.name
"@
    $qParams = @{ QueryOrPath = $query; All = $true }
    if ($Grid) { $qParams['Grid'] = $true }
    if ($Clip) { $qParams['Clip'] = $true }
    q @qParams
}
Set-Alias show-dbs dbs

# Lista las tablas de la base de datos activa con recuento de filas ultrarrápido sin scan
function tables {
    <#
    .SYNOPSIS
        Lista todas las tablas de la BD actual con recuento exacto de filas (sin scan de tablas).
    .EXAMPLE
        tables
        tables Articulos
        tables -Grid
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Filter,

        [switch]$Grid,
        [switch]$Clip
    )
    $cleanFilter = ($Filter -replace "[';]", '')
    $query = @"
SELECT 
    s.name AS [Esquema],
    t.name AS [Tabla],
    SUM(p.row_count) AS [Filas]
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.dm_db_partition_stats p ON t.object_id = p.object_id
WHERE p.index_id IN (0, 1)
  AND (@Filter IS NULL OR t.name LIKE @Pattern OR s.name LIKE @Pattern)
GROUP BY s.name, t.name
ORDER BY s.name, t.name
"@
    $qParams = @{
        QueryOrPath = $query
        Parameters  = @{
            Filter  = if ($Filter) { $Filter } else { $null }
            Pattern = if ($Filter) { "%$cleanFilter%" } else { "%" }
        }
        All         = $true
    }
    if ($Grid) { $qParams['Grid'] = $true }
    if ($Clip) { $qParams['Clip'] = $true }
    q @qParams
}

# Lista las vistas de la base de datos activa
function views {
    <#
    .SYNOPSIS
        Lista todas las vistas de la BD activa con fecha de creación y modificación.
    .EXAMPLE
        views
        views vStock
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Filter,

        [switch]$Grid,
        [switch]$Clip
    )
    $cleanFilter = ($Filter -replace "[';]", '')
    $query = @"
SELECT 
    s.name AS [Esquema],
    v.name AS [Vista],
    v.create_date AS [FechaCreacion],
    v.modify_date AS [UltimaModificacion]
FROM sys.views v
INNER JOIN sys.schemas s ON v.schema_id = s.schema_id
WHERE (@Filter IS NULL OR v.name LIKE @Pattern OR s.name LIKE @Pattern)
ORDER BY s.name, v.name
"@
    $qParams = @{
        QueryOrPath = $query
        Parameters  = @{
            Filter  = if ($Filter) { $Filter } else { $null }
            Pattern = if ($Filter) { "%$cleanFilter%" } else { "%" }
        }
        All         = $true
    }
    if ($Grid) { $qParams['Grid'] = $true }
    if ($Clip) { $qParams['Clip'] = $true }
    q @qParams
}

# Consulta rápida de las primeras N filas de una tabla o vista
function top {
    <#
    .SYNOPSIS
        Muestra rápidamente las primeras N filas (por defecto 20) de cualquier tabla o vista.
    .EXAMPLE
        top Articulos
        top Articulos 50 -Grid
        top Clientes 10 -Clip
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Table,

        [Parameter(Position = 1)]
        [int]$Count = 20,

        [switch]$Grid,
        [switch]$Clip,
        [switch]$Json
    )

    $clean = ($Table.Trim().Trim('"', "'") -replace '[\0\r\n\t;]', '').Replace("'", "''")
    $bracketed = if ($clean -match '^\[?([^.\]]+)\]?\.\[?([^.\]]+)\]?$') {
        "[" + $matches[1].Trim('[]') + "].[" + $matches[2].Trim('[]') + "]"
    } else {
        "[" + $clean.Trim('[]') + "]"
    }

    $query = "SELECT TOP $Count * FROM $bracketed"
    $qParams = @{ QueryOrPath = $query; All = $true }
    if ($Grid) { $qParams['Grid'] = $true }
    if ($Clip) { $qParams['Clip'] = $true }
    if ($Json) { $qParams['Json'] = $true }
    q @qParams
}

Register-ArgumentCompleter -CommandName top -ParameterName Table -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    if ($null -eq $global:SqlTableCache -or $global:SqlTableCache.Count -eq 0) {
        Update-SqlTableCache
    }
    $cleanWord = $wordToComplete.TrimStart('"', "'", '[')
    $global:SqlTableCache | Where-Object { $_ -like "$cleanWord*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Tabla: $_")
    }
}

# Ejecuta una consulta SQL y copia directamente los resultados tabulados al portapapeles
function qclip {
    <#
    .SYNOPSIS
        Ejecuta una consulta SQL y copia directamente los resultados tabulados al portapapeles.
    .EXAMPLE
        qclip "SELECT TOP 50 * FROM Articulos"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$QueryOrPath
    )
    q -QueryOrPath $QueryOrPath -Clip -All
}


# ==============================================================================
# AUTOCOMPLETADO SQL (PSReadLine KeyHandler: Ctrl+Space)
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
