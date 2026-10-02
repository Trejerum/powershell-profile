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
        $header = @"
-- ==============================================================================
-- Script: $filename
-- Fecha:  $nowStr
-- Autor:  $env:USERNAME
-- Base:   SGA
-- ==============================================================================

USE [SGA];
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


