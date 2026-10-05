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

# Crea archivos vacíos o actualiza la fecha de modificación (estilo Unix)
function touch {
    <#
    .SYNOPSIS
        Crea archivos vacíos o actualiza la fecha de modificación al estilo Unix.
    .EXAMPLE
        touch script.ps1
        touch note1.txt note2.txt
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Path
    )
    process {
        foreach ($p in $Path) {
            if (Test-Path -LiteralPath $p) {
                (Get-Item -LiteralPath $p).LastWriteTime = [DateTime]::Now
            }
            else {
                $parent = Split-Path -Parent $p
                if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                    [void](New-Item -ItemType Directory -Path $parent -Force)
                }
                [void](New-Item -ItemType File -Path $p -Force)
            }
        }
    }
}

# Búsqueda ultrarrápida de archivos por nombre recursivamente (usando Ripgrep si existe)
function ff {
    <#
    .SYNOPSIS
        Busca archivos por nombre recursivamente usando Ripgrep o fallback nativo.
    .EXAMPLE
        ff "Controller"
        ff "*.sql" database/
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Pattern,

        [Parameter(Position = 1)]
        [string]$Path = "."
    )
    if (Get-Command rg -ErrorAction SilentlyContinue) {
        rg --files $Path 2>$null | Select-String -Pattern $Pattern -SimpleMatch | ForEach-Object { $_.Line }
    }
    else {
        Get-ChildItem -Path $Path -Recurse -Filter "*$Pattern*" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    }
}

# Muestra la ruta real, tipo y origen de un comando o ejecutable
function which {
    <#
    .SYNOPSIS
        Muestra la ruta real, tipo y origen de un comando, función o ejecutable.
    .EXAMPLE
        which nvim
        which git
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name
    )
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Host "● No se encontró el comando o ejecutable: '$Name'" -ForegroundColor Yellow
        return
    }
    $cmd | Select-Object Name, CommandType, @{Name='Origen/Ruta'; Expression={ if ($_.Source) { $_.Source } elseif ($_.Definition) { $_.Definition } else { "N/A" } }}, Version | Format-Table -AutoSize
}

# Muestra las primeras líneas de un archivo o flujo
function head {
    <#
    .SYNOPSIS
        Muestra las primeras N líneas de un archivo o entrada de tubería.
    .EXAMPLE
        head error.log
        head error.log -n 25
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        $Path,

        [Parameter(Position = 1)]
        [Alias('n')]
        [int]$Count = 10
    )
    process {
        if ($Path -is [string] -and (Test-Path -LiteralPath $Path)) {
            Get-Content -LiteralPath $Path -TotalCount $Count
        } else {
            $Path | Select-Object -First $Count
        }
    }
}

# Muestra las últimas líneas de un archivo o flujo
function tail {
    <#
    .SYNOPSIS
        Muestra las últimas N líneas de un archivo o entrada de tubería.
    .EXAMPLE
        tail error.log
        tail error.log -n 30
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        $Path,

        [Parameter(Position = 1)]
        [Alias('n')]
        [int]$Count = 10
    )
    process {
        if ($Path -is [string] -and (Test-Path -LiteralPath $Path)) {
            Get-Content -LiteralPath $Path -Tail $Count
        } else {
            $Path | Select-Object -Last $Count
        }
    }
}

# Descompresor universal para .zip, .tar.gz, .7z, .rar
function extract {
    <#
    .SYNOPSIS
        Descomprime archivos (.zip, .tar.gz, .7z, .rar) en la carpeta indicada.
    .EXAMPLE
        extract release.zip
        extract backup.7z ./destino
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Archive,

        [Parameter(Position = 1)]
        [string]$Destination = "."
    )
    if (-not (Test-Path -LiteralPath $Archive)) {
        Write-Error "No se encontró el archivo: $Archive"
        return
    }
    $resolved = (Resolve-Path -LiteralPath $Archive).ProviderPath
    if (Get-Command 7z -ErrorAction SilentlyContinue) {
        7z x $resolved -o"$Destination"
    }
    elseif ($resolved.EndsWith(".zip", [System.StringComparison]::OrdinalIgnoreCase)) {
        Expand-Archive -LiteralPath $resolved -DestinationPath $Destination -Force
    }
    elseif (Get-Command tar -ErrorAction SilentlyContinue) {
        tar -xf $resolved -C $Destination
    }
    else {
        Write-Error "No se encontró 7z, tar ni Expand-Archive para procesar '$resolved'."
    }
}

