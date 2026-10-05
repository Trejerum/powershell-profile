# ==============================================================================
# 15-NOTES: GESTOR DE NOTAS PERSONALES & DIARIO DEVELOPER
# ==============================================================================
# Automatiza el flujo de notas diarias en Neovim ($HOME\Documentos\Notes),
# captura rápida de ideas desde consola, búsqueda con Ripgrep y versionado Git.
# ==============================================================================

$global:NotesDir = Join-Path $HOME "Documentos\Notes"
$script:NotesDir = $global:NotesDir

# ------------------------------------------------------------------------------
# 1. COMANDO PRINCIPAL: note (alias: today, diario)
# ------------------------------------------------------------------------------
function note {
    <#
    .SYNOPSIS
        Abre la nota diaria en Neovim o realiza capturas rápidas desde la consola.
    .EXAMPLE
        note
        note "Revisar stock en wizard de traspasos"
        "Error en SP_Stock: timeout" | note
        note yesterday
        note -1
        note last
        note 20261001
        note 2
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        $InputObject
    )

    begin {
        $piped = @()
        $notesDir = $global:NotesDir
        if (-not (Test-Path -LiteralPath $notesDir)) {
            New-Item -ItemType Directory -Path $notesDir -Force | Out-Null
        }
    }

    process {
        if ($null -ne $InputObject) {
            $piped += $InputObject
        }
    }

    end {
        $todayStr = Get-Date -Format 'yyyyMMdd'
        $todayFile = Join-Path $notesDir "$todayStr.md"

        # Caso 1: Captura rápida vía pipeline o texto libre
        if ($piped.Count -gt 0) {
            $text = ($piped -join " ").Trim()

            $isNavigation = ($piped.Count -eq 1 -and (
                $text -in @('yesterday', 'ayer', '-1', 'last', 'ultimo', 'prev') -or
                $text -match '^\d+$' -or
                $text -match '^\d{4}-?\d{2}-?\d{2}$'
            ))

            if (-not $isNavigation) {
                if (-not (Test-Path -LiteralPath $todayFile)) {
                    $header = "# $todayStr`r`n`r`n"
                    [System.IO.File]::WriteAllText($todayFile, $header, [System.Text.Encoding]::UTF8)
                }

                $timeStr = Get-Date -Format 'HH:mm'
                $linesToAppend = foreach ($line in ($text -split "`r?`n")) {
                    if ($line.Trim().Length -gt 0) {
                        "- [$timeStr] $line"
                    }
                }
                Add-Content -LiteralPath $todayFile -Value $linesToAppend -Encoding UTF8

                Write-Host "✓ Apuntado en $todayStr.md: " -ForegroundColor Green -NoNewline
                Write-Host $text -ForegroundColor White
                return
            }

            $selector = $text
        }
        else {
            $selector = $null
        }

        # Caso 2: Abrir nota en Neovim
        $targetFile = $null

        if (-not $selector) {
            $targetFile = $todayFile
            if (-not (Test-Path -LiteralPath $targetFile)) {
                $header = "# $todayStr`r`n`r`n"
                [System.IO.File]::WriteAllText($targetFile, $header, [System.Text.Encoding]::UTF8)
                Write-Host "● Creada nueva nota diaria: $todayStr.md" -ForegroundColor Cyan
            }
        }
        elseif ($selector -in @('yesterday', 'ayer', '-1')) {
            $targetDate = (Get-Date).AddDays(-1)
            if ((Get-Date).DayOfWeek -eq 'Monday') {
                $fridayStr = (Get-Date).AddDays(-3).ToString('yyyyMMdd')
                $fridayFile = Join-Path $notesDir "$fridayStr.md"
                if (Test-Path -LiteralPath $fridayFile) {
                    $targetDate = (Get-Date).AddDays(-3)
                }
            }
            $targetStr = $targetDate.ToString('yyyyMMdd')
            $targetFile = Join-Path $notesDir "$targetStr.md"
            if (-not (Test-Path -LiteralPath $targetFile)) {
                $header = "# $targetStr`r`n`r`n"
                [System.IO.File]::WriteAllText($targetFile, $header, [System.Text.Encoding]::UTF8)
                Write-Host "● Creada nueva nota para $targetStr.md" -ForegroundColor Cyan
            }
        }
        elseif ($selector -in @('last', 'ultimo', 'prev')) {
            $last = Get-ChildItem -Path $notesDir -Filter "*.md" |
                    Where-Object { $_.BaseName -match '^\d{8}$' } |
                    Sort-Object Name -Descending |
                    Select-Object -First 1
            if ($last) {
                $targetFile = $last.FullName
            } else {
                Write-Error "No se encontraron notas con formato YYYYMMDD.md en $notesDir."
                return
            }
        }
        elseif ($selector -match '^\d{1,2}$') {
            $idx = [int]$selector
            $existing = @(Get-ChildItem -Path $notesDir -Filter "*.md" |
                          Where-Object { $_.BaseName -match '^\d{8}$' } |
                          Sort-Object Name -Descending)
            if ($idx -le $existing.Count -and $idx -ge 1) {
                $targetFile = $existing[$idx - 1].FullName
            } else {
                Write-Error "Índice $idx fuera de rango (hay $($existing.Count) notas disponibles)."
                return
            }
        }
        elseif ($selector -match '^\d{4}-?\d{2}-?\d{2}$') {
            $cleanDate = $selector -replace '-', ''
            $targetFile = Join-Path $notesDir "$cleanDate.md"
            if (-not (Test-Path -LiteralPath $targetFile)) {
                $header = "# $cleanDate`r`n`r`n"
                [System.IO.File]::WriteAllText($targetFile, $header, [System.Text.Encoding]::UTF8)
                Write-Host "● Creada nueva nota para fecha: $cleanDate.md" -ForegroundColor Cyan
            }
        }
        else {
            if (-not (Test-Path -LiteralPath $todayFile)) {
                $header = "# $todayStr`r`n`r`n"
                [System.IO.File]::WriteAllText($todayFile, $header, [System.Text.Encoding]::UTF8)
            }
            $timeStr = Get-Date -Format 'HH:mm'
            Add-Content -LiteralPath $todayFile -Value "- [$timeStr] $selector" -Encoding UTF8
            Write-Host "✓ Apuntado en $todayStr.md: $selector" -ForegroundColor Green
            return
        }

        nvim $targetFile "+"
    }
}
Set-Alias today note
Set-Alias diario note

