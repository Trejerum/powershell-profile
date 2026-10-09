# ==============================================================================
# 35-BLUEMINE.PS1 - GESTOR DE TICKETS, CRONÓMETRO DE TAREAS Y CONTROL DE JORNADA
# ==============================================================================
# Proporciona integración entre notas diarias y Bluemine (fork de Redmine):
# - Catálogo de tickets locales sincronizado desde Descargas (issues*.csv)
# - Selección y adición rápida de tickets a la nota diaria (bm / tickets)
# - Cronómetro de tareas de un solo toque (tstart, tstop, todo -Start / -Stop)
# - Control y auto-cuadre de jornada laboral (8,5h L-J y 6,0h V) (hours / imputar)
# - Volcado rápido al portapapeles listo para la web de Bluemine (hours -Clip)
# ==============================================================================

if (-not $global:NotesDir) {
    $global:NotesDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "Notes"
}
$global:BluemineCsvPath   = Join-Path $global:NotesDir "bluemine.csv"
$global:ActiveTimerFile   = Join-Path $HOME ".active_task_timer.json"

# ------------------------------------------------------------------------------
# 1. SINCRONIZACIÓN DE TICKETS DESDE DESCARGAS: bm-sync (alias: bluemine-sync)
# ------------------------------------------------------------------------------
function bm-sync {
    <#
    .SYNOPSIS
        Sincroniza el catálogo de tickets de Bluemine importando el CSV más reciente desde Descargas.
    .EXAMPLE
        bm-sync
        bm-sync -Force
        bm-sync -Clean
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path,

        [switch]$Force,
        [switch]$Clean,
        [switch]$Quiet
    )

    $targetPath = $global:BluemineCsvPath
    $notesDir = $global:NotesDir
    if (-not (Test-Path -LiteralPath $notesDir)) {
        New-Item -ItemType Directory -Path $notesDir -Force | Out-Null
    }

    $sourceFile = $null

    if ($Path) {
        if (Test-Path -LiteralPath $Path) {
            $sourceFile = Get-Item -LiteralPath $Path
        } else {
            Write-Error "El archivo especificado no existe: $Path"
            return
        }
    } else {
        $downloadsDir = Join-Path $HOME "Downloads"
        if (Test-Path -LiteralPath $downloadsDir) {
            $candidate = Get-ChildItem -Path $downloadsDir -Filter "issues*.csv" |
                         Sort-Object LastWriteTime -Descending |
                         Select-Object -First 1
            if ($candidate) {
                $sourceFile = $candidate
            }
        }
    }

    if (-not $sourceFile) {
        if (-not $Quiet) {
            if (Test-Path -LiteralPath $targetPath) {
                Write-Host "ℹ No hay nuevos 'issues*.csv' en Descargas. Usando catálogo actual en $targetPath." -ForegroundColor Yellow
            } else {
                Write-Host "ℹ No se encontró ningún archivo 'issues*.csv' en Descargas ni catálogo previo." -ForegroundColor Yellow
                Write-Host "Tip: Descarga la exportación CSV desde Bluemine y ejecuta 'bm-sync'." -ForegroundColor DarkGray
            }
        }
        return
    }

    # Comprobar si el archivo en Descargas es más reciente que el actual
    $shouldCopy = $Force -or (-not (Test-Path -LiteralPath $targetPath))
    if (-not $shouldCopy) {
        $currentTarget = Get-Item -LiteralPath $targetPath
        if ($sourceFile.LastWriteTime -gt $currentTarget.LastWriteTime) {
            $shouldCopy = $true
        }
    }

    if ($shouldCopy) {
        Copy-Item -LiteralPath $sourceFile.FullName -Destination $targetPath -Force
        if ($Clean -and $sourceFile.FullName -ne $targetPath) {
            Remove-Item -LiteralPath $sourceFile.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    $issues = @(Get-BluemineIssues)
    $activeCount = @($issues | Where-Object { $_.Status -ne 'Cerrada' }).Count
    $closedCount = @($issues | Where-Object { $_.Status -eq 'Cerrada' }).Count

    if (-not $Quiet) {
        Write-Host "✓ Catálogo de Bluemine sincronizado ($($sourceFile.Name)):" -ForegroundColor Green
        Write-Host "  $($issues.Count) tareas en total ($activeCount activas, $closedCount cerradas)." -ForegroundColor White
    }
}
Set-Alias bluemine-sync bm-sync
Set-Alias sync-bm bm-sync

# ------------------------------------------------------------------------------
# 2. HELPER: PARSEO DEL CSV DE BLUEMINE: Get-BluemineIssues
# ------------------------------------------------------------------------------
function Get-BluemineIssues {
    [CmdletBinding()]
    param()

    $csvPath = $global:BluemineCsvPath
    if (-not (Test-Path -LiteralPath $csvPath)) {
        return @()
    }

    $rawLines = [System.IO.File]::ReadAllLines($csvPath, [System.Text.Encoding]::UTF8)
    if ($rawLines.Count -le 1) {
        return @()
    }

    # Si la primera línea empieza por '#;', reemplazar por 'Id;' para evitar que se interprete como comentario
    if ($rawLines[0].StartsWith('#;') -or $rawLines[0].StartsWith('#,')) {
        $rawLines[0] = 'Id' + $rawLines[0].Substring(1)
    }

    $headerLine = $rawLines[0]
    $delimiter = if ($headerLine.Contains(';')) { ';' } else { ',' }

    $parsed = $rawLines | ConvertFrom-Csv -Delimiter $delimiter
    $results = @()

    foreach ($row in $parsed) {
        # Extraer propiedades tolerando variaciones en nombres de columna
        $id = $row.Id
        if (-not $id) { $id = $row.'#' }
        if (-not $id) { $id = $row.ID }
        if (-not $id) { continue }

        $clientCode = $row.'Codigo Tarea Cliente'
        if (-not $clientCode) { $clientCode = $row.'Código Tarea Cliente' }
        if (-not $clientCode) { $clientCode = "" }

        $status = if ($row.Estado) { $row.Estado.Trim() } else { "Nueva Petición" }
        $priority = if ($row.Prioridad) { $row.Prioridad.Trim() } else { "Normal" }
        $subject = if ($row.Asunto) { $row.Asunto.Trim() } else { "" }

        $spentRaw = $row.'Tiempo dedicado'
        if (-not $spentRaw) { $spentRaw = "0,00" }
        $spentNum = 0.0
        try {
            $spentNum = [double]::Parse(($spentRaw -replace ',', '.'), [System.Globalization.CultureInfo]::InvariantCulture)
        } catch { }

        $results += [PSCustomObject]@{
            Id         = $id.ToString().Trim()
            Code       = $clientCode.ToString().Trim()
            Status     = $status
            Priority   = $priority
            Subject    = $subject
            SpentHours = $spentNum
            Raw        = $row
        }
    }

    return $results
}

# ------------------------------------------------------------------------------
# 3. SELECTOR & VISOR DE TICKETS BLUEMINE: bm (alias: tickets, bluemine)
# ------------------------------------------------------------------------------
function bm {
    <#
    .SYNOPSIS
        Consulta las tareas asignadas de Bluemine o añade un ticket a la nota diaria de hoy.
    .EXAMPLE
        bm                          # Lista tareas activas ordenadas por prioridad
        bm rendimiento              # Busca por texto en asunto o código SGA
        bm 1                        # Añade la tarea #1 a la nota diaria de hoy
        bm -Add 221074              # Añade directamente por número de ticket
        bm -All                     # Muestra también tareas cerradas
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Filter,

        [Parameter()]
        [string]$Add,

        [Parameter()]
        [switch]$All
    )

    # Auto-detección silenciosa si hay un issues*.csv más reciente en Descargas
    bm-sync -Quiet

    $issues = @(Get-BluemineIssues)
    if ($issues.Count -eq 0) {
        Write-Host "ℹ No hay tareas en el catálogo de Bluemine." -ForegroundColor Yellow
        Write-Host "Tip: Descarga 'issues.csv' de Bluemine y ejecuta 'bm-sync'." -ForegroundColor DarkGray
        return
    }

    # Filtrar activas por defecto salvo -All
    $displayed = if ($All) {
        $issues
    } else {
        @($issues | Where-Object { $_.Status -ne 'Cerrada' })
    }

    # Ordenar por prioridad (Urgente > Normal > Baja)
    $priorityOrder = @{ 'Urgente' = 1; 'Alta' = 2; 'Normal' = 3; 'Baja' = 4 }
    $displayed = @($displayed | Sort-Object {
        if ($priorityOrder.ContainsKey($_.Priority)) { $priorityOrder[$_.Priority] } else { 99 }
    }, Id)

    # Caso 1: Añadir por índice numérico posicional (ej. 'bm 1') o por -Add
    $targetToAdd = $null
    if ($Add) {
        $targetToAdd = $Add
    } elseif ($Filter -match '^\d{1,3}$') {
        $idx = [int]$Filter
        if ($idx -ge 1 -and $idx -le $displayed.Count) {
            $targetToAdd = $displayed[$idx - 1].Id
        }
    } elseif ($Filter -match '^\d{5,7}$') {
        $targetToAdd = $Filter
    }

    if ($targetToAdd) {
        $item = $issues | Where-Object { $_.Id -eq $targetToAdd } | Select-Object -First 1
        if (-not $item) {
            Write-Error "No se encontró ningún ticket con ID '#$targetToAdd'."
            return
        }

        $todayStr = Get-Date -Format 'yyyyMMdd'
        $todayFile = Join-Path $global:NotesDir "$todayStr.md"

        if (-not (Test-Path -LiteralPath $todayFile)) {
            $header = "# $todayStr`r`n`r`n"
            $utf8Bom = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllText($todayFile, $header, $utf8Bom)
        }

        $codeTag = if ($item.Code) { "[$($item.Code)] " } else { "" }
        $taskLine = "- [ ] #$($item.Id) $codeTag$($item.Subject)"

        # Comprobar si ya existe en la nota de hoy
        $content = [System.IO.File]::ReadAllText($todayFile, [System.Text.Encoding]::UTF8)
        if ($content.Contains("#$($item.Id)")) {
            Write-Host "ℹ El ticket #$($item.Id) ya está presente en la nota de hoy ($todayStr.md)." -ForegroundColor Yellow
            return
        }

        # Añadir al inicio del bloque de tareas (justo después del encabezado # YYYYMMDD)
        $todayLines = [System.Collections.Generic.List[string]]::new(
            [System.IO.File]::ReadAllLines($todayFile, [System.Text.Encoding]::UTF8)
        )
        $insertIdx = 0
        for ($i = 0; $i -lt $todayLines.Count; $i++) {
            if ($todayLines[$i] -match '^#\s+') {
                $insertIdx = $i + 1
                while ($insertIdx -lt $todayLines.Count -and [string]::IsNullOrWhiteSpace($todayLines[$insertIdx])) {
                    $insertIdx++
                }
                break
            }
        }
        $todayLines.Insert($insertIdx, $taskLine)
        $crlf = ($todayLines -join "`r`n") + "`r`n"
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($todayFile, $crlf, $utf8Bom)

        Write-Host "`n✓ Tarea de Bluemine añadida a la nota de hoy ($todayStr.md):" -ForegroundColor Green
        Write-Host "  $taskLine`n" -ForegroundColor White
        return
    }

    # Caso 2: Filtrar por texto si se especificó búsqueda
    if ($Filter) {
        $displayed = @($displayed | Where-Object {
            $_.Subject -like "*$Filter*" -or
            $_.Code -like "*$Filter*" -or
            $_.Id -like "*$Filter*" -or
            $_.Status -like "*$Filter*"
        })
    }

    if ($displayed.Count -eq 0) {
        Write-Host "● No se encontraron tareas que coincidan con '$Filter'." -ForegroundColor Yellow
        return
    }

    $title = if ($All) { "Todas las Tareas de Bluemine" } else { "Tareas Activas de Bluemine" }
    Write-Host "`n=== $title ($($displayed.Count)) ===`n" -ForegroundColor DarkCyan

    $idx = 1
    foreach ($item in $displayed) {
        $pColor = switch ($item.Priority) {
            'Urgente' { "Red" }
            'Alta'    { "Magenta" }
            'Normal'  { "Yellow" }
            'Baja'    { "DarkGray" }
            default   { "Cyan" }
        }

        $idxTag = "  [$idx]".PadRight(7)
        Write-Host $idxTag -ForegroundColor DarkGray -NoNewline
        Write-Host "#$($item.Id) " -ForegroundColor Cyan -NoNewline
        if ($item.Code) {
            Write-Host "[$($item.Code)] " -ForegroundColor DarkYellow -NoNewline
        }
        Write-Host "($($item.Priority)) " -ForegroundColor $pColor -NoNewline
        Write-Host "$($item.Subject)" -ForegroundColor White -NoNewline
        if ($item.SpentHours -gt 0) {
            Write-Host " [$($item.SpentHours)h]" -ForegroundColor DarkGreen -NoNewline
        }
        if ($item.Status -ne 'Nueva Petición' -and $item.Status -ne 'En curso') {
            Write-Host " {$($item.Status)}" -ForegroundColor DarkGray -NoNewline
        }
        Write-Host ""
        $idx++
    }

    Write-Host ""
    Write-Host "Tip: Usa 'bm <n>' para añadir una tarea a hoy, o 'todo -Start <n>' para arrancar cronómetro.`n" -ForegroundColor DarkGray
}
Set-Alias tickets bm
Set-Alias bluemine bm

