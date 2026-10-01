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

# ==============================================================================
# 2. NAVEGACIÓN RÁPIDA (PROYECTOS & ENTORNO)
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

# Subir niveles de directorio rápidamente
function ..   { Set-Location .. }
function ...  { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

# Crear directorio y entrar inmediatamente
function mkcd {
    <#
    .SYNOPSIS
        Crea una carpeta (y sus directorios padres si no existen) y navega a ella de inmediato.
    .EXAMPLE
        mkcd backend/api/v2
    #>
    param([Parameter(Mandatory = $true, Position = 0)][string]$Path)
    [void](New-Item -ItemType Directory -Path $Path -Force)
    Set-Location $Path
}

# Abrir explorador de archivos en la ruta actual o indicada
function open {
    <#
    .SYNOPSIS
        Abre el Explorador de archivos de Windows en la carpeta actual o en la ruta indicada.
    .EXAMPLE
        open
        open ./logs
    #>
    param([Parameter(Position = 0)][string]$Path = ".")
    Invoke-Item $Path
}
Set-Alias o open

# Salto dinámico a cualquier subproyecto dentro de Documentos\Proyectos con autocompletado
function proj {
    <#
    .SYNOPSIS
        Navega dinámicamente a cualquier subproyecto dentro de Documentos\Proyectos.
    .EXAMPLE
        proj
        proj RSGA
        proj CINFA
    #>
    param(
        [Parameter(Position = 0)]
        [string]$Name
    )
    $projDir = Join-Path $HOME "Documentos\Proyectos"
    if (-not (Test-Path -LiteralPath $projDir)) {
        Write-Warning "El directorio '$projDir' no existe."
        return
    }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Host "Proyectos disponibles en $projDir`:" -ForegroundColor DarkCyan
        Get-ChildItem -LiteralPath $projDir -Directory | Select-Object -ExpandProperty Name | ForEach-Object {
            Write-Host "  • $_" -ForegroundColor White
        }
        return
    }
    $target = Join-Path $projDir $Name
    if (Test-Path -LiteralPath $target) {
        Set-Location $target
    } else {
        $match = Get-ChildItem -LiteralPath $projDir -Directory | Where-Object { $_.Name -like "*$Name*" } | Select-Object -First 1
        if ($match) {
            Set-Location $match.FullName
        } else {
            Write-Host "● No se encontró ningún proyecto que coincida con '$Name' en $projDir" -ForegroundColor Yellow
        }
    }
}
Register-ArgumentCompleter -CommandName proj -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $projDir = Join-Path $HOME "Documentos\Proyectos"
    if (Test-Path -LiteralPath $projDir) {
        Get-ChildItem -LiteralPath $projDir -Directory |
            Where-Object { $_.Name -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', "Proyecto: $($_.Name)") }
    }
}

# Recargar el perfil de PowerShell en la sesión actual
function reload {
    <#
    .SYNOPSIS
        Recarga el perfil activo de PowerShell en la consola actual.
    #>
    . $PROFILE
    Write-Host "✓ Perfil de PowerShell recargado correctamente." -ForegroundColor Green
}
Set-Alias rel reload
Set-Alias rprof reload
Set-Alias reload-profile reload

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

# Interfaz TUI interactiva de Lazygit
if (Get-Command lazygit -ErrorAction SilentlyContinue) {
    Set-Alias lg lazygit
}

# Añadir todo y crear commit en un único paso
function gcom {
    <#
    .SYNOPSIS
        Prepara todos los cambios (git add -A) y realiza el commit con el mensaje indicado.
    .EXAMPLE
        gcom "feat: implementar nuevo endpoint de clientes"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )
    git add -A
    git commit -m $Message
}

# Crear una nueva rama y posicionarse en ella inmediatamente
function gcob {
    <#
    .SYNOPSIS
        Crea y cambia a una nueva rama de Git (git checkout -b / git switch -c).
    .EXAMPLE
        gcob feature/auth-jwt
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Branch
    )
    git checkout -b $Branch
}
Set-Alias gswc gcob