# ------------------------------------------------------------------------------
# 2. BÚSQUEDA EN NOTAS: snote (consola) y vnote (Neovim Quickfix)
# ------------------------------------------------------------------------------
function snote {
    <#
    .SYNOPSIS
        Busca texto en todas las notas de Documentos\Notes usando Ripgrep o Select-String.
    .EXAMPLE
        snote "inventario"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Pattern
    )

    $notesDir = $global:NotesDir
    if (-not (Test-Path -LiteralPath $notesDir)) {
        Write-Error "No se encuentra la carpeta de notas en $notesDir."
        return
    }

    if (Get-Command rg -ErrorAction SilentlyContinue) {
        Write-Host "Buscando '$Pattern' en notas...`n" -ForegroundColor DarkCyan
        & rg -i --heading --line-number --color=always $Pattern $notesDir
    }
    else {
        Get-ChildItem -Path $notesDir -Filter "*.md" -Recurse |
            Select-String -Pattern $Pattern |
            ForEach-Object {
                $rel = $_.Path.Replace($notesDir, "").TrimStart("\/")
                Write-Host "${rel}:$($_.LineNumber): " -ForegroundColor Cyan -NoNewline
                Write-Host $_.Line
            }
    }
}
Set-Alias find-note snote

function vnote {
    <#
    .SYNOPSIS
        Busca texto en las notas con Ripgrep y abre los resultados en Neovim con Quickfix (:copen).
    .EXAMPLE
        vnote "inventario"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Pattern
    )

    if (-not (Get-Command rg -ErrorAction SilentlyContinue)) {
        Write-Error "Ripgrep ('rg') no está disponible en el PATH."
        return
    }

    $notesDir = $global:NotesDir
    $tempQf = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "nvim_notes_qf_$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).txt")
    try {
        & rg --vimgrep -i $Pattern $notesDir | Out-File -FilePath $tempQf -Encoding UTF8
        if (-not (Test-Path -LiteralPath $tempQf) -or (Get-Item -LiteralPath $tempQf).Length -eq 0) {
            Write-Host "● No se encontraron notas con el término '$Pattern'." -ForegroundColor Yellow
            return
        }
        nvim -q $tempQf -c "copen"
    }
    finally {
        if (Test-Path -LiteralPath $tempQf) {
            Remove-Item -LiteralPath $tempQf -Force -ErrorAction SilentlyContinue
        }
    }
}

# ------------------------------------------------------------------------------
# 3. LISTADO & RESUMEN DE NOTAS: lnotes (alias: recent-notes)
# ------------------------------------------------------------------------------
function lnotes {
    <#
    .SYNOPSIS
        Muestra un resumen de las notas diarias más recientes con fechas relativas y primeros puntos.
    .EXAMPLE
        lnotes
        lnotes 15
        lnotes -Open 2
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [int]$Count = 10,

        [Parameter()]
        [int]$Open
    )

    $notesDir = $global:NotesDir
    $files = @(Get-ChildItem -Path $notesDir -Filter "*.md" |
               Where-Object { $_.BaseName -match '^\d{8}$' } |
               Sort-Object Name -Descending)

    if ($Open) {
        if ($Open -ge 1 -and $Open -le $files.Count) {
            nvim $files[$Open - 1].FullName "+"
            return
        } else {
            Write-Error "Índice $Open fuera de rango (1 a $($files.Count))."
            return
        }
    }

    $itemsToShow = $files | Select-Object -First $Count

    Write-Host "`n=== Notas Diarias Recientes ($notesDir) ===`n" -ForegroundColor DarkCyan

    $idx = 1
    $today = (Get-Date).Date
    foreach ($f in $itemsToShow) {
        $dateStr = $f.BaseName
        $fileDate = [DateTime]::ParseExact($dateStr, 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture)
        $diffDays = ($today - $fileDate.Date).Days

        $relTime = switch ($diffDays) {
            0 { "Hoy" }
            1 { "Ayer" }
            default { "Hace $diffDays días" }
        }

        $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8
        $preview = ""
        foreach ($l in $lines) {
            $t = $l.Trim()
            if ($t -and -not $t.StartsWith("#")) {
                $preview = if ($t.Length -gt 60) { $t.Substring(0, 57) + "..." } else { $t }
                break
            }
        }
        if (-not $preview) { $preview = "(Sin anotaciones adicionales)" }

        $numTag = "[$idx]".PadRight(5)
        $dateTag = "$dateStr ($relTime)".PadRight(22)
        $sizeKB = [Math]::Round($f.Length / 1KB, 1)

        Write-Host $numTag -ForegroundColor Cyan -NoNewline
        Write-Host $dateTag -ForegroundColor White -NoNewline
        Write-Host " $([string]$sizeKB + ' KB') ".PadRight(10) -ForegroundColor DarkGray -NoNewline
        Write-Host "-> $preview" -ForegroundColor Gray

        $idx++
    }

    Write-Host "`nTip: Usa 'note <número>' (ej. 'note 1', 'note 2') para abrir directamente la nota deseada.`n" -ForegroundColor DarkGray
}
Set-Alias recent-notes lnotes

# ------------------------------------------------------------------------------
# 4. SCRATCHPAD SQL FECHADO: note-sql (alias: nsql)
# ------------------------------------------------------------------------------
function note-sql {
    <#
    .SYNOPSIS
        Crea un script SQL fechado dentro de Documentos\Notes\sql\ y lo abre en Neovim.
    .EXAMPLE
        note-sql "art_dups"
        note-sql fix_inventario
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $sqlDir = Join-Path $global:NotesDir "sql"
    if (-not (Test-Path -LiteralPath $sqlDir)) {
        New-Item -ItemType Directory -Path $sqlDir -Force | Out-Null
    }

    $cleanName = ($Name -replace '[^\w\-]', '_').Trim('_')
    $dateStr = Get-Date -Format 'yyyyMMdd'
    $filename = "${dateStr}_${cleanName}.sql"
    $fullPath = Join-Path $sqlDir $filename

    if (-not (Test-Path -LiteralPath $fullPath)) {
        $nowStr = Get-Date -Format 'yyyy-MM-dd HH:mm'
        $activeDb = if ($global:SqlDefaultDatabase) { $global:SqlDefaultDatabase } else { "master" }
        $header = @"
-- ==============================================================================
-- Script: $filename
-- Fecha:  $nowStr
-- Autor:  $env:USERNAME
-- Base:   $activeDb
-- ==============================================================================

USE [$activeDb];
GO


"@
        [System.IO.File]::WriteAllText($fullPath, ($header -replace "`r?`n", "`r`n"), [System.Text.Encoding]::UTF8)
        Write-Host "● Creado script SQL: $filename" -ForegroundColor Cyan
    }

    nvim $fullPath "+"
}
Set-Alias nsql note-sql