# ------------------------------------------------------------------------------
# 4. CRONÓMETRO DE TAREAS: task-start, task-stop, task-status
# ------------------------------------------------------------------------------
function task-start {
    <#
    .SYNOPSIS
        Inicia un cronómetro para la tarea indicada de 'todo' o por número de ticket.
    .EXAMPLE
        task-start 1
        tstart 2
        todo -Start 1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [int]$Task,

        [Parameter(Position = 1)]
        [string]$Comment
    )

    $tasks = @(Get-NoteTasks)
    if ($Task -lt 1 -or $Task -gt $tasks.Count) {
        Write-Error "Índice $Task fuera de rango (hay $($tasks.Count) tareas pendientes)."
        return
    }

    $targetTask = $tasks[$Task - 1]

    # Si ya había una tarea corriendo, cerrarla primero automáticamente
    if (Test-Path -LiteralPath $global:ActiveTimerFile) {
        Write-Host "● Cerrando temporizador de la tarea anterior en curso..." -ForegroundColor DarkCyan
        task-stop -NoPrompt
    }

    $ticketId = $null
    if ($targetTask.Text -match '#(\d{5,7})') {
        $ticketId = $matches[1]
    }

    $timerState = [PSCustomObject]@{
        TaskIdx        = $Task
        TaskText       = $targetTask.Text
        TicketId       = $ticketId
        File           = $targetTask.File
        FileName       = $targetTask.FileName
        LineNumber     = $targetTask.LineNumber
        LastLineNumber = $targetTask.LastLineNumber
        StartTime      = (Get-Date).ToString('o')
        Comment        = $Comment
    }

    $json = $timerState | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($global:ActiveTimerFile, $json, [System.Text.Encoding]::UTF8)

    $timeStr = (Get-Date).Format('HH:mm')
    Write-Host "`n⏱ Cronómetro INICIADO a las $timeStr para la tarea [$Task]:" -ForegroundColor Green
    Write-Host "  $($targetTask.Text)" -ForegroundColor White
    Write-Host "Tip: Usa 'task-stop' o 'todo -Stop' cuando finalices para registrar el tiempo exacto.`n" -ForegroundColor DarkGray
}
Set-Alias tstart task-start