# Lista los puertos TCP locales que están a la escucha
function ports {
    <#
    .SYNOPSIS
        Muestra todos los puertos TCP locales en escucha con su PID y nombre de proceso.
    .EXAMPLE
        ports
        ports 4200
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Filter
    )
    $conns = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
    if (-not $conns) {
        Write-Host "● No se detectaron conexiones en escucha." -ForegroundColor DarkGray
        return
    }
    $results = @(foreach ($c in ($conns | Sort-Object -Property LocalPort)) {
        $pidVal = $c.OwningProcess
        $pName = if ($pidVal -le 4) { "System" } else {
            $proc = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
            if ($proc) { $proc.ProcessName } else { "Desconocido" }
        }
        [PSCustomObject]@{
            Puerto  = $c.LocalPort
            IP      = $c.LocalAddress
            PID     = $pidVal
            Proceso = $pName
        }
    })
    if ($Filter) {
        $results = $results | Where-Object { $_.Puerto -like "*$Filter*" -or $_.Proceso -like "*$Filter*" }
    }
    $results | Format-Table -AutoSize
}
Set-Alias listening ports

# Busca procesos en ejecución con consumo de RAM y CPU
function psfind {
    <#
    .SYNOPSIS
        Busca procesos en ejecución mostrando PID, memoria en MB y CPU.
    .EXAMPLE
        psfind node
        psfind sql
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name
    )
    Get-Process | Where-Object { $_.ProcessName -like "*$Name*" } |
        Select-Object Id, ProcessName, @{Name='RAM (MB)'; Expression={[Math]::Round($_.WorkingSet64 / 1MB, 1)}}, @{Name='CPU (s)'; Expression={[Math]::Round($_.CPU, 1)}}, Responding |
        Format-Table -AutoSize
}
Set-Alias psgrep psfind

# Muestra la IP local activa y la IP pública
function myip {
    <#
    .SYNOPSIS
        Muestra la dirección IP local de las tarjetas de red activas y la IP pública externa.
    #>
    [CmdletBinding()]
    param()

    Write-Host "--- Red Local ---" -ForegroundColor Cyan
    Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Wi-Fi*', 'Ethernet*', 'vEthernet*' -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "169.254*" -and $_.IPAddress -ne "127.0.0.1" } |
        Select-Object InterfaceAlias, IPAddress, IPv4Address | Format-Table -AutoSize

    Write-Host "--- IP Pública ---" -ForegroundColor Cyan
    try {
        $pub = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 3).Trim()
        Write-Host "IP Externa: $pub" -ForegroundColor Green
    }
    catch {
        Write-Host "No se pudo obtener la IP pública (sin conexión o timeout)." -ForegroundColor Yellow
    }
}

# Resumen rápido del estado del equipo (uptime, memoria, discos)
function sysinfo {
    <#
    .SYNOPSIS
        Muestra un resumen de uptime del sistema, uso de memoria RAM y espacio disponible en discos.
    #>
    [CmdletBinding()]
    param()

    $os = Get-CimInstance Win32_OperatingSystem
    $uptime = (Get-Date) - $os.LastBootUpTime
    $totalRamGB = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeRamGB  = [Math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedRamGB  = [Math]::Round($totalRamGB - $freeRamGB, 2)
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -gt 0 }

    Write-Host "`n=== Sistema & Recursos ===" -ForegroundColor DarkCyan
    Write-Host ("Uptime: " + [int]$uptime.TotalDays + "d " + $uptime.Hours + "h " + $uptime.Minutes + "m") -ForegroundColor White
    Write-Host "RAM:    $usedRamGB GB usados / $totalRamGB GB totales ($freeRamGB GB libres)" -ForegroundColor White
    Write-Host "`n--- Espacio en Disco ---" -ForegroundColor Cyan
    $drives | Select-Object Name, @{Name='Usado (GB)'; Expression={[Math]::Round(($_.Used / 1GB), 1)}}, @{Name='Libre (GB)'; Expression={[Math]::Round(($_.Free / 1GB), 1)}}, @{Name='Total (GB)'; Expression={[Math]::Round((($_.Used + $_.Free) / 1GB), 1)}} | Format-Table -AutoSize
}