# ------------------------------------------------------------------------------
# 5. VERSIONADO & BACKUP GIT: notes-sync (alias: nsync, note-save)
# ------------------------------------------------------------------------------
function notes-sync {
    <#
    .SYNOPSIS
        Registra y sincroniza todos los cambios de Documentos\Notes en el repositorio Git local.
    .EXAMPLE
        notes-sync
        notes-sync "Resumen reunión semanal"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Message
    )

    $notesDir = $global:NotesDir
    if (-not (Test-Path -LiteralPath (Join-Path $notesDir ".git"))) {
        Write-Error "No se ha encontrado repositorio Git en $notesDir."
        return
    }

    $status = git -C $notesDir status --porcelain
    if (-not $status) {
        Write-Host "✓ No hay cambios pendientes en las notas. Repositorio limpio." -ForegroundColor Green
        return
    }

    git -C $notesDir add -A
    $nowStr = Get-Date -Format 'yyyy-MM-dd HH:mm'
    $commitMsg = if ($Message) { $Message } else { "docs(notes): update notes $nowStr" }

    $null = git -C $notesDir commit -m $commitMsg
    if ($LASTEXITCODE -eq 0) {
        $shortHash = git -C $notesDir rev-parse --short HEAD
        Write-Host "✓ Notas sincronizadas en Git local (commit $shortHash): $commitMsg" -ForegroundColor Green
    } else {
        Write-Warning "No se pudo realizar el commit en $notesDir."
    }
}
Set-Alias nsync notes-sync
Set-Alias note-commit notes-sync
Set-Alias note-save notes-sync

# ------------------------------------------------------------------------------
# 6. ENVOLTORIO notes (compatible con navegación y atajo a note)
# ------------------------------------------------------------------------------
function notes {
    <#
    .SYNOPSIS
        Navega a la carpeta de notas o ejecuta 'note' si recibe argumentos.
    .EXAMPLE
        notes
        notes "Hacer prueba de traspasos"
        notes yesterday
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        $Arguments
    )
    if ($Arguments) {
        note @Arguments
    } else {
        Set-Location $global:NotesDir
    }
}

# ------------------------------------------------------------------------------
# 7. GESTOR DE TAREAS: todo (alias: todos, tasks)
# ------------------------------------------------------------------------------
function Get-NoteTasks {
    param(
        [int]$Days = 7,
        [switch]$IncludeDone,
        [switch]$TodayOnly
    )

    $notesDir = $global:NotesDir
    $todayStr = Get-Date -Format 'yyyyMMdd'
    $today = (Get-Date).Date

    $query = @(Get-ChildItem -Path $notesDir -Filter "*.md" |
               Where-Object { $_.BaseName -match '^\d{8}$' } |
               Sort-Object Name -Descending)

    if ($TodayOnly) {
        $query = @($query | Where-Object { $_.BaseName -eq $todayStr })
    }
    elseif ($Days -gt 0) {
        $cutoffDate = $today.AddDays(-$Days)
        $query = @($query | Where-Object {
            try {
                $d = [DateTime]::ParseExact($_.BaseName, 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture)
                $d -ge $cutoffDate
            } catch { $false }
        })
    }

    $results = @()
    $taskRegex = '^\s*[-*]\s*\[([ xX>~])\]\s*(.*)$'

    foreach ($file in $query) {
        $lines = [System.IO.File]::ReadAllLines($file.FullName, [System.Text.Encoding]::UTF8)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line -match $taskRegex) {
                $marker = $matches[1]
                $desc = $matches[2].Trim()
                $isDone = ($marker -match '[xX]')
                $isMoved = ($marker -eq '>')

                if ($IncludeDone -or (-not $isDone -and -not $isMoved)) {
                    $results += [PSCustomObject]@{
                        File       = $file.FullName
                        FileName   = $file.Name
                        BaseName   = $file.BaseName
                        LineNumber = ($i + 1)
                        Done       = $isDone
                        Moved      = $isMoved
                        Text       = $desc
                        RawLine    = $line
                    }
                }
            }
        }
    }

    return $results
}