function task-stop {
    <#
    .SYNOPSIS
        Detiene el cronómetro activo, calcula el tiempo transcurrido y lo anota en la nota diaria.
    .EXAMPLE
        task-stop
        tstop "Optimización de consultas"
        todo -Stop
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Comment,

        [switch]$NoPrompt
    )

    if (-not (Test-Path -LiteralPath $global:ActiveTimerFile)) {
        Write-Host "ℹ No hay ningún cronómetro de tarea activo en este momento." -ForegroundColor Yellow
        Write-Host "Tip: Usa 'task-start <n>' o 'todo -Start <n>' para iniciar uno." -ForegroundColor DarkGray
        return
    }

    $json = [System.IO.File]::ReadAllText($global:ActiveTimerFile, [System.Text.Encoding]::UTF8)
    $timer = $json | ConvertFrom-Json

    $startTime = [DateTime]::Parse($timer.StartTime)
    $endTime = Get-Date
    $elapsedMinutes = [math]::Round(($endTime - $startTime).TotalMinutes)

    # Si fue menos de 1 minuto, computar al menos 0.05h o 1 minuto
    if ($elapsedMinutes -lt 1) { $elapsedMinutes = 1 }

    # Calcular horas decimales (redondeado a 2 decimales, ej. 1.25h)
    $hours = [math]::Round($elapsedMinutes / 60, 2)
    if ($hours -lt 0.05) { $hours = 0.05 }

    $startStr = $startTime.ToString('HH:mm')
    $endStr   = $endTime.ToString('HH:mm')

    $finalComment = if ($Comment) {
        $Comment.Trim()
    } elseif ($timer.Comment) {
        $timer.Comment.Trim()
    } else {
        ""
    }

    if (-not $finalComment -and -not $NoPrompt) {
        Write-Host "`n⏱ Tarea: $($timer.TaskText)" -ForegroundColor Cyan
        Write-Host "  Tiempo transcurrido: $elapsedMinutes min (${hours}h) [$startStr - $endStr]" -ForegroundColor Yellow
        $userComment = Read-Host "  Comentario / descripción del trabajo (opcional)"
        if ($userComment) {
            $finalComment = $userComment.Trim()
        }
    }

    $noteText = if ($finalComment) {
        "[$startStr - $endStr] ${hours}h | $finalComment"
    } else {
        "[$startStr - $endStr] ${hours}h"
    }
    $indentedLine = "    $noteText"

    # Escribir en la nota
    if (Test-Path -LiteralPath $timer.File) {
        $fileLines = [System.Collections.Generic.List[string]]::new(
            [System.IO.File]::ReadAllLines($timer.File, [System.Text.Encoding]::UTF8)
        )
        $insertIdx = [math]::Min([int]$timer.LastLineNumber, $fileLines.Count)
        $fileLines.Insert($insertIdx, $indentedLine)

        $crlf = ($fileLines -join "`r`n") + "`r`n"
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($timer.File, $crlf, $utf8Bom)
    }

    # Eliminar archivo de estado
    Remove-Item -LiteralPath $global:ActiveTimerFile -Force -ErrorAction SilentlyContinue

    Write-Host "`n✓ Cronómetro DETENIDO: ${hours}h ($elapsedMinutes min) registradas en $($timer.FileName):" -ForegroundColor Green
    Write-Host "  $($timer.TaskText)" -ForegroundColor DarkGray
    Write-Host "      ↳ $noteText`n" -ForegroundColor White
}
Set-Alias tstop task-stop