# Listar ramas locales ordenadas por fecha de último commit con tiempo relativo
function gb {
    <#
    .SYNOPSIS
        Lista ramas locales ordenadas por fecha de actividad reciente.
    #>
    git branch --sort=-committerdate --format="%(color:yellow)%(refname:short)%(color:reset) %(color:cyan)(%(committerdate:relative))%(color:reset) - %(subject)"
}

# Deshacer el último commit manteniendo todos los cambios en el árbol de trabajo (soft reset)
function gundo {
    <#
    .SYNOPSIS
        Deshace el último commit pero conserva los cambios preparados (staged) en el árbol de trabajo.
    #>
    git reset --soft HEAD~1
    Write-Host "✓ Último commit deshecho (los cambios siguen en el área de preparación/staged)." -ForegroundColor Green
}

# Comparar diferencias de un archivo en Neovim con vista split (:diffsplit)
function vd {
    <#
    .SYNOPSIS
        Abre el diff de un archivo en Neovim con vista paralela split (:diffsplit).
    .EXAMPLE
        vd Program.cs
        vd
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$File
    )
    if ($File) {
        nvim -d $File
    } else {
        git difftool -t nvimdiff -y
    }
}

# Dashboard multi-entorno para repositorios SGA (RSGA, RSGA_2, RSGA_3) con salto rápido
function repo-status {
    <#
    .SYNOPSIS
        Muestra un dashboard en tiempo real de los entornos/clones Git de SGA con soporte de salto rápido.
    .EXAMPLE
        repos           # Muestra el estado de todos los clones
        repos -Fetch    # Hace git fetch silencioso antes de evaluar (alias: -f)
        repos 1         # Salta a RSGA
        repos 2         # Salta a RSGA_2
        repos 3         # Salta a RSGA_3
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Target,

        [Alias('f')]
        [switch]$Fetch,

        [Parameter()]
        [string]$Path = $script:SgaRoot
    )

    # 1. Soporte de salto directo si se pasa un identificador
    if ($Target) {
        $cleanTarget = $Target.Trim().ToLower()
        switch ($cleanTarget) {
            { $_ -in @('1', 'rsga', 'sga') } {
                rsga
                Write-Host "● Posicionado en [RSGA]" -ForegroundColor Green
                return
            }
            { $_ -in @('2', 'rsga2', 'rsga_2') } {
                rsga2
                Write-Host "● Posicionado en [RSGA_2]" -ForegroundColor Green
                return
            }
            { $_ -in @('3', 'rsga3', 'rsga_3') } {
                rsga3
                Write-Host "● Posicionado en [RSGA_3]" -ForegroundColor Green
                return
            }
        }
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "El directorio '$Path' no existe."
        return
    }

    $dirs = @(Get-ChildItem -LiteralPath $Path -Directory | Where-Object { Test-Path (Join-Path $_.FullName '.git') })
    if ($dirs.Count -eq 0) {
        Write-Host "● No se encontraron repositorios Git en $Path." -ForegroundColor Yellow
        return
    }

    if ($Fetch) {
        Write-Host "Sincronizando estado remoto (git fetch)..." -ForegroundColor DarkGray
        foreach ($d in $dirs) {
            git -C $d.FullName fetch -q 2>$null
        }
    }

    Write-Host "`n=== Estado de Entornos SGA ===`n" -ForegroundColor DarkCyan

    $idx = 1
    foreach ($d in $dirs) {
        $p = $d.FullName
        $branch = (git -C $p branch --show-current 2>$null)
        if (-not $branch) { $branch = 'DETACHED' }

        $statusLines = @(git -C $p status --porcelain 2>$null)
        $staged = @($statusLines | Where-Object { $_ -match '^[MADRC]' }).Count
        $modified = @($statusLines | Where-Object { $_ -match '^.[MD]' }).Count
        $untracked = @($statusLines | Where-Object { $_ -match '^\?\?' }).Count

        $statusParts = @()
        if ($staged -gt 0)    { $statusParts += "+$staged staged" }
        if ($modified -gt 0)  { $statusParts += "~$modified mod" }
        if ($untracked -gt 0) { $statusParts += "!$untracked new" }

        $localStatus = if ($statusParts.Count -gt 0) { $statusParts -join ', ' } else { 'Limpio' }
        $localColor  = if ($statusParts.Count -gt 0) { 'Yellow' } else { 'Green' }

        $upstreamCounts = (git -C $p rev-list --left-right --count 'HEAD...@{upstream}' 2>$null)
        $syncStatus = 'Sin tracking'
        $syncColor = 'DarkGray'
        if ($upstreamCounts) {
            $parts = $upstreamCounts.Trim().Split([char]9)
            if ($parts.Count -ge 2) {
                $ahead = [int]$parts[0]
                $behind = [int]$parts[1]
                if ($ahead -eq 0 -and $behind -eq 0) {
                    $syncStatus = 'Al día'
                    $syncColor = 'Green'
                } elseif ($ahead -gt 0 -and $behind -eq 0) {
                    $syncStatus = "↑ $ahead pendiente(s)"
                    $syncColor = 'Cyan'
                } elseif ($ahead -eq 0 -and $behind -gt 0) {
                    $syncStatus = "↓ $behind por bajar"
                    $syncColor = 'Magenta'
                } else {
                    $syncStatus = "↑ $ahead ↓ $behind (divergente)"
                    $syncColor = 'Red'
                }
            }
        }

        $lastCommit = (git -C $p log -1 --format='%h (%cr) %s' 2>$null)
        if ($lastCommit -and $lastCommit.Length -gt 60) {
            $lastCommit = $lastCommit.Substring(0, 57) + '...'
        }

        $tag = "[$idx] $($d.Name)".PadRight(12)
        Write-Host $tag -ForegroundColor Yellow -NoNewline
        Write-Host (" " + $branch).PadRight(32) -ForegroundColor Cyan -NoNewline
        Write-Host " | " -ForegroundColor DarkGray -NoNewline
        Write-Host $localStatus.PadRight(18) -ForegroundColor $localColor -NoNewline
        Write-Host " | " -ForegroundColor DarkGray -NoNewline
        Write-Host $syncStatus -ForegroundColor $syncColor
        if ($lastCommit) {
            Write-Host "     └─ $lastCommit" -ForegroundColor DarkGray
        }

        $idx++
    }

    Write-Host "`nTip: Usa 'repos <1|2|3>' para saltar directamente al clon deseado o '-f' para refrescar origin.`n" -ForegroundColor DarkGray
}
Set-Alias repos repo-status
Set-Alias sga-status repo-status