function todo {
    <#
    .SYNOPSIS
        Gestor interactivo de tareas y pendientes en notas diarias (- [ ]).
    .EXAMPLE
        todo                                # Lista tareas pendientes de los últimos 7 días
        todo "Revisar stock en pre"         # Añade una nueva tarea a la nota de hoy
        todo -Today                         # Solo tareas de hoy
        todo -Done                          # Muestra también completadas (- [x])
        todo -Days 14                       # Revisa notas de los últimos 14 días
        todo -Open 2                        # Abre Neovim en la línea exacta de la tarea 2
        todo -Check 2                       # Marca la tarea 2 como hecha en el archivo markdown
        todo -Uncheck 2                     # Desmarca la tarea 2
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Add', ValueFromPipeline = $true)]
        [string]$Task,

        [Parameter(ParameterSetName = 'List')]
        [int]$Days = 7,

        [Parameter(ParameterSetName = 'List')]
        [switch]$Today,

        [Parameter(ParameterSetName = 'List')]
        [switch]$Done,

        [Parameter(ParameterSetName = 'List')]
        [switch]$All,

        [Parameter(ParameterSetName = 'Open')]
        [int]$Open,

        [Parameter(ParameterSetName = 'Check')]
        [int]$Check,

        [Parameter(ParameterSetName = 'Uncheck')]
        [int]$Uncheck
    )

    $notesDir = $global:NotesDir
    $todayStr = Get-Date -Format 'yyyyMMdd'
    $todayFile = Join-Path $notesDir "$todayStr.md"

    # Caso 1: Añadir tarea
    if ($PSCmdlet.ParameterSetName -eq 'Add' -and $Task) {
        if (-not (Test-Path -LiteralPath $todayFile)) {
            $header = "# $todayStr`r`n`r`n"
            [System.IO.File]::WriteAllText($todayFile, $header, [System.Text.Encoding]::UTF8)
        }
        $timeStr = Get-Date -Format 'HH:mm'
        $newLine = "- [ ] [$timeStr] $Task"
        Add-Content -LiteralPath $todayFile -Value $newLine -Encoding UTF8
        Write-Host "✓ Tarea añadida en $todayStr.md: " -ForegroundColor Green -NoNewline
        Write-Host "[$timeStr] $Task" -ForegroundColor White
        return
    }

    # Obtener tareas según contexto
    $includeCompleted = ($Done -or $All -or $Uncheck -or $Open)
    $scannedDays = if ($All) { 0 } else { $Days }
    $tasks = @(Get-NoteTasks -Days $scannedDays -IncludeDone:$includeCompleted -TodayOnly:$Today)

    # Caso 2: Abrir en Neovim
    if ($Open) {
        if ($Open -ge 1 -and $Open -le $tasks.Count) {
            $t = $tasks[$Open - 1]
            Write-Host "● Abriendo $($t.FileName) en línea $($t.LineNumber)..." -ForegroundColor Cyan
            nvim "+$($t.LineNumber)" "$($t.File)"
            return
        } else {
            Write-Error "Índice $Open fuera de rango (hay $($tasks.Count) tareas listadas)."
            return
        }
    }

    # Caso 3: Marcar tarea como completada (-Check)
    if ($Check) {
        if ($Check -ge 1 -and $Check -le $tasks.Count) {
            $t = $tasks[$Check - 1]
            $fileLines = [System.IO.File]::ReadAllLines($t.File, [System.Text.Encoding]::UTF8)
            $idx = $t.LineNumber - 1
            if ($fileLines[$idx] -match '^\s*[-*]\s*\[ \]') {
                $fileLines[$idx] = $fileLines[$idx] -replace '^\s*[-*]\s*\[ \]', '- [x]'
                $crlfContent = ($fileLines -join "`r`n") + "`r`n"
                $utf8Bom = New-Object System.Text.UTF8Encoding($true)
                [System.IO.File]::WriteAllText($t.File, $crlfContent, $utf8Bom)
                Write-Host "✓ Tarea [$Check] marcada como COMPLETADA en $($t.FileName):" -ForegroundColor Green
                Write-Host "  $($t.Text)" -ForegroundColor White
            } else {
                Write-Host "ℹ La tarea ya estaba completada o modificada en $($t.FileName)." -ForegroundColor Yellow
            }
            return
        } else {
            Write-Error "Índice $Check fuera de rango (hay $($tasks.Count) tareas listadas)."
            return
        }
    }

    # Caso 4: Desmarcar tarea (-Uncheck)
    if ($Uncheck) {
        if ($Uncheck -ge 1 -and $Uncheck -le $tasks.Count) {
            $t = $tasks[$Uncheck - 1]
            $fileLines = [System.IO.File]::ReadAllLines($t.File, [System.Text.Encoding]::UTF8)
            $idx = $t.LineNumber - 1
            if ($fileLines[$idx] -match '^\s*[-*]\s*\[[xX]\]') {
                $fileLines[$idx] = $fileLines[$idx] -replace '^\s*[-*]\s*\[[xX]\]', '- [ ]'
                $crlfContent = ($fileLines -join "`r`n") + "`r`n"
                $utf8Bom = New-Object System.Text.UTF8Encoding($true)
                [System.IO.File]::WriteAllText($t.File, $crlfContent, $utf8Bom)
                Write-Host "✓ Tarea [$Uncheck] desmarcada como PENDIENTE en $($t.FileName):" -ForegroundColor Cyan
                Write-Host "  $($t.Text)" -ForegroundColor White
            } else {
                Write-Host "ℹ La tarea no estaba marcada como completada en $($t.FileName)." -ForegroundColor Yellow
            }
            return
        } else {
            Write-Error "Índice $Uncheck fuera de rango (hay $($tasks.Count) tareas listadas)."
            return
        }
    }

    # Caso 5: Listar tareas en pantalla
    if ($tasks.Count -eq 0) {
        Write-Host "`n✓ No hay tareas pendientes en las notas recientes. ¡Todo al día!`n" -ForegroundColor Green
        return
    }

    $titleFilter = if ($Today) { "Hoy" } elseif ($All) { "Historial completo" } else { "Últimos $Days días" }
    Write-Host "`n=== Tareas en Notas ($titleFilter) ===`n" -ForegroundColor DarkCyan

    $groups = $tasks | Group-Object BaseName
    $taskIdx = 1

    foreach ($g in $groups) {
        $dateStr = $g.Name
        $fileDate = [DateTime]::ParseExact($dateStr, 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture)
        $diffDays = ((Get-Date).Date - $fileDate.Date).Days
        $relLabel = switch ($diffDays) {
            0 { "Hoy" }
            1 { "Ayer" }
            default { "Hace $diffDays días" }
        }

        Write-Host " [$dateStr ($relLabel)]" -ForegroundColor Yellow
        foreach ($item in $g.Group) {
            $numTag = "  [$taskIdx]".PadRight(8)
            $box = if ($item.Done) { "[x]" } else { "[ ]" }
            $boxColor = if ($item.Done) { "Green" } else { "Cyan" }
            $textColor = if ($item.Done) { "DarkGray" } else { "White" }

            Write-Host $numTag -ForegroundColor DarkGray -NoNewline
            Write-Host "$box " -ForegroundColor $boxColor -NoNewline
            Write-Host "$($item.Text)" -ForegroundColor $textColor -NoNewline
            Write-Host " (L:$($item.LineNumber))" -ForegroundColor DarkGray

            $taskIdx++
        }
        Write-Host ""
    }

    $pendingCount = @($tasks | Where-Object { -not $_.Done }).Count
    $doneCount = @($tasks | Where-Object { $_.Done }).Count

    Write-Host "Total: $pendingCount pendiente(s)" -NoNewline -ForegroundColor White
    if ($doneCount -gt 0) {
        Write-Host ", $doneCount completada(s)" -NoNewline -ForegroundColor DarkGray
    }
    Write-Host "."
    Write-Host "Tip: Usa 'todo -Check <n>' para tachar, 'todo -Open <n>' para abrir en Neovim o 'note-roll' para traspasar pendientes a hoy.`n" -ForegroundColor DarkGray
}
Set-Alias todos todo
Set-Alias tasks todo

