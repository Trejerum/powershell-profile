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