# ==============================================================================
# 4. AYUDA RÁPIDA DEL PERFIL (CENTRO DE MANDO)
# ==============================================================================

function Show-ProfileHelp {
    <#
    .SYNOPSIS
        Muestra la guía completa de atajos y herramientas del perfil con filtros y fichas de detalle.
    .EXAMPLE
        phelp
        phelp git
        phelp sql
        phelp q
        phelp vmod
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Filter
    )

    $commands = @(
        # 1. Navegación & Entorno
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "sga"; Sintaxis = "sga"; Detalle = "Navega a la raíz del proyecto SGA (`$HOME\Documentos\Proyectos\SGA)"; Ejemplos = @("sga") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "rsga"; Sintaxis = "rsga"; Detalle = "Navega al repositorio principal RSGA"; Ejemplos = @("rsga") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "rsga2"; Sintaxis = "rsga2"; Detalle = "Navega al entorno o copia secundaria RSGA_2"; Ejemplos = @("rsga2") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "rsga3"; Sintaxis = "rsga3"; Detalle = "Navega al entorno o copia terciaria RSGA_3"; Ejemplos = @("rsga3") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "proj"; Sintaxis = "proj [nombre]"; Detalle = "Navega a cualquier subproyecto en Documentos\Proyectos con autocompletado <Tab> (sin argumentos lista proyectos)"; Ejemplos = @("proj", "proj RSGA", "proj CINFA") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "profile"; Sintaxis = "profile"; Detalle = "Navega a la carpeta física del perfil de PowerShell"; Ejemplos = @("profile") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "notes"; Sintaxis = "notes"; Detalle = "Navega a la carpeta de notas personales (`$HOME\Documentos\Notes)"; Ejemplos = @("notes") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = ".."; Sintaxis = "..  |  ...  |  ...."; Detalle = "Sube 1, 2 o 3 niveles de directorio en el árbol del sistema de archivos"; Ejemplos = @("..", "...", "....") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "mkcd"; Sintaxis = "mkcd <carpeta>"; Detalle = "Crea un directorio (incluyendo padres si no existen) y navega dentro de él de inmediato"; Ejemplos = @("mkcd backend/api/v2") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "open"; Sintaxis = "open [ruta]"; Detalle = "Abre la carpeta actual o la ruta indicada en el Explorador de archivos de Windows (alias: o)"; Ejemplos = @("open", "open .", "open ./logs") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "reload"; Sintaxis = "reload"; Detalle = "Recarga el perfil de PowerShell en la consola activa (alias: rel, rprof, reload-profile)"; Ejemplos = @("reload", "rel") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "ep"; Sintaxis = "ep"; Detalle = "Abre `$PROFILE en Neovim para editarlo (alias: edit-profile)"; Ejemplos = @("ep") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "en"; Sintaxis = "en"; Detalle = "Abre la carpeta de configuración de Neovim (~AppData\Local\nvim) en Neovim (alias: edit-nvim)"; Ejemplos = @("en") }

        # 2. Archivos & Búsqueda
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "v"; Sintaxis = "v [ruta] | <cmd> | v"; Detalle = "Wrapper inteligente de Neovim: abre ficheros o vuelca salidas de pipeline a buffer temporal"; Ejemplos = @("v Program.cs", "gs | v", "q 'SELECT TOP 10 * FROM Articulos' | v") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "vrg"; Sintaxis = "vrg <patrón> [ruta]"; Detalle = "Busca texto con Ripgrep y abre resultados directamente en Neovim dentro de la lista Quickfix (:copen)"; Ejemplos = @("vrg 'Get-ActiveSql'", "vrg 'kill-port' src/") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "touch"; Sintaxis = "touch <archivo...>"; Detalle = "Crea archivos vacíos o actualiza su fecha de modificación al estilo Unix (crea carpetas si faltan)"; Ejemplos = @("touch nuevo.sql", "touch test1.cs test2.cs") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "ff"; Sintaxis = "ff <patrón> [ruta]"; Detalle = "Búsqueda recursiva ultrarrápida de archivos por nombre usando Ripgrep o fallback nativo"; Ejemplos = @("ff 'Controller'", "ff '*.sql' database/") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "which"; Sintaxis = "which <comando>"; Detalle = "Muestra la ruta absoluta, tipo (Cmdlet, Alias, App) y versión de cualquier comando ejecutable"; Ejemplos = @("which nvim", "which git", "which q") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "head"; Sintaxis = "head <archivo> [-n 10]"; Detalle = "Muestra las primeras N líneas de un archivo o flujo de datos sin cargarlo todo en memoria"; Ejemplos = @("head error.log", "head error.log -n 25") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "tail"; Sintaxis = "tail <archivo> [-n 10]"; Detalle = "Muestra las últimas N líneas de un archivo o log (útil para inspeccionar errores recientes)"; Ejemplos = @("tail error.log", "tail error.log -n 50") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "extract"; Sintaxis = "extract <archivo> [dest]"; Detalle = "Descomprime automáticamente archivos (.zip, .tar.gz, .7z, .rar) usando 7z, tar o Expand-Archive"; Ejemplos = @("extract release.zip", "extract backup.7z ./salida") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "cb"; Sintaxis = "cb [texto] | <cmd> | cb"; Detalle = "Copia texto o cualquier objeto de la consola directamente al portapapeles de Windows"; Ejemplos = @("cb 'Texto a copiar'", "Get-Location | cb") }

        # 3. Git & Lazygit
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "lg"; Sintaxis = "lg"; Detalle = "Lanza la interfaz de terminal interactiva (TUI) de Lazygit en el repositorio actual"; Ejemplos = @("lg") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "repo-status"; Sintaxis = "repo-status [-f] [1|2|3]"; Detalle = "Dashboard en vivo de entornos RSGA/RSGA_2/RSGA_3 con salto rápido (alias: repos)"; Ejemplos = @("repos", "repos -f", "repos 2", "repos rsga") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "g"; Sintaxis = "g <args...>"; Detalle = "Atajo universal para Git con soporte completo de autocompletado en posh-git (ramas, flags)"; Ejemplos = @("g switch main", "g diff") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gs"; Sintaxis = "gs"; Detalle = "Estado compacto y legible del repositorio (git status -sb)"; Ejemplos = @("gs") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "ga"; Sintaxis = "ga"; Detalle = "Añade todos los cambios locales al índice (git add .)"; Ejemplos = @("ga") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gcom"; Sintaxis = "gcom '<mensaje>'"; Detalle = "Añade todos los cambios (git add -A) y crea el commit en un solo paso rápido"; Ejemplos = @("gcom 'fix(api): corregir validacion de stock'") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gcob"; Sintaxis = "gcob <nueva-rama>"; Detalle = "Crea una nueva rama y cambia a ella de inmediato (git checkout -b / git switch -c, alias: gswc)"; Ejemplos = @("gcob feature/soporte-multiterminal") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gb"; Sintaxis = "gb"; Detalle = "Lista las ramas locales ordenadas por fecha del último commit con tiempo relativo"; Ejemplos = @("gb") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gp"; Sintaxis = "gp / gf"; Detalle = "Descarga y fusiona cambios remotos (git pull / git fetch)"; Ejemplos = @("gp", "gf origin") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gpush"; Sintaxis = "gpush"; Detalle = "Sube los commits locales al repositorio remoto (git push)"; Ejemplos = @("gpush") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gpsup"; Sintaxis = "gpsup [remoto]"; Detalle = "Publica la rama actual configurando el tracking remoto (git push -u origin <rama>, alias: gpu)"; Ejemplos = @("gpsup", "gpu") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gco"; Sintaxis = "gco <rama/archivo>"; Detalle = "Cambia de rama o restaura ficheros con autocompletado inteligente con <Tab>"; Ejemplos = @("gco develop", "gco main") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "glog"; Sintaxis = "glog"; Detalle = "Historial gráfico compacto y coloreado de los últimos 10 commits"; Ejemplos = @("glog") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gundo"; Sintaxis = "gundo"; Detalle = "Deshace el último commit conservando todos los cambios preparados (staged) en el árbol de trabajo"; Ejemplos = @("gundo") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gss"; Sintaxis = "gss [mensaje]"; Detalle = "Guarda cambios en el stash con timestamp y rama activa (incluye archivos sin rastrear)"; Ejemplos = @("gss", "gss 'refactor conexion'") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gsl"; Sintaxis = "gsl"; Detalle = "Lista los stashes guardados con fechas relativas y colores legibles"; Ejemplos = @("gsl") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gsp"; Sintaxis = "gsp [índice]"; Detalle = "Aplica y retira el stash indicado (por defecto el último stash@{0})"; Ejemplos = @("gsp", "gsp 1") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "vmod"; Sintaxis = "vmod [-l] [-Splits]"; Detalle = "Muestra cambios coloreados y los abre en Neovim en pestañas con Quickfix (alias: vdiff)"; Ejemplos = @("vmod", "vmod -List", "vmod -Splits") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "vd"; Sintaxis = "vd [archivo]"; Detalle = "Abre el diff de un archivo en Neovim con vista dividida en paralelo (:diffsplit)"; Ejemplos = @("vd Program.cs", "vd") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "agy-review-pr"; Sintaxis = "agy-review-pr <rama>"; Detalle = "Audita y analiza una PR con Antigravity comparando contra develop sin cambiar de rama"; Ejemplos = @("agy-review-pr feature/login", "agy-review-pr bugfix/320 main -Print") }

        # 4. Sistema & Red
        [PSCustomObject]@{ Categoria = "Sistema & Red"; Comando = "ports"; Sintaxis = "ports [filtro]"; Detalle = "Muestra todos los puertos TCP en escucha con su PID y nombre de proceso (alias: listening)"; Ejemplos = @("ports", "ports 4200", "ports sql") }
        [PSCustomObject]@{ Categoria = "Sistema & Red"; Comando = "kill-port"; Sintaxis = "kill-port <puerto...>"; Detalle = "Finaliza los procesos que bloquean uno o varios puertos TCP (alias: kp)"; Ejemplos = @("kp 4200", "kp 5000, 7000") }
        [PSCustomObject]@{ Categoria = "Sistema & Red"; Comando = "psfind"; Sintaxis = "psfind <nombre>"; Detalle = "Busca procesos en ejecución mostrando PID, memoria en MB y consumo de CPU (alias: psgrep)"; Ejemplos = @("psfind node", "psfind sql", "psfind dotnet") }
        [PSCustomObject]@{ Categoria = "Sistema & Red"; Comando = "myip"; Sintaxis = "myip"; Detalle = "Muestra la dirección IP local de la tarjeta de red activa y la IP pública externa"; Ejemplos = @("myip") }
        [PSCustomObject]@{ Categoria = "Sistema & Red"; Comando = "sysinfo"; Sintaxis = "sysinfo"; Detalle = "Resumen de salud del equipo: uptime de Windows, uso de memoria RAM y espacio libre en discos"; Ejemplos = @("sysinfo") }

        # 5. SQL Server Toolkit
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "q"; Sintaxis = "q <query/.sql> [switches]"; Detalle = "Motor ultrarrápido ADO.NET (switches: -Grid, -Clip, -Csv, -Json, -DryRun, -Timeout N)"; Ejemplos = @("q 'SELECT TOP 10 * FROM Articulos'", "q ./cambios.sql -DryRun", "q 'SELECT * FROM Clientes' -Grid") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "qconnect"; Sintaxis = "qconnect [srv] [bd]"; Detalle = "Abre una conexión persistente reutilizable de alto rendimiento (indicador [BD ⚡] en prompt)"; Ejemplos = @("qconnect", "qconnect 'PORT1220\\SQL_SERVER' 'SGA'") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "qdisc"; Sintaxis = "qdisc"; Detalle = "Cierra la sesión persistente activa y vuelve a conexiones transitorias (alias: qdisconnect)"; Ejemplos = @("qdisc") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "use"; Sintaxis = "use <BaseDatos>"; Detalle = "Cambia la base de datos activa al vuelo con autocompletado y refresco de caché"; Ejemplos = @("use SGA", "use RSGA_DEV") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "dbs"; Sintaxis = "dbs [-Grid] [-Clip]"; Detalle = "Lista todas las bases de datos de la instancia SQL actual con tamaño en MB y estado (alias: show-dbs)"; Ejemplos = @("dbs", "dbs -Grid") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "tables"; Sintaxis = "tables [filtro]"; Detalle = "Lista todas las tablas de la BD activa con su esquema y recuento exacto de filas (sin scan)"; Ejemplos = @("tables", "tables Articulos", "tables -Grid") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "views"; Sintaxis = "views [filtro]"; Detalle = "Lista todas las vistas de la BD activa con su fecha de creación y última modificación"; Ejemplos = @("views", "views vStock") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "top"; Sintaxis = "top <tabla> [n]"; Detalle = "Consulta rápida de las primeras N filas (por defecto 20) con soporte -Grid, -Clip, -Json"; Ejemplos = @("top Articulos", "top Articulos 50 -Grid", "top Clientes 10 -Clip") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "desc"; Sintaxis = "desc <tabla>"; Detalle = "Describe columnas, tipos de datos, nulabilidad y defaults de una tabla o vista"; Ejemplos = @("desc Articulos", "desc dbo.Clientes -Grid") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "count"; Sintaxis = "count <tabla>"; Detalle = "Recuento ultrarrápido de filas en 0 ms usando particiones DMVs (sys.dm_db_partition_stats)"; Ejemplos = @("count Articulos", "count MovimientosStock") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "find-table"; Sintaxis = "find-table <patrón>"; Detalle = "Busca tablas y vistas por coincidencia de texto en el nombre"; Ejemplos = @("find-table Stock", "find-table Pedido -Grid") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "find-col"; Sintaxis = "find-col <columna>"; Detalle = "Busca en qué tablas y vistas existe una columna dada en toda la base de datos"; Ejemplos = @("find-col IdArticulo", "find-col FechaCreacion") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "find-code"; Sintaxis = "find-code <patrón>"; Detalle = "Busca texto dentro del DDL de SPs, Vistas, Funciones y Triggers (alias: find-sp, grep-sql)"; Ejemplos = @("find-code 'usp_Calcular'", "find-sp 'ActualizarStock' -Grid") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "who"; Sintaxis = "who [-Grid]"; Detalle = "Monitor en tiempo real de sesiones activas de usuario, bloqueos (blocking) y consultas"; Ejemplos = @("who", "who -Grid") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "see"; Sintaxis = "see <objeto> [-Clip]"; Detalle = "Muestra el código fuente DDL de un SP, Vista, Función o Trigger en consola"; Ejemplos = @("see usp_RecalcularStock", "see vArticulosActivos -Clip") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "see-idx"; Sintaxis = "see-idx <tabla>"; Detalle = "Inspecciona los índices definidos, tipo (Clustered/Nonclustered) y columnas clave"; Ejemplos = @("see-idx Articulos") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "q2excel"; Sintaxis = "q2excel <query/.sql>"; Detalle = "Ejecuta una consulta SQL y la abre directamente en Excel en formato español (alias: qexcel)"; Ejemplos = @("q2excel 'SELECT * FROM Articulos'", "qexcel ./informe.sql") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "open-sql"; Sintaxis = "open-sql <objeto>"; Detalle = "Extrae el DDL de un objeto SQL y lo abre en Neovim listo para inspeccionar o editar"; Ejemplos = @("open-sql usp_GenerarPedido") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "vsql"; Sintaxis = "vsql"; Detalle = "Scratchpad SQL temporal en Neovim con opción de ejecución directa contra la BD al guardar (:wq)"; Ejemplos = @("vsql") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "qfmt"; Sintaxis = "qfmt <query> [-Clip]"; Detalle = "Formatea e indenta una consulta SQL desordenada para mayor claridad y limpieza"; Ejemplos = @("qfmt 'SELECT a,b FROM t WHERE x=1' -Clip") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "qclip"; Sintaxis = "qclip <query/.sql>"; Detalle = "Ejecuta la consulta SQL y copia directamente los resultados tabulados al portapapeles"; Ejemplos = @("qclip 'SELECT TOP 20 * FROM Articulos'") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "qlog"; Sintaxis = "qlog [filtro] [-Last]"; Detalle = "Consulta el historial persistente de consultas SQL ejecutadas en `$HOME\.sql_history.tsv"; Ejemplos = @("qlog", "qlog Articulos -Last 10") }

        # 6. Consola & Atajos
        [PSCustomObject]@{ Categoria = "Consola & Atajos"; Comando = "hist"; Sintaxis = "hist [filtro] [-Last]"; Detalle = "Busca comandos ejecutados previamente en el historial de la sesión de PowerShell"; Ejemplos = @("hist", "hist git", "hist sql -Last 20") }
        [PSCustomObject]@{ Categoria = "Consola & Atajos"; Comando = "HistorySearch"; Sintaxis = "↑ / ↓"; Detalle = "Búsqueda contextual en el historial: pulsa flecha arriba tras escribir un prefijo (ej. 'git ')"; Ejemplos = @("Escribe 'git ' y pulsa ↑") }
        [PSCustomObject]@{ Categoria = "Consola & Atajos"; Comando = "SqlTableCompletion"; Sintaxis = "Ctrl + Espacio"; Detalle = "Autocompletado predictivo inteligente de nombres de tablas y vistas de SQL Server en la consola"; Ejemplos = @("Escribe 'SELECT * FROM Art' y pulsa Ctrl+Espacio") }
        [PSCustomObject]@{ Categoria = "Consola & Atajos"; Comando = "ViEditVisually"; Sintaxis = "Ctrl+X, Ctrl+E"; Detalle = "Abre el comando que estás escribiendo en una ventana de Neovim para edición multilínea compleja"; Ejemplos = @("Pulsa Ctrl+X seguido de Ctrl+E en el prompt") }
    )

    if ($Filter) {
        # Si el filtro coincide exactamente con el nombre de un comando o su alias, mostrar ficha técnica
        $exact = $commands | Where-Object {
            $_.Comando -eq $Filter -or
            ($_.Detalle -match "(?i)\balias:\s*[^)]*\b$([regex]::Escape($Filter))\b")
        } | Select-Object -First 1
        if ($exact) {
            Write-Host "`n┌─ Ficha de Ayuda: " -NoNewline -ForegroundColor Cyan
            Write-Host $exact.Comando.ToUpper() -NoNewline -ForegroundColor Yellow
            Write-Host " [$($exact.Categoria)] ─┐" -ForegroundColor Cyan
            Write-Host "  Sintaxis:    " -NoNewline -ForegroundColor DarkGray
            Write-Host $exact.Sintaxis -ForegroundColor Green
            Write-Host "  Descripción: " -NoNewline -ForegroundColor DarkGray
            Write-Host $exact.Detalle -ForegroundColor White
            if ($exact.Ejemplos -and $exact.Ejemplos.Count -gt 0) {
                Write-Host "  Ejemplos de uso:" -ForegroundColor DarkGray
                foreach ($ex in $exact.Ejemplos) {
                    Write-Host "    • $ex" -ForegroundColor Cyan
                }
            }
            Write-Host "└──────────────────────────────────────────────────────────┘`n" -ForegroundColor Cyan
            return
        }

        # Filtrado amplio por comando, categoría, sintaxis o descripción
        $commands = $commands | Where-Object {
            $_.Comando -like "*$Filter*" -or $_.Detalle -like "*$Filter*" -or $_.Categoria -like "*$Filter*" -or $_.Sintaxis -like "*$Filter*"
        }

        if (-not $commands -or $commands.Count -eq 0) {
            Write-Host "● No se encontraron comandos que coincidan con '$Filter'." -ForegroundColor Yellow
            return
        }
    }

    Write-Host "`n=== Centro de Mando: `$PROFILE ===`n" -ForegroundColor DarkCyan

    $groups = $commands | Group-Object Categoria
    foreach ($group in $groups) {
        Write-Host " [$($group.Name)]" -ForegroundColor Yellow
        foreach ($item in $group.Group) {
            $cmdDisplay = $item.Sintaxis.PadRight(26)
            Write-Host "   $cmdDisplay" -NoNewline -ForegroundColor Green
            Write-Host " -> " -NoNewline -ForegroundColor DarkGray
            Write-Host $item.Detalle -ForegroundColor White
        }
        Write-Host ""
    }

    Write-Host "Tip: Usa 'phelp <comando>' (ej. 'phelp q', 'phelp vmod', 'phelp top') para ver su ficha técnica con ejemplos.`n" -ForegroundColor DarkGray
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

    # Búsqueda contextual en el historial de comandos (filtrar por prefijo escrito)
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

    # Edición visual de la línea de comandos con Neovim (Ctrl+X, Ctrl+E)
    Set-PSReadLineKeyHandler -Chord 'Ctrl+x,Ctrl+e' -Function ViEditVisually
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