# ------------------------------------------------------------------------------
# 8. ROLLOVER DE TAREAS: note-roll (alias: note-rollover, roll-todos)
# ------------------------------------------------------------------------------
function note-roll {
    <#
    .SYNOPSIS
        Traspasa automáticamente las tareas no completadas (- [ ]) del día anterior a la nota de hoy.
    .EXAMPLE
        note-roll
        note-roll -DaysAgo 2
        note-roll -MarkMoved
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$DaysAgo = 0,

        [Parameter()]
        [switch]$MarkMoved
    )

    $notesDir = $global:NotesDir
    $todayStr = Get-Date -Format 'yyyyMMdd'
    $todayFile = Join-Path $notesDir "$todayStr.md"

    # Encontrar la nota anterior relevante (ayer o último día con nota registrada)
    $candidateFiles = @(Get-ChildItem -Path $notesDir -Filter "*.md" |
                        Where-Object { $_.BaseName -match '^\d{8}$' -and $_.BaseName -lt $todayStr } |
                        Sort-Object Name -Descending)

    if ($candidateFiles.Count -eq 0) {
        Write-Host "ℹ No se encontraron notas anteriores para traspasar tareas." -ForegroundColor Yellow
        return
    }

    $prevFile = if ($DaysAgo -gt 0 -and $DaysAgo -le $candidateFiles.Count) {
        $candidateFiles[$DaysAgo - 1]
    } else {
        $candidateFiles[0]
    }

    $prevStr = $prevFile.BaseName
    $prevLines = [System.IO.File]::ReadAllLines($prevFile.FullName, [System.Text.Encoding]::UTF8)

    $taskRegex = '^\s*[-*]\s*\[ \]\s*(.*)$'
    $pendingTasks = @()
    $pendingIndices = @()

    for ($i = 0; $i -lt $prevLines.Count; $i++) {
        if ($prevLines[$i] -match $taskRegex) {
            $pendingTasks += $matches[1].Trim()
            $pendingIndices += $i
        }
    }

    if ($pendingTasks.Count -eq 0) {
        Write-Host "✓ No hay tareas pendientes en la nota anterior ($prevStr.md). ¡Todo al día!" -ForegroundColor Green
        return
    }

    # Asegurar nota de hoy
    if (-not (Test-Path -LiteralPath $todayFile)) {
        $header = "# $todayStr`r`n`r`n"
        [System.IO.File]::WriteAllText($todayFile, $header, [System.Text.Encoding]::UTF8)
        Write-Host "● Creada nueva nota diaria: $todayStr.md" -ForegroundColor Cyan
    }

    $todayContent = [System.IO.File]::ReadAllText($todayFile, [System.Text.Encoding]::UTF8)

    # Filtrar las tareas que ya estén traspasadas a hoy para evitar duplicados
    $toAdd = @()
    foreach ($task in $pendingTasks) {
        if (-not ($todayContent.Contains($task))) {
            $toAdd += "- [ ] $task"
        }
    }

    if ($toAdd.Count -eq 0) {
        Write-Host "ℹ Todas las tareas pendientes de $prevStr.md ya estaban presentes en $todayStr.md." -ForegroundColor Yellow
        return
    }

    # Agregar encabezado de sección en hoy si no existe
    $appendLines = @()
    $appendLines += ""
    $appendLines += "## Pendientes de $prevStr"
    $appendLines += $toAdd

    $crlfToAppend = ($appendLines -join "`r`n") + "`r`n"
    [System.IO.File]::AppendAllText($todayFile, $crlfToAppend, [System.Text.Encoding]::UTF8)

    # Si se pide marcar en el origen (-MarkMoved)
    if ($MarkMoved) {
        foreach ($idx in $pendingIndices) {
            $prevLines[$idx] = $prevLines[$idx] -replace '^\s*[-*]\s*\[ \]', '- [>]'
        }
        $crlfPrev = ($prevLines -join "`r`n") + "`r`n"
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($prevFile.FullName, $crlfPrev, $utf8Bom)
    }

    Write-Host "✓ $($toAdd.Count) tarea(s) pendiente(s) de $prevStr.md traspasadas a $todayStr.md:" -ForegroundColor Green
    foreach ($item in $toAdd) {
        Write-Host "  • $($item -replace '^-\s*\[ \]\s*', '')" -ForegroundColor White
    }
}
Set-Alias note-rollover note-roll
Set-Alias roll-todos note-roll

# ------------------------------------------------------------------------------
# 9. CAPTURA DE PORTAPAPELES: nclip (alias: note-clip)
# ------------------------------------------------------------------------------
function nclip {
    <#
    .SYNOPSIS
        Captura el contenido actual del portapapeles y lo añade a la nota de hoy como bloque de código o texto formateado.
    .EXAMPLE
        nclip
        nclip "Error en wizard de traspasos"
        nclip "Consulta de saldo" -Lang sql
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Title = "Captura de portapapeles",

        [Parameter(Position = 1)]
        [string]$Lang = ""
    )

    $clipText = Get-Clipboard
    if (-not $clipText -or [string]::IsNullOrWhiteSpace(($clipText -join ""))) {
        Write-Warning "El portapapeles está vacío o no contiene texto."
        return
    }

    $notesDir = $global:NotesDir
    if (-not (Test-Path -LiteralPath $notesDir)) {
        New-Item -ItemType Directory -Path $notesDir -Force | Out-Null
    }

    $todayStr = Get-Date -Format 'yyyyMMdd'
    $todayFile = Join-Path $notesDir "$todayStr.md"

    if (-not (Test-Path -LiteralPath $todayFile)) {
        $header = "# $todayStr`r`n`r`n"
        [System.IO.File]::WriteAllText($todayFile, $header, [System.Text.Encoding]::UTF8)
    }

    $timeStr = Get-Date -Format 'HH:mm'
    $clipJoined = if ($clipText -is [array]) { $clipText -join "`r`n" } else { [string]$clipText }

    $codeFence = '```' + $Lang
    $linesToAppend = @(
        "",
        "#### $Title [$timeStr]",
        $codeFence,
        $clipJoined.TrimEnd(),
        '```',
        ""
    )

    $crlfBlock = ($linesToAppend -join "`r`n") + "`r`n"
    [System.IO.File]::AppendAllText($todayFile, $crlfBlock, [System.Text.Encoding]::UTF8)

    $lineCount = ($clipJoined -split "`r?`n").Count
    Write-Host "✓ Portapapeles guardado en $todayStr.md ($lineCount líneas): " -ForegroundColor Green -NoNewline
    Write-Host "$Title [$timeStr]" -ForegroundColor White
}
Set-Alias note-clip nclip

# ------------------------------------------------------------------------------
# 10. NOTAS TEMÁTICAS / PROYECTOS: ntopic (alias: note-topic) y ltopics
# ------------------------------------------------------------------------------
function ntopic {
    <#
    .SYNOPSIS
        Gestiona notas por tema o proyecto en Documentos\Notes\topics\<tema>.md.
    .DESCRIPTION
        Si se pasa texto, lo añade a la nota temática con timestamp.
        Si solo se pasa el tema, abre la nota en Neovim.
    .EXAMPLE
        ntopic cinfa "Reunión con soporte sobre sincronización"
        ntopic cinfa
        ntopic rsga-back
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Topic,

        [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
        [string[]]$Text
    )

    $topicsDir = Join-Path $global:NotesDir "topics"
    if (-not (Test-Path -LiteralPath $topicsDir)) {
        New-Item -ItemType Directory -Path $topicsDir -Force | Out-Null
    }

    $cleanTopic = ($Topic -replace '[^\w\-]', '_').Trim('_').ToLowerInvariant()
    $topicFile = Join-Path $topicsDir "$cleanTopic.md"

    if (-not (Test-Path -LiteralPath $topicFile)) {
        $header = "# Tema: $cleanTopic`r`n`r`n"
        [System.IO.File]::WriteAllText($topicFile, $header, [System.Text.Encoding]::UTF8)
        Write-Host "● Creada nueva nota temática: topics\$cleanTopic.md" -ForegroundColor Cyan
    }

    if ($Text -and $Text.Count -gt 0) {
        $body = ($Text -join " ").Trim()
        $nowStr = Get-Date -Format 'yyyy-MM-dd HH:mm'
        $entry = "- [$nowStr] $body"
        [System.IO.File]::AppendAllText($topicFile, "$entry`r`n", [System.Text.Encoding]::UTF8)
        Write-Host "✓ Apuntado en topics\$cleanTopic.md: " -ForegroundColor Green -NoNewline
        Write-Host $body -ForegroundColor White
    } else {
        nvim $topicFile "+"
    }
}
Set-Alias note-topic ntopic

