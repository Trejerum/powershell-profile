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
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "ep"; Sintaxis = "ep [modulo]"; Detalle = "Abre `$PROFILE o un módulo específico en Neovim (ej. 'ep sql', 'ep git')"; Ejemplos = @("ep", "ep sql", "ep git") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "en"; Sintaxis = "en"; Detalle = "Abre la carpeta de configuración de Neovim (~AppData\Local\nvim) en Neovim (alias: edit-nvim)"; Ejemplos = @("en") }

        # 1.5. Notas & Diario Developer
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "note"; Sintaxis = "note [texto/fecha]"; Detalle = "Abre nota del día en Neovim o realiza capturas rápidas desde consola (alias: today, diario)"; Ejemplos = @("note", "note 'Revisar bug en traspasos'", "note yesterday", "note 2") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "snote"; Sintaxis = "snote <patrón>"; Detalle = "Busca texto en todas las notas históricas con Ripgrep resaltando en color (alias: find-note)"; Ejemplos = @("snote 'inventario'", "snote 'wizard'") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "vnote"; Sintaxis = "vnote <patrón>"; Detalle = "Busca texto en las notas con Ripgrep y abre resultados en Neovim con Quickfix (:copen)"; Ejemplos = @("vnote 'traspaso'") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "lnotes"; Sintaxis = "lnotes [n] [-Open n]"; Detalle = "Dashboard de notas recientes con fechas relativas y primeros puntos tratados (alias: recent-notes)"; Ejemplos = @("lnotes", "lnotes 5", "lnotes -Open 2") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "note-sql"; Sintaxis = "note-sql <nombre>"; Detalle = "Crea un script SQL fechado en Documentos\Notes\sql y lo abre en Neovim (alias: nsql)"; Ejemplos = @("note-sql fix_inventario") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "notes-sync"; Sintaxis = "notes-sync [mensaje]"; Detalle = "Registra y sincroniza todos los cambios de notas en el repo Git local (alias: nsync, note-save)"; Ejemplos = @("notes-sync", "notes-sync 'Reunión sprint'") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "todo"; Sintaxis = "todo [tarea] [-Done] [-Open n] [-Check n]"; Detalle = "Gestor interactivo de tareas/checklists en notas (- [ ]) con apertura o marcado directo (alias: todos, tasks)"; Ejemplos = @("todo", "todo 'Revisar stock'", "todo -Today", "todo -Check 1", "todo -Open 2") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "note-roll"; Sintaxis = "note-roll [-DaysAgo n] [-MarkMoved]"; Detalle = "Traspasa automáticamente las tareas no hechas (- [ ]) de la nota anterior a la de hoy (alias: note-rollover, roll-todos)"; Ejemplos = @("note-roll", "note-roll -MarkMoved") }

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
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "qenv"; Sintaxis = "qenv [perfil]"; Detalle = "Muestra o activa los entornos/conexiones de sql-connections.json (alias: qprofiles, qconns)"; Ejemplos = @("qenv", "qenv pre", "qenv local") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "q"; Sintaxis = "q <query/.sql> [switches]"; Detalle = "Motor ultrarrápido ADO.NET (switches: -Grid, -Clip, -Csv, -Json, -DryRun, -Timeout N)"; Ejemplos = @("q 'SELECT TOP 10 * FROM Articulos'", "q ./cambios.sql -DryRun", "q 'SELECT * FROM Clientes' -Grid") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "qconnect"; Sintaxis = "qconnect [perfil/srv] [bd]"; Detalle = "Abre una conexión persistente reutilizable de alto rendimiento (soporta perfiles de sql-connections.json)"; Ejemplos = @("qconnect", "qconnect pre", "qconnect 'PORT1220\\SQL_SERVER' 'SGA'") }
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
 