# Búsqueda en el historial de comandos de PowerShell
function hist {
    <#
    .SYNOPSIS
        Busca comandos en el historial de PowerShell por texto o muestra los últimos N.
    .EXAMPLE
        hist
        hist git
        hist sql -Last 30
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Filter,

        [Parameter(Position = 1)]
        [int]$Last = 25
    )
    $entries = Get-History
    if ($Filter) {
        $entries = $entries | Where-Object { $_.CommandLine -like "*$Filter*" }
    }
    $entries | Select-Object -Last $Last | Format-Table Id, CommandLine -AutoSize
}

# ==============================================================================
# INTEGRACIÓN DIFUSA CON FZF (SI ESTÁ INSTALADO)
# ==============================================================================

# Búsqueda difusa interactiva de archivos y apertura en Neovim
function fe {
    <#
    .SYNOPSIS
        Búsqueda interactiva difusa de archivos con fzf y apertura en Neovim.
    .EXAMPLE
        fe
        fe src/
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = "."
    )
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Host "● fzf no está instalado en el sistema." -ForegroundColor Yellow
        Write-Host "  Instálalo fácilmente con: winget install junegunn.fzf" -ForegroundColor DarkGray
        return
    }

    $selected = if (Get-Command fd -ErrorAction SilentlyContinue) {
        fd --type f --hidden --exclude .git . $Path | fzf --preview "head -n 40 {}" --header="[Enter] Abrir en Neovim | [ESC] Salir"
    } elseif (Get-Command rg -ErrorAction SilentlyContinue) {
        rg --files $Path 2>$null | fzf --preview "head -n 40 {}" --header="[Enter] Abrir en Neovim | [ESC] Salir"
    } else {
        Get-ChildItem -LiteralPath $Path -File -Recurse -Depth 4 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName | fzf --header="[Enter] Abrir en Neovim | [ESC] Salir"
    }

    if ($selected) {
        nvim $selected
    }
}
Set-Alias vf fe

# Búsqueda difusa interactiva de carpetas y navegación (cd)
function fcd {
    <#
    .SYNOPSIS
        Búsqueda interactiva difusa de carpetas con fzf y cambio automático de directorio.
    .EXAMPLE
        fcd
        fcd C:\Proyectos
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = "."
    )
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Host "● fzf no está instalado en el sistema." -ForegroundColor Yellow
        Write-Host "  Instálalo fácilmente con: winget install junegunn.fzf" -ForegroundColor DarkGray
        return
    }

    $dirs = if (Get-Command fd -ErrorAction SilentlyContinue) {
        fd --type d --hidden --exclude .git . $Path
    } else {
        Get-ChildItem -LiteralPath $Path -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    }

    $selected = $dirs | fzf --header="[Enter] Cambiar de directorio | [ESC] Salir"
    if ($selected -and (Test-Path -LiteralPath $selected)) {
        Set-Location -LiteralPath $selected
        Write-Host "● Posicionado en: $selected" -ForegroundColor Green
    }
}