function task-status {
    <#
    .SYNOPSIS
        Muestra el estado del cronómetro de tarea activo.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $global:ActiveTimerFile)) {
        Write-Host "● No hay ninguna tarea en el cronómetro activo." -ForegroundColor DarkGray
        return
    }

    $json = [System.IO.File]::ReadAllText($global:ActiveTimerFile, [System.Text.Encoding]::UTF8)
    $timer = $json | ConvertFrom-Json
    $startTime = [DateTime]::Parse($timer.StartTime)
    $elapsed = (Get-Date) - $startTime
    $mins = [math]::Floor($elapsed.TotalMinutes)
    $secs = $elapsed.Seconds

    Write-Host "`n┌─ Cronómetro Activo ──────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "  Tarea:      " -NoNewline -ForegroundColor DarkGray
    Write-Host "[$($timer.TaskIdx)] $($timer.TaskText)" -ForegroundColor Yellow
    Write-Host "  Inicio:     " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($startTime.ToString('HH:mm:ss'))" -ForegroundColor White
    Write-Host "  Tiempo:     " -NoNewline -ForegroundColor DarkGray
    Write-Host "$mins min $secs seg" -ForegroundColor Green
    Write-Host "└──────────────────────────────────────────────────────────┘`n" -ForegroundColor Cyan
}
Set-Alias tstatus task-status