function ltopics {
    <#
    .SYNOPSIS
        Lista todas las notas temáticas en Documentos\Notes\topics\ con fecha de última modificación y tamaño.
    .EXAMPLE
        ltopics
        ltopics -Open cinfa
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Open
    )

    $topicsDir = Join-Path $global:NotesDir "topics"
    if (-not (Test-Path -LiteralPath $topicsDir)) {
        Write-Host "● No hay notas temáticas creadas todavía en $topicsDir." -ForegroundColor DarkGray
        return
    }

    if ($Open) {
        ntopic $Open
        return
    }

    $files = Get-ChildItem -Path $topicsDir -Filter "*.md" | Sort-Object LastWriteTime -Descending
    if (-not $files -or $files.Count -eq 0) {
        Write-Host "● No hay notas temáticas creadas todavía." -ForegroundColor DarkGray
        return
    }

    Write-Host "`n=== Notas Temáticas ($topicsDir) ===`n" -ForegroundColor DarkCyan
    $idx = 1
    foreach ($f in $files) {
        $nameTag = "[$idx] $($f.BaseName)".PadRight(25)
        $modDate = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
        $sizeKB = [Math]::Round($f.Length / 1KB, 1)

        $lines = [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)
        $preview = ""
        foreach ($l in $lines) {
            $t = $l.Trim()
            if ($t -and -not $t.StartsWith("#")) {
                $preview = if ($t.Length -gt 55) { $t.Substring(0, 52) + "..." } else { $t }
                break
            }
        }
        if (-not $preview) { $preview = "(Sin apuntes adicionales)" }

        Write-Host "  $nameTag" -NoNewline -ForegroundColor Yellow
        Write-Host "$modDate  " -NoNewline -ForegroundColor DarkGray
        Write-Host "($([string]$sizeKB + ' KB'))  ".PadRight(12) -NoNewline -ForegroundColor DarkCyan
        Write-Host "-> $preview" -ForegroundColor White

        $idx++
    }
    Write-Host "`nTip: Usa 'ntopic <nombre>' para abrir o añadir contenido a cualquier tema.`n" -ForegroundColor DarkGray
}
Set-Alias list-topics ltopics

# Autocompletado con Tab para ntopic
if (Get-Command Register-ArgumentCompleter -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -CommandName ntopic -ParameterName Topic -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $topicsDir = Join-Path $global:NotesDir "topics"
        if (Test-Path -LiteralPath $topicsDir) {
            Get-ChildItem -Path $topicsDir -Filter "*.md" |
                Where-Object { $_.BaseName -like "$wordToComplete*" } |
                ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_.BaseName, $_.BaseName, 'ParameterValue', "Nota temática: $($_.BaseName)")
                }
        }
    }
}

# ------------------------------------------------------------------------------
# 11. PLANTILLA DE REUNIONES: nmeeting (alias: note-meeting)
# ------------------------------------------------------------------------------
function nmeeting {
    <#
    .SYNOPSIS
        Inserta una plantilla de reunión estructurada en la nota de hoy o en una nota temática.
    .EXAMPLE
        nmeeting "Sincronización sprint 14"
        nmeeting "Arquitectura nuevo microservicio" -Topic "arquitectura"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter(Position = 1)]
        [string]$Topic
    )

    $timeStr = Get-Date -Format 'HH:mm'
    $todayStr = Get-Date -Format 'yyyyMMdd'

    $targetFile = if ($Topic) {
        $topicsDir = Join-Path $global:NotesDir "topics"
        if (-not (Test-Path -LiteralPath $topicsDir)) {
            New-Item -ItemType Directory -Path $topicsDir -Force | Out-Null
        }
        Join-Path $topicsDir "$($Topic.ToLowerInvariant()).md"
    } else {
        Join-Path $global:NotesDir "$todayStr.md"
    }

    if (-not (Test-Path -LiteralPath $targetFile)) {
        $header = if ($Topic) { "# Tema: $Topic`r`n`r`n" } else { "# $todayStr`r`n`r`n" }
        [System.IO.File]::WriteAllText($targetFile, $header, [System.Text.Encoding]::UTF8)
    }

    $template = @(
        "",
        "### Reunión: $Title [$timeStr]",
        "- **Asistentes:** ",
        "- **Objetivo / Puntos tratados:**",
        "  - ",
        "- **Acuerdos y Próximos pasos:**",
        "  - [ ] ",
        ""
    )

    $crlfBlock = ($template -join "`r`n") + "`r`n"
    [System.IO.File]::AppendAllText($targetFile, $crlfBlock, [System.Text.Encoding]::UTF8)

    Write-Host "✓ Plantilla de reunión añadida en $(Split-Path $targetFile -Leaf): " -ForegroundColor Green -NoNewline
    Write-Host "$Title [$timeStr]" -ForegroundColor White
}
Set-Alias note-meeting nmeeting

# ------------------------------------------------------------------------------
# 12. ETIQUETAS Y HASHTAGS: ntag (alias: note-tag) y ltags
# ------------------------------------------------------------------------------
function ntag {
    <#
    .SYNOPSIS
        Busca notas que contengan una etiqueta o hashtag específico (#tag).
    .EXAMPLE
        ntag bug
        ntag sql
        ntag urgente
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Tag
    )

    $cleanTag = ($Tag.TrimStart('#')).Trim()
    $pattern = "#$cleanTag\b"

    $notesDir = $global:NotesDir
    if (-not (Test-Path -LiteralPath $notesDir)) {
        Write-Warning "No se encuentra el directorio de notas en $notesDir."
        return
    }

    Write-Host "● Buscando etiqueta #$cleanTag en notas...`n" -ForegroundColor DarkCyan

    if (Get-Command rg -ErrorAction SilentlyContinue) {
        & rg -i --heading --line-number --color=always $pattern $notesDir
    } else {
        Get-ChildItem -Path $notesDir -Filter "*.md" -Recurse |
            Select-String -Pattern $pattern |
            ForEach-Object {
                $rel = $_.Path.Replace($notesDir, "").TrimStart("\/")
                Write-Host "${rel}:$($_.LineNumber): " -ForegroundColor Cyan -NoNewline
                Write-Host $_.Line
            }
    }
}
Set-Alias note-tag ntag