# Búsqueda difusa interactiva en el historial de comandos
function fhist {
    <#
    .SYNOPSIS
        Búsqueda interactiva difusa en el historial de PowerShell con fzf.
    #>
    [CmdletBinding()]
    param()
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Host "● fzf no está instalado en el sistema." -ForegroundColor Yellow
        Write-Host "  Instálalo fácilmente con: winget install junegunn.fzf" -ForegroundColor DarkGray
        return
    }

    $historyFile = $null
    try { $historyFile = (Get-PSReadLineOption).HistorySavePath } catch { }
    $commands = if ($historyFile -and (Test-Path -LiteralPath $historyFile)) {
        Get-Content -LiteralPath $historyFile -Tail 1500
    } else {
        (Get-History | Select-Object -ExpandProperty CommandLine)
    }

    $selected = $commands | Select-Object -Unique | fzf --tac --header="[Enter] Ejecutar comando | [ESC] Salir"
    if ($selected) {
        Write-Host "Ejecutando: $selected" -ForegroundColor Cyan
        Invoke-Expression $selected
    }
}

# ==============================================================================
# DIAGNÓSTICO Y RENDIMIENTO DEL PERFIL (BENCHMARK)
# ==============================================================================

function profile-bench {
    <#
    .SYNOPSIS
        Mide el tiempo de carga milisegundo a milisegundo de cada módulo del perfil y el arranque total.
    .EXAMPLE
        profile-bench
        pbench
    #>
    [CmdletBinding()]
    param()

    $pDir = if ($global:ProfileDir) { $global:ProfileDir } else { Split-Path -Parent $PROFILE }
    $pD = Join-Path $pDir "profile.d"

    if (-not (Test-Path -LiteralPath $pD)) {
        Write-Warning "No se encontró el directorio de módulos '$pD'."
        return
    }

    Write-Host "`n=== Diagnóstico de Rendimiento del Perfil ($PROFILE) ===`n" -ForegroundColor DarkCyan

    $files = Get-ChildItem -Path "$pD\*.ps1" | Sort-Object Name
    $results = @()
    $totalMs = 0

    foreach ($f in $files) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $null = & { . $f.FullName } 2>$null
        } catch { }
        $sw.Stop()
        $ms = [Math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        $totalMs += $ms

        $statusColor = if ($ms -lt 40) { 'Green' } elseif ($ms -lt 100) { 'Yellow' } else { 'Red' }
        $barLength = [Math]::Min([Math]::Max([int]($ms / 5), 1), 25)
        $bar = ("█" * $barLength)

        $results += [PSCustomObject]@{
            Modulo = $f.Name
            Ms     = $ms
            Bar    = $bar
            Color  = $statusColor
        }
    }

    # Comprobación de arranque frío en subshell
    $coldSw = [System.Diagnostics.Stopwatch]::StartNew()
    $subProcess = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -Command `"`$PROFILE = '$PROFILE'; . '$pDir\Microsoft.PowerShell_profile.ps1'`"" -WindowStyle Hidden -PassThru -Wait
    $coldSw.Stop()
    $coldMs = [Math]::Round($coldSw.Elapsed.TotalMilliseconds, 0)

    foreach ($r in $results) {
        $nameCol = $r.Modulo.PadRight(28)
        $msCol   = ("$($r.Ms) ms").PadLeft(10)
        Write-Host "  $nameCol" -NoNewline -ForegroundColor White
        Write-Host " $msCol  " -NoNewline -ForegroundColor Cyan
        Write-Host $r.Bar -ForegroundColor $r.Color
    }

    Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Carga acumulada módulos:     " -NoNewline -ForegroundColor DarkGray
    Write-Host ("$([Math]::Round($totalMs, 1)) ms").PadLeft(8) -ForegroundColor Green
    Write-Host "  Arranque completo en frío:   " -NoNewline -ForegroundColor DarkGray
    Write-Host ("$coldMs ms").PadLeft(8) -ForegroundColor Cyan
    Write-Host ""
}
Set-Alias pbench profile-bench
Set-Alias profile-time profile-bench

# ==============================================================================
# DIFERENCIA VISUAL CON PORTAPAPELES: clip-diff (alias: vdiff-clip)
# ==============================================================================
function clip-diff {
    <#
    .SYNOPSIS
        Compara un archivo local contra el contenido actual del portapapeles usando Neovim en modo diff.
    .EXAMPLE
        clip-diff config.json
        clip-diff .\script.ps1
        vdiff-clip query.sql
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Error "No se encontró el archivo: $Path"
        return
    }

    $clipText = Get-Clipboard
    if (-not $clipText -or [string]::IsNullOrWhiteSpace(($clipText -join ""))) {
        Write-Warning "El portapapeles está vacío o no contiene texto."
        return
    }

    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
    $ext = [System.IO.Path]::GetExtension($resolved)
    $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "clip_diff_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))$ext")

    try {
        $clipJoined = if ($clipText -is [array]) { $clipText -join "`r`n" } else { [string]$clipText }
        [System.IO.File]::WriteAllText($tempFile, $clipJoined, [System.Text.Encoding]::UTF8)

        nvim -d $resolved $tempFile
    }
    finally {
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}
Set-Alias vdiff-clip clip-diff

# ==============================================================================
# EJECUCIÓN PERIÓDICA ESTILO UNIX: watch
# ==============================================================================
function watch {
    <#
    .SYNOPSIS
        Ejecuta un comando o scriptblock periódicamente cada N segundos refrescando la pantalla (estilo watch de Unix).
    .EXAMPLE
        watch "git status -s"
        watch "ports 8080" -n 5
        watch "Get-Process node" 1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Command,

        [Parameter(Position = 1)]
        [Alias('n')]
        [int]$Interval = 2
    )

    if ($Interval -lt 1) { $Interval = 1 }

    try {
        while ($true) {
            Clear-Host
            $nowStr = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Write-Host "Cada $($Interval)s: $Command" -NoNewline -ForegroundColor DarkCyan
            Write-Host "  [$nowStr]  (Ctrl+C para salir)`n" -ForegroundColor DarkGray

            try {
                Invoke-Expression $Command
            } catch {
                Write-Host "Error al ejecutar: $_" -ForegroundColor Red
            }

            Start-Sleep -Seconds $Interval
        }
    } catch [System.Management.Automation.PipelineStoppedException] {
        # Salida limpia con Ctrl+C
    }
}
Set-Alias watch-cmd watch