# ------------------------------------------------------------------------------
# 5. CONTROL DE JORNADA & IMPUTACIÓN: hours (alias: timesheet, imputar)
# ------------------------------------------------------------------------------
function hours {
    <#
    .SYNOPSIS
        Analiza las horas imputadas en la nota de hoy comparándolas con el objetivo de jornada (8,5h L-J / 6,0h V).
    .EXAMPLE
        hours                       # Muestra el balance de la jornada de hoy
        hours -Fill                 # Auto-cuadra las horas restantes para clavar la jornada
        hours -Clip                 # Copia el resumen tabulado al portapapeles para Bluemine
        hours -Days 5               # Muestra el resumen de los últimos 5 días
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [int]$Days = 1,

        [switch]$Fill,
        [Alias('Auto')]
        [switch]$AutoFill,

        [switch]$Clip
    )

    $notesDir = $global:NotesDir
    $today = (Get-Date).Date
    $todayStr = $today.ToString('yyyyMMdd')
    $dayOfWeek = (Get-Date).DayOfWeek

    # Target de jornada según día: Viernes = 6.0h; Lunes-Jueves = 8.5h
    $targetToday = if ($dayOfWeek -eq 'Friday') {
        6.0
    } elseif ($dayOfWeek -in @('Saturday', 'Sunday')) {
        0.0
    } else {
        8.5
    }

    $todayFile = Join-Path $notesDir "$todayStr.md"
    if (-not (Test-Path -LiteralPath $todayFile)) {
        Write-Host "ℹ No existe nota para el día de hoy ($todayStr.md)." -ForegroundColor Yellow
        return
    }

    # Cargar catálogo de Bluemine para cruzar tickets
    $bmIssues = @(Get-BluemineIssues)
    $bmMap = @{}
    foreach ($iss in $bmIssues) {
        $bmMap[$iss.Id] = $iss
    }

    # Parsear nota de hoy
    $lines = [System.IO.File]::ReadAllLines($todayFile, [System.Text.Encoding]::UTF8)
    $taskRegex = '^\s*[-*]\s*\[([ xX>~-])\]\s*(.*)$'
    $timeRegex = '(?:^|\s|\||\[)(\d+(?:[.,]\d+)?)\s*h\b'

    $currentTask = $null
    $currentTicket = $null
    $entries = @()
    $candidateTasks = @()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match $taskRegex) {
            $marker = $matches[1]
            $taskText = $matches[2].Trim()
            $currentTask = $taskText
            $currentTicket = $null

            if ($taskText -match '#(\d{5,7})') {
                $currentTicket = $matches[1]
            } elseif ($taskText -match '\b(SGA-\d+)\b') {
                # Buscar por código SGA en el catálogo
                $sgaCode = $matches[1]
                $found = $bmIssues | Where-Object { $_.Code -eq $sgaCode } | Select-Object -First 1
                if ($found) { $currentTicket = $found.Id }
            }

            $candidateTasks += [PSCustomObject]@{
                LineNumber = ($i + 1)
                Text       = $taskText
                Ticket     = $currentTicket
                Marker     = $marker
            }

            # Comprobar si la propia tarea tiene horas indicadas en línea (ej. [2.5h])
            if ($taskText -match $timeRegex) {
                $h = [double]::Parse(($matches[1] -replace ',', '.'), [System.Globalization.CultureInfo]::InvariantCulture)
                $entries += [PSCustomObject]@{
                    Ticket  = $currentTicket
                    Hours   = $h
                    Comment = ($taskText -replace $timeRegex, '').Trim()
                    Line    = ($i + 1)
                }
            }
        }
        elseif ($l -match '^\s{2,}\S' -and $currentTask) {
            # Sub-apunte identado
            if ($l -match $timeRegex) {
                $h = [double]::Parse(($matches[1] -replace ',', '.'), [System.Globalization.CultureInfo]::InvariantCulture)
                # Extraer comentario tras el '|' o ':'
                $comment = $l.Trim()
                if ($comment -match '\|\s*(.*)$') {
                    $comment = $matches[1].Trim()
                } elseif ($comment -match ':\s*(.*)$') {
                    $comment = $matches[1].Trim()
                }

                $entries += [PSCustomObject]@{
                    Ticket  = $currentTicket
                    Hours   = $h
                    Comment = $comment
                    Line    = ($i + 1)
                }
            }
        }
    }

    $totalLogged = 0.0
    foreach ($e in $entries) {
        $totalLogged += $e.Hours
    }
    $totalLogged = [math]::Round($totalLogged, 2)

    # --------------------------------------------------------------------------
    # MODO -Fill: Auto-cuadre de horas restantes
    # --------------------------------------------------------------------------
    if ($Fill -or $AutoFill) {
        $diff = [math]::Round($targetToday - $totalLogged, 2)
        if ($diff -le 0) {
            Write-Host "`n✓ La jornada ya está completa ($totalLogged h / $targetToday h). No es necesario auto-cuadrar.`n" -ForegroundColor Green
            return
        }

        # Buscar tareas candidatas a recibir horas (priorizar las que tienen ticket de Bluemine)
        $withTicket = @($candidateTasks | Where-Object { $_.Ticket })
        $targets = if ($withTicket.Count -gt 0) { $withTicket } else { $candidateTasks }

        if ($targets.Count -eq 0) {
            Write-Host "● No hay tareas en la nota de hoy para asignar las $diff h restantes." -ForegroundColor Yellow
            return
        }

        Write-Host "`n┌─ Auto-Cuadre de Jornada ($todayStr) ───────────────────────┐" -ForegroundColor Cyan
        Write-Host "  Objetivo de hoy:   " -NoNewline -ForegroundColor DarkGray
        Write-Host "$targetToday h ($dayOfWeek)" -ForegroundColor Yellow
        Write-Host "  Horas imputadas:   " -NoNewline -ForegroundColor DarkGray
        Write-Host "$totalLogged h" -ForegroundColor White
        Write-Host "  Faltan por cuadrar: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$diff h" -ForegroundColor Green
        Write-Host "────────────────────────────────────────────────────────────" -ForegroundColor DarkCyan

        # Repartir $diff entre las tareas candidatas
        $portion = [math]::Round($diff / $targets.Count, 2)
        $remainder = [math]::Round($diff - ($portion * ($targets.Count - 1)), 2)

        $proposals = @()
        for ($k = 0; $k -lt $targets.Count; $k++) {
            $assignedHours = if ($k -eq ($targets.Count - 1)) { $remainder } else { $portion }
            $proposals += [PSCustomObject]@{
                Target = $targets[$k]
                Hours  = $assignedHours
            }
            $tDesc = $targets[$k].Text
            Write-Host "  • +$assignedHours h → $tDesc" -ForegroundColor White
        }
        Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan

        $confirm = Read-Host "`n¿Aplicar esta distribución a la nota de hoy? [S/n]"
        if ($confirm -ne '' -and $confirm -notmatch '^[sSyY]') {
            Write-Host "ℹ Auto-cuadre cancelado por el usuario." -ForegroundColor Yellow
            return
        }

        # Escribir los apuntes de cuadre en el archivo
        $fileLines = [System.Collections.Generic.List[string]]::new(
            [System.IO.File]::ReadAllLines($todayFile, [System.Text.Encoding]::UTF8)
        )
        $offset = 0
        $timeStr = (Get-Date).ToString('HH:mm')

        foreach ($p in $proposals) {
            $insertIdx = $p.Target.LineNumber + $offset
            # Avanzar mientras haya líneas hijas
            while ($insertIdx -lt $fileLines.Count -and $fileLines[$insertIdx] -match '^\s{2,}\S') {
                $insertIdx++
            }
            $appendLine = "    [$timeStr] $($p.Hours)h | Trabajo y desarrollo continuado"
            $fileLines.Insert($insertIdx, $appendLine)
            $offset++
        }

        $crlf = ($fileLines -join "`r`n") + "`r`n"
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($todayFile, $crlf, $utf8Bom)

        Write-Host "`n✓ ¡Jornada cuadrada con éxito a $targetToday h exactas!`n" -ForegroundColor Green
        # Recargar para mostrar reporte final
        hours
        return
    }

    # --------------------------------------------------------------------------
    # MOSTRAR REPORTE EN PANTALLA
    # --------------------------------------------------------------------------
    $dayLabel = switch ($dayOfWeek) {
        'Monday'    { "Lunes" }
        'Tuesday'   { "Martes" }
        'Wednesday' { "Miércoles" }
        'Thursday'  { "Jueves" }
        'Friday'    { "Viernes" }
        default     { $dayOfWeek.ToString() }
    }

    Write-Host "`n=== Control de Imputación - $todayStr ($dayLabel) ===`n" -ForegroundColor DarkCyan
    Write-Host "  Objetivo de hoy: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$targetToday h" -ForegroundColor Yellow

    if ($entries.Count -eq 0) {
        Write-Host "  Horas registradas: 0.0 h`n" -ForegroundColor White
        Write-Host "ℹ No hay horas registradas en la nota de hoy." -ForegroundColor Yellow
        Write-Host "Tip: Usa 'todo -Log <n> <horas>', 'task-start <n>' o 'hours -Fill' para auto-cuadrar.`n" -ForegroundColor DarkGray
        return
    }

    # Agrupar por Ticket
    $grouped = $entries | Group-Object { if ($_.Ticket) { "#$($_.Ticket)" } else { "[Sin ticket]" } }

    Write-Host ""
    Write-Host "  Ticket        Código     Horas   Asunto / Detalle" -ForegroundColor DarkGray
    Write-Host "  ────────────  ─────────  ──────  ──────────────────────────────────────────" -ForegroundColor DarkGray

    $tsvLines = @("Ticket`tCodigo`tHoras`tAsunto`tComentarios")

    foreach ($g in $grouped) {
        $tId = $g.Name.TrimStart('#')
        $bmInfo = if ($bmMap.ContainsKey($tId)) { $bmMap[$tId] } else { $null }

        $code = if ($bmInfo -and $bmInfo.Code) { $bmInfo.Code } else { "-" }
        $subject = if ($bmInfo -and $bmInfo.Subject) { $bmInfo.Subject } else { "(Tarea en nota)" }

        $sumH = 0.0
        $comments = @()
        foreach ($e in $g.Group) {
            $sumH += $e.Hours
            if ($e.Comment) { $comments += $e.Comment }
        }
        $sumH = [math]::Round($sumH, 2)

        $tCol = $g.Name.PadRight(14)
        $cCol = $code.PadRight(11)
        $hCol = "${sumH}h".PadLeft(6)

        Write-Host "  $tCol" -NoNewline -ForegroundColor Cyan
        Write-Host "$cCol" -NoNewline -ForegroundColor DarkYellow
        Write-Host "$hCol  " -NoNewline -ForegroundColor Green
        Write-Host "$subject" -ForegroundColor White

        if ($comments.Count -gt 0) {
            $uniqueComments = @($comments | Select-Object -Unique)
            foreach ($cm in $uniqueComments) {
                Write-Host "                           ↳ $cm" -ForegroundColor DarkGray
            }
        }

        $commStr = ($comments -join "; ")
        $tsvLines += "$($g.Name)`t$code`t$sumH`t$subject`t$commStr"
    }

    Write-Host "  ──────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

    # Barra de progreso
    $pct = if ($targetToday -gt 0) { [math]::Min([int](($totalLogged / $targetToday) * 100), 100) } else { 100 }
    $filledBars = [int][math]::Round($pct / 10)
    $emptyBars  = 10 - $filledBars
    $bar = ("█" * $filledBars) + ("░" * $emptyBars)

    $barColor = if ($totalLogged -ge $targetToday) { "Green" } elseif ($totalLogged -ge ($targetToday - 1.5)) { "Yellow" } else { "Red" }

    Write-Host "  TOTAL HOY:               " -NoNewline -ForegroundColor DarkGray
    Write-Host "${totalLogged}h / ${targetToday}h  " -NoNewline -ForegroundColor White
    Write-Host "[$bar] $pct%" -ForegroundColor $barColor

    if ($totalLogged -lt $targetToday) {
        $faltan = [math]::Round($targetToday - $totalLogged, 2)
        Write-Host "  Faltan: $faltan h para completar la jornada diaria." -ForegroundColor Yellow
        Write-Host "  Tip: Usa 'hours -Fill' para cuadrar automáticamente las horas restantes." -ForegroundColor DarkGray
    } elseif ($totalLogged -eq $targetToday) {
        Write-Host "  ✓ ¡Jornada diaria completada al 100% exacto!" -ForegroundColor Green
    } else {
        $extra = [math]::Round($totalLogged - $targetToday, 2)
        Write-Host "  ℹ +$extra h por encima del objetivo de hoy." -ForegroundColor Cyan
    }
    Write-Host ""

    # Copiar al portapapeles si se pidió -Clip
    if ($Clip) {
        $tsvContent = $tsvLines -join "`r`n"
        Set-Clipboard -Value $tsvContent
        Write-Host "✓ Resumen copiado al portapapeles en formato TSV/Excel listo para Bluemine.`n" -ForegroundColor Green
    }
}
Set-Alias timesheet hours
Set-Alias imputar hours