function ltags {
    <#
    .SYNOPSIS
        Analiza todas las notas y muestra un resumen estadístico de las etiquetas (#hashtags) utilizadas.
    .EXAMPLE
        ltags
    #>
    [CmdletBinding()]
    param()

    $notesDir = $global:NotesDir
    if (-not (Test-Path -LiteralPath $notesDir)) {
        Write-Warning "No se encuentra el directorio de notas en $notesDir."
        return
    }

    $files = Get-ChildItem -Path $notesDir -Filter "*.md" -Recurse
    $tagCounts = @{}
    $tagRegex = '#([a-zA-Z0-9_\-]+)'

    foreach ($f in $files) {
        $lines = [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)
        foreach ($line in $lines) {
            if ($line -match '^\s*#{1,6}\s+') { continue }

            $matches = [regex]::Matches($line, $tagRegex)
            foreach ($m in $matches) {
                $t = $m.Groups[1].Value.ToLowerInvariant()
                if ($t -notmatch '^\d+$') {
                    if ($tagCounts.ContainsKey($t)) {
                        $tagCounts[$t]++
                    } else {
                        $tagCounts[$t] = 1
                    }
                }
            }
        }
    }

    if ($tagCounts.Count -eq 0) {
        Write-Host "● No se han encontrado etiquetas (#tag) en las notas." -ForegroundColor DarkGray
        return
    }

    Write-Host "`n=== Etiquetas (#hashtags) en Notas ($($tagCounts.Count)) ===`n" -ForegroundColor DarkCyan

    $sortedTags = $tagCounts.GetEnumerator() | Sort-Object Value -Descending
    foreach ($entry in $sortedTags) {
        $tagCol = "  #$($entry.Key)".PadRight(25)
        $countCol = "$($entry.Value) mención(es)".PadLeft(14)
        Write-Host $tagCol -NoNewline -ForegroundColor Yellow
        Write-Host $countCol -ForegroundColor Cyan
    }
    Write-Host "`nTip: Usa 'ntag <etiqueta>' para ver las líneas exactas de cualquier tag.`n" -ForegroundColor DarkGray
}
Set-Alias list-tags ltags

# ------------------------------------------------------------------------------
# 13. ACTIVIDAD GIT DEL DÍA: ngit (alias: note-git)
# ------------------------------------------------------------------------------
function ngit {
    <#
    .SYNOPSIS
        Inserta en la nota diaria los commits realizados hoy en el repositorio actual o en todos los repositorios.
    .DESCRIPTION
        - Sin parámetros: extrae los commits de hoy del repositorio Git actual.
        - Con 'repos', 'all' o switch -Repos: escanea recursivamente todos los proyectos en Documentos\Proyectos y extrae los commits de todos los repositorios con actividad hoy.
        - Con <nombre>: busca un repositorio específico en Documentos\Proyectos y extrae sus commits sin necesidad de cambiar de carpeta.
    .EXAMPLE
        ngit
        ngit repos
        ngit -Repos
        ngit rsga
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Target,

        [Parameter(Position = 1)]
        [string]$Author,

        [Alias('All')]
        [switch]$Repos,

        [Alias('Anyone')]
        [switch]$AllAuthors
    )

    $isAllRepos = ($Repos -or ($Target -and $Target -in @('repos', 'all', 'proyectos', '-repos', '-all')))
    $targetRepos = @()

    if ($isAllRepos) {
        Write-Host "● Escaneando repositorios en busca de commits propios realizados hoy..." -ForegroundColor DarkCyan
        $discovered = @()
        if (Get-Command Get-ProfileGitRepositories -ErrorAction SilentlyContinue) {
            $discovered = @(Get-ProfileGitRepositories)
        } else {
            $projDir = if ($global:ProjectsRoot) { $global:ProjectsRoot } else { "Documentos\Proyectos" }
            if (Test-Path -LiteralPath $projDir) {
                $discovered = @(Get-ChildItem -Path $projDir -Directory -Recurse -Depth 3 | Where-Object { Test-Path (Join-Path $_.FullName ".git") })
            }
        }

        # Incluir también el repositorio actual si estamos en uno y no está ya en la lista
        $gitCheck = git rev-parse --is-inside-work-tree 2>$null
        if ($gitCheck -eq 'true') {
            $currentTop = (git rev-parse --show-toplevel 2>$null)
            if ($currentTop) {
                $alreadyIn = $discovered | Where-Object { $_.FullName -eq $currentTop }
                if (-not $alreadyIn) {
                    $discovered += [System.IO.DirectoryInfo]::new($currentTop)
                }
            }
        }

        if ($discovered.Count -eq 0) {
            Write-Warning "No se encontraron repositorios Git en '$global:ProjectsRoot'."
            return
        }

        $targetRepos = $discovered
    }
    elseif ($Target) {
        # Buscar repositorio específico por nombre aproximado
        $discovered = @()
        if (Get-Command Get-ProfileGitRepositories -ErrorAction SilentlyContinue) {
            $discovered = @(Get-ProfileGitRepositories)
        }
        $match = $discovered | Where-Object { $_.Name -like "*$Target*" -or $_.FullName -like "*$Target*" } | Select-Object -First 1
        if (-not $match) {
            Write-Error "No se encontró ningún repositorio Git que coincida con '$Target'."
            return
        }
        $targetRepos = @($match)
    }
    else {
        # Repositorio actual
        $gitCheck = git rev-parse --is-inside-work-tree 2>$null
        if ($gitCheck -ne 'true') {
            Write-Warning "El directorio actual no es un repositorio Git.`nTip: Usa 'ngit repos' para escanear automáticamente todos tus proyectos."
            return
        }
        $topLevel = git rev-parse --show-toplevel 2>$null
        $targetRepos = @([System.IO.DirectoryInfo]::new($topLevel))
    }

    $notesDir = $global:NotesDir
    if (-not (Test-Path -LiteralPath $notesDir)) {
        New-Item -ItemType Directory -Path $notesDir -Force | Out-Null
    }

    $todayStr = Get-Date -Format 'yyyyMMdd'
    $todayFile = Join-Path $notesDir "$todayStr.md"

    if (-not (Test-Path -LiteralPath $todayFile)) {
        $header = "# $todayStr`r`n`r`n"
        [System.IO.File]::WriteAllText($todayFile, $header, [System.Text.Encoding]::UTF8)
    }

    $timeStr = Get-Date -Format 'HH:mm'
    $collectedBlocks = @()
    $totalCommits = 0
    $activeRepoCount = 0

    foreach ($repo in $targetRepos) {
        $repoPath = $repo.FullName
        $repoName = $repo.Name

        # Filtro de autor: por defecto solo los commits del propio usuario configurado en ese repo
        $authorFlags = @()
        if (-not $AllAuthors) {
            if ($Author) {
                $authorFlags += @('-F', "--author=$Author")
            } else {
                $rEmail = git -C "$repoPath" config user.email 2>$null
                $rUser  = git -C "$repoPath" config user.name 2>$null
                if ($rEmail) { $authorFlags += @('-F', "--author=$rEmail") }
                if ($rUser)  { $authorFlags += @('-F', "--author=$rUser") }
                if (-not $rEmail -and -not $rUser) {
                    $authorFlags += @('-F', "--author=$env:USERNAME")
                }
            }
        }

        $commitsRaw = git -C "$repoPath" log --since="midnight" @authorFlags --format="format:- [%h] %s" 2>$null
        if (-not $commitsRaw -or [string]::IsNullOrWhiteSpace(($commitsRaw -join ""))) {
            if (-not $isAllRepos) {
                Write-Host "● No hay commits registrados hoy en '$repoName' para tu usuario." -ForegroundColor Yellow
            }
            continue
        }

        $commitList = if ($commitsRaw -is [array]) { $commitsRaw } else { @($commitsRaw) }
        $totalCommits += $commitList.Count
        $activeRepoCount++

        $linesForRepo = @(
            "",
            "### Commits en $repoName [$timeStr]:"
        ) + $commitList + @("")

        $collectedBlocks += ($linesForRepo -join "`r`n") + "`r`n"

        Write-Host "✓ $($commitList.Count) commit(s) en $($repoName):" -ForegroundColor Green
        foreach ($c in $commitList) {
            Write-Host "  $c" -ForegroundColor White
        }
    }

    if ($collectedBlocks.Count -eq 0) {
        if ($isAllRepos) {
            Write-Host "● No se detectaron commits de hoy en ninguno de los $($targetRepos.Count) repositorios escaneados." -ForegroundColor Yellow
        }
        return
    }

    $allCrlf = $collectedBlocks -join ""
    [System.IO.File]::AppendAllText($todayFile, $allCrlf, [System.Text.Encoding]::UTF8)

    if ($isAllRepos) {
        Write-Host "`n✓ Total: $totalCommits commit(s) de $activeRepoCount repositorio(s) añadidos a $todayStr.md." -ForegroundColor Green
    }
}
Set-Alias note-git ngit