# ==============================================================================
# ELIMINACIÓN RÁPIDA Y SEGURA DE DIRECTORIOS: rmrf / rm-dir
# ==============================================================================
function Remove-ProfileDirectoryFast {
    param([string]$TargetDirectory)

    if (-not (Test-Path -LiteralPath $TargetDirectory)) { return $true }

    # 1. Intentar rmdir nativo de Windows (el más rápido con cmd)
    cmd /c "rmdir /s /q `"$TargetDirectory`"" 2>$null

    # 2. Si todavía existe (ej. rutas >260 caracteres o permisos especiales), fallback a Robocopy purge
    if (Test-Path -LiteralPath $TargetDirectory) {
        $emptyTemp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName())
        try {
            New-Item -ItemType Directory -Path $emptyTemp -Force | Out-Null
            robocopy $emptyTemp $TargetDirectory /purge /quiet /njh /njs /nc /ns /np | Out-Null
            cmd /c "rmdir /s /q `"$TargetDirectory`"" 2>$null
            if (Test-Path -LiteralPath $TargetDirectory) {
                Remove-Item -LiteralPath $TargetDirectory -Force -Recurse -ErrorAction SilentlyContinue
            }
        }
        finally {
            if (Test-Path -LiteralPath $emptyTemp) {
                cmd /c "rmdir /s /q `"$emptyTemp`"" 2>$null
            }
        }
    }

    return (-not (Test-Path -LiteralPath $TargetDirectory))
}

function Test-ProfileDirectorySafeToDelete {
    param([string]$FullPath)

    if ([string]::IsNullOrWhiteSpace($FullPath)) { return $false }

    $norm = [System.IO.Path]::GetFullPath($FullPath).TrimEnd('\', '/')
    $systemDrive = ($env:SystemDrive).TrimEnd('\', '/')

    # 1. Raíces de disco (ej. C:, D:)
    if ($norm -match '^[a-zA-Z]:$') { return $false }

    # 2. Carpetas críticas del sistema y del usuario
    $forbidden = @(
        $systemDrive,
        [System.IO.Path]::GetFullPath($env:SystemRoot).TrimEnd('\', '/'),
        [System.IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\', '/'),
        [System.IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd('\', '/')
    )
    if ($env:ProgramFilesx86) {
        $forbidden += [System.IO.Path]::GetFullPath($env:ProgramFilesx86).TrimEnd('\', '/')
    }

    foreach ($f in $forbidden) {
        if ($norm -ieq $f) { return $false }
    }

    # 3. Directorio actual o padre
    $current = (Get-Location).Path.TrimEnd('\', '/')
    if ($norm -ieq $current) { return $false }

    return $true
}

function Get-ProfileDirectorySize {
    param([string]$DirPath)
    try {
        $dirInfo = New-Object System.IO.DirectoryInfo($DirPath)
        $totalBytes = [long]0
        $fileCount = [long]0
        foreach ($file in $dirInfo.EnumerateFiles('*', [System.IO.SearchOption]::AllDirectories)) {
            $totalBytes += $file.Length
            $fileCount++
        }
        return @{ Bytes = $totalBytes; Count = $fileCount }
    } catch {
        return @{ Bytes = [long]0; Count = [long]0 }
    }
}

function Format-ProfileByteSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    } elseif ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    } elseif ($Bytes -ge 1KB) {
        return "{0:N1} KB" -f ($Bytes / 1KB)
    } else {
        return "$Bytes bytes"
    }
}

function rmrf {
    <#
    .SYNOPSIS
        Eliminación rápida y segura de directorios en Windows (10x más rápido que Remove-Item).
    .DESCRIPTION
        - Soporta una o múltiples carpetas a la vez (y comodines).
        - Utiliza rmdir /s /q nativo de Windows con fallback a Robocopy para evitar bloqueos por rutas largas (>260 caracteres).
        - Calcula y reporta el espacio en disco liberado.
        - Con -Find / -Recurse <nombre>: busca recursivamente todas las carpetas con ese nombre en subdirectorios (ej. 'node_modules', 'bin', 'obj') para eliminarlas.
        - Con -Force / -f: omite la confirmación interactiva.
        - Sin parámetros: si fzf está disponible, abre un selector interactivo de carpetas en la ubicación actual.
    .EXAMPLE
        rmrf node_modules
        rmrf bin obj dist
        rmrf ./temp_* -Force
        rmrf -Find node_modules
        rmrf -Find bin, obj
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Path,

        [Alias('Recurse', 'Search')]
        [string[]]$Find,

        [Alias('f', 'Yes')]
        [switch]$Force,

        [Alias('DryRun')]
        [switch]$WhatIf
    )

    # ---------------------------------------------------------
    # CASO 1: Búsqueda recursiva (-Find / -Recurse)
    # ---------------------------------------------------------
    if ($Find -and $Find.Count -gt 0) {
        Write-Host "● Escaneando subdirectorios en busca de: $($Find -join ', ')..." -ForegroundColor DarkCyan
        $currentDir = Get-Item -LiteralPath (Get-Location).Path
        $foundDirs = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
        $queue = [System.Collections.Generic.Queue[System.IO.DirectoryInfo]]::new()
        $queue.Enqueue($currentDir)

        while ($queue.Count -gt 0) {
            $parent = $queue.Dequeue()
            try {
                foreach ($sub in $parent.GetDirectories()) {
                    $matched = $false
                    foreach ($pattern in $Find) {
                        if ($sub.Name -like $pattern) {
                            $foundDirs.Add($sub)
                            $matched = $true
                            break
                        }
                    }
                    if (-not $matched -and $sub.Name -ne '.git') {
                        $queue.Enqueue($sub)
                    }
                }
            } catch {}
        }

        if ($foundDirs.Count -eq 0) {
            Write-Host "● No se encontraron carpetas coincidentes en este árbol de directorios." -ForegroundColor Yellow
            return
        }

        Write-Host "`nCarpetas encontradas ($($foundDirs.Count)):" -ForegroundColor Cyan
        $totalBytes = [long]0
        $items = @()
        foreach ($d in $foundDirs) {
            $sz = Get-ProfileDirectorySize $d.FullName
            $totalBytes += $sz.Bytes
            $rel = ($d.FullName.Substring($currentDir.FullName.Length)).TrimStart('\', '/')
            $items += [PSCustomObject]@{
                FullName = $d.FullName
                RelPath  = $rel
                Bytes    = $sz.Bytes
                SizeStr  = (Format-ProfileByteSize $sz.Bytes)
            }
            Write-Host ("  • {0,-45} {1,10}" -f $rel, (Format-ProfileByteSize $sz.Bytes)) -ForegroundColor White
        }
        Write-Host "  $('-' * 57)" -ForegroundColor DarkGray
        Write-Host ("  Total espacio a liberar: {0}`n" -f (Format-ProfileByteSize $totalBytes)) -ForegroundColor Yellow

        if ($WhatIf) {
            Write-Host "Modo WhatIf: no se ha eliminado ninguna carpeta." -ForegroundColor Cyan
            return
        }

        if (-not $Force) {
            $ans = Read-Host "¿Deseas eliminar estas $($foundDirs.Count) carpetas? [s/N]"
            if ($ans -notmatch '^(s|si|y|yes)$') {
                Write-Host "Operación cancelada." -ForegroundColor DarkGray
                return
            }
        }

        $deletedCount = 0
        $freedBytes = [long]0
        foreach ($it in $items) {
            if (-not (Test-ProfileDirectorySafeToDelete $it.FullName)) {
                Write-Warning "Omitiendo carpeta protegida: $($it.RelPath)"
                continue
            }
            $ok = Remove-ProfileDirectoryFast $it.FullName
            if ($ok) {
                $deletedCount++
                $freedBytes += $it.Bytes
            } else {
                Write-Error "No se pudo eliminar: $($it.RelPath)"
            }
        }

        Write-Host "`n✔ Eliminadas $deletedCount carpetas. Espacio liberado: $(Format-ProfileByteSize $freedBytes)" -ForegroundColor Green
        return
    }

    # ---------------------------------------------------------
    # CASO 2: Sin argumentos -> Selección interactiva con fzf
    # ---------------------------------------------------------
    if (-not $Path -or $Path.Count -eq 0) {
        if (Get-Command fzf -ErrorAction SilentlyContinue) {
            $subDirs = Get-ChildItem -Directory | Where-Object { $_.Name -ne '.git' }
            if (-not $subDirs -or $subDirs.Count -eq 0) {
                Write-Warning "No hay carpetas en la ubicación actual."
                return
            }
            $listForFzf = @()
            foreach ($sd in $subDirs) {
                $sz = Get-ProfileDirectorySize $sd.FullName
                $listForFzf += ("{0,-35} | {1,10}" -f $sd.Name, (Format-ProfileByteSize $sz.Bytes))
            }
            $selected = $listForFzf | fzf -m --header="[Tab/Shift+Tab] Marcar múltiples | [Enter] Eliminar seleccionadas | [ESC] Salir"
            if (-not $selected) { return }

            $targets = @()
            foreach ($line in ($selected -split "`r?`n")) {
                if ($line) {
                    $dirName = ($line -split '\|')[0].Trim()
                    if ($dirName) { $targets += $dirName }
                }
            }
            $Path = $targets
        } else {
            $ans = Read-Host "Introduce la ruta de la carpeta a eliminar"
            if (-not $ans) { return }
            $Path = @($ans)
        }
    }

    # ---------------------------------------------------------
    # CASO 3: Eliminación de las rutas especificadas
    # ---------------------------------------------------------
    $targetsToDelete = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
    foreach ($p in $Path) {
        $cleanP = $p.Trim().TrimEnd('\', '/')
        if ($cleanP -in @('', '.', '..')) {
            Write-Error "Operación denegada por seguridad: no se permite eliminar el directorio actual o padre ('$p')."
            continue
        }

        # Si es una ruta directa existente
        if (Test-Path -LiteralPath $p) {
            $item = Get-Item -LiteralPath $p
            if ($item.PSIsContainer) {
                $targetsToDelete.Add($item)
            } else {
                Write-Warning "'$p' es un archivo, no un directorio. Usa Remove-Item para archivos."
            }
        } elseif ($p -match '[*?]') {
            # Si contiene comodines (ej. temp_*)
            $resolved = Get-ChildItem -Path $p -Directory -ErrorAction SilentlyContinue
            if ($resolved) {
                foreach ($r in $resolved) {
                    $targetsToDelete.Add($r)
                }
            } else {
                Write-Warning "No se encontraron carpetas con el patrón: '$p'"
            }
        } else {
            Write-Warning "No existe la carpeta: '$p'"
        }
    }

    if ($targetsToDelete.Count -eq 0) {
        return
    }

    # Medir y validar cada carpeta
    $validTargets = @()
    $totalBytes = [long]0
    foreach ($t in $targetsToDelete) {
        if (-not (Test-ProfileDirectorySafeToDelete $t.FullName)) {
            Write-Error "Operación denegada por seguridad: no se permite eliminar directorios raíz o del sistema ($($t.FullName))"
            continue
        }
        $sz = Get-ProfileDirectorySize $t.FullName
        $totalBytes += $sz.Bytes
        $validTargets += [PSCustomObject]@{
            FullName = $t.FullName
            Name     = $t.Name
            Bytes    = $sz.Bytes
            SizeStr  = (Format-ProfileByteSize $sz.Bytes)
        }
    }

    if ($validTargets.Count -eq 0) { return }

    if ($WhatIf) {
        Write-Host "Modo WhatIf: Se eliminarían $($validTargets.Count) carpetas ($(Format-ProfileByteSize $totalBytes)):" -ForegroundColor Cyan
        foreach ($vt in $validTargets) {
            Write-Host "  • $($vt.Name) ($($vt.SizeStr))" -ForegroundColor White
        }
        return
    }

    if (-not $Force) {
        if ($validTargets.Count -eq 1) {
            $vt = $validTargets[0]
            $confirm = Read-Host "¿Eliminar la carpeta '$($vt.Name)' ($($vt.SizeStr))? [s/N]"
        } else {
            Write-Host "Carpetas a eliminar ($($validTargets.Count)):" -ForegroundColor Cyan
            foreach ($vt in $validTargets) {
                Write-Host "  • $($vt.Name) ($($vt.SizeStr))" -ForegroundColor White
            }
            Write-Host "Total a liberar: $(Format-ProfileByteSize $totalBytes)" -ForegroundColor Yellow
            $confirm = Read-Host "¿Deseas eliminar estas $($validTargets.Count) carpetas? [s/N]"
        }

        if ($confirm -notmatch '^(s|si|y|yes)$') {
            Write-Host "Operación cancelada." -ForegroundColor DarkGray
            return
        }
    }

    $deletedCount = 0
    $freedBytes = [long]0
    foreach ($vt in $validTargets) {
        Write-Host "Eliminando '$($vt.Name)' ($($vt.SizeStr))..." -NoNewline -ForegroundColor DarkGray
        $ok = Remove-ProfileDirectoryFast $vt.FullName
        if ($ok) {
            Write-Host " [OK]" -ForegroundColor Green
            $deletedCount++
            $freedBytes += $vt.Bytes
        } else {
            Write-Host " [ERROR]" -ForegroundColor Red
            Write-Error "No se pudo eliminar completamente la carpeta '$($vt.FullName)'."
        }
    }

    Write-Host "✔ Eliminadas $deletedCount carpeta(s). Espacio liberado: $(Format-ProfileByteSize $freedBytes)" -ForegroundColor Green
}

Set-Alias rm-dir     rmrf
Set-Alias purge-dir  rmrf
Set-Alias rmdir-fast rmrf