# Autocompletado con Tab para ngit
if (Get-Command Register-ArgumentCompleter -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -CommandName ngit -ParameterName Target -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $candidates = [System.Collections.Generic.List[string]]::new()
        $candidates.Add('repos')
        $candidates.Add('all')

        if (Get-Command Get-ProfileGitRepositories -ErrorAction SilentlyContinue) {
            foreach ($r in (Get-ProfileGitRepositories)) {
                $candidates.Add($r.Name)
            }
        }

        $candidates |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object {
                $desc = if ($_ -in @('repos', 'all')) { "Escanear todos los proyectos" } else { "Proyecto Git: $_" }
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $desc)
            }
    }
}

# ------------------------------------------------------------------------------
# 14. RESUMEN DE TRABAJO & DAILY: standup (alias: note-standup)
# ------------------------------------------------------------------------------
function standup {
    <#
    .SYNOPSIS
        Genera un resumen diario (Daily Standup) con lo hecho ayer, lo pendiente hoy y opción de copiar al portapapeles.
    .EXAMPLE
        standup
        standup -Clip
    #>
    [CmdletBinding()]
    param(
        [switch]$Clip
    )

    $notesDir = $global:NotesDir
    $todayStr = Get-Date -Format 'yyyyMMdd'
    $todayFile = Join-Path $notesDir "$todayStr.md"

    # Encontrar la nota anterior relevante (ayer o viernes)
    $candidateFiles = @(Get-ChildItem -Path $notesDir -Filter "*.md" |
                        Where-Object { $_.BaseName -match '^\d{8}$' -and $_.BaseName -lt $todayStr } |
                        Sort-Object Name -Descending)

    $doneYesterday = @()
    $prevDateStr = ""
    if ($candidateFiles.Count -gt 0) {
        $prevFile = $candidateFiles[0]
        $prevDateStr = $prevFile.BaseName
        $prevLines = [System.IO.File]::ReadAllLines($prevFile.FullName, [System.Text.Encoding]::UTF8)
        foreach ($l in $prevLines) {
            if ($l -match '^\s*[-*]\s*\[[xX]\]\s*(.*)$') {
                $doneYesterday += $matches[1].Trim()
            }
        }
    }

    # Tareas pendientes de hoy
    $pendingToday = @()
    if (Test-Path -LiteralPath $todayFile) {
        $todayLines = [System.IO.File]::ReadAllLines($todayFile, [System.Text.Encoding]::UTF8)
        foreach ($l in $todayLines) {
            if ($l -match '^\s*[-*]\s*\[ \]\s*(.*)$') {
                $pendingToday += $matches[1].Trim()
            }
        }
    }

    # Si no hay pendientes en hoy, comprobar si hay pendientes de la nota anterior
    if ($pendingToday.Count -eq 0 -and $candidateFiles.Count -gt 0) {
        $prevLines = [System.IO.File]::ReadAllLines($candidateFiles[0].FullName, [System.Text.Encoding]::UTF8)
        foreach ($l in $prevLines) {
            if ($l -match '^\s*[-*]\s*\[ \]\s*(.*)$') {
                $pendingToday += $matches[1].Trim()
            }
        }
    }

    $reportLines = @()
    $reportLines += "## Daily Standup - $(Get-Date -Format 'yyyy-MM-dd')"
    $reportLines += ""
    $reportLines += "### Ayer $(if ($prevDateStr) { "($prevDateStr)" }):"
    if ($doneYesterday.Count -gt 0) {
        foreach ($d in $doneYesterday) {
            $reportLines += "- $d"
        }
    } else {
        $reportLines += "- (Sin tareas marcadas como completadas)"
    }

    $reportLines += ""
    $reportLines += "### Hoy:"
    if ($pendingToday.Count -gt 0) {
        foreach ($p in $pendingToday) {
            $reportLines += "- $p"
        }
    } else {
        $reportLines += "- Continuar tareas en curso / backlog"
    }

    $reportLines += ""
    $reportLines += "### Bloqueos / Impedimentos:"
    $reportLines += "- Ninguno"

    $reportText = $reportLines -join "`r`n"

    Write-Host "`n┌─ Daily Standup ───────────────────────────────────────────┐" -ForegroundColor DarkCyan
    foreach ($line in $reportLines) {
        if ($line.StartsWith("## ")) {
            Write-Host "  $line" -ForegroundColor Yellow
        } elseif ($line.StartsWith("### ")) {
            Write-Host "  $line" -ForegroundColor Cyan
        } elseif ($line.StartsWith("- ")) {
            Write-Host "    $line" -ForegroundColor White
        } else {
            Write-Host ""
        }
    }
    Write-Host "└───────────────────────────────────────────────────────────┘`n" -ForegroundColor DarkCyan

    if ($Clip) {
        Set-Clipboard -Value $reportText
        Write-Host "✓ Resumen copiado al portapapeles listo para Teams o Slack." -ForegroundColor Green
    } else {
        Write-Host "Tip: Usa 'standup -Clip' para copiarlo directamente al portapapeles.`n" -ForegroundColor DarkGray
    }
}
Set-Alias note-standup standup





