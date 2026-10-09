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
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "proj"; Sintaxis = "proj [nombre]"; Detalle = "Navega dinámicamente a cualquier subproyecto con autocompletado <Tab> (alias de repos)"; Ejemplos = @("proj", "proj MiProyecto", "proj ApiService") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "scratch"; Sintaxis = "scratch [nombre] [-List] [-Clean n] [-v]"; Detalle = "Crea o navega a un sandbox desechable fechado en Documentos\Scratch (alias: sandbox)"; Ejemplos = @("scratch", "scratch test-api", "scratch -List", "scratch -Clean 7", "scratch -v") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "profile"; Sintaxis = "profile"; Detalle = "Navega al repositorio de dotfiles de PowerShell (~/.dotfiles/powershell) (alias: cdprofile, dotfiles)"; Ejemplos = @("profile", "cdprofile", "dotfiles") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "notes"; Sintaxis = "notes"; Detalle = "Navega a la carpeta de notas personales (`$HOME\Documentos\Notes)"; Ejemplos = @("notes") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = ".."; Sintaxis = "..  |  ...  |  ...."; Detalle = "Sube 1, 2 o 3 niveles de directorio en el árbol del sistema de archivos"; Ejemplos = @("..", "...", "....") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "mkcd"; Sintaxis = "mkcd <carpeta>"; Detalle = "Crea un directorio (incluyendo padres si no existen) y navega dentro de él de inmediato"; Ejemplos = @("mkcd backend/api/v2") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "open"; Sintaxis = "open [ruta]"; Detalle = "Abre la carpeta actual o la ruta indicada en el Explorador de archivos de Windows (alias: o)"; Ejemplos = @("open", "open .", "open ./logs") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "reload"; Sintaxis = "reload"; Detalle = "Recarga el perfil de PowerShell en la consola activa (alias: rel, rprof, reload-profile)"; Ejemplos = @("reload", "rel") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "profile-bench"; Sintaxis = "profile-bench"; Detalle = "Diagnóstico y benchmark del tiempo de arranque y coste de cada módulo del perfil (alias: pbench)"; Ejemplos = @("profile-bench", "pbench") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "ep"; Sintaxis = "ep [modulo]"; Detalle = "Abre `$PROFILE o un módulo específico en Neovim (ej. 'ep sql', 'ep git')"; Ejemplos = @("ep", "ep sql", "ep git") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "en"; Sintaxis = "en [archivo]"; Detalle = "Abre la carpeta de configuración de Neovim (~/.dotfiles/nvim) o un archivo específico en Neovim (alias: edit-nvim)"; Ejemplos = @("en", "en init.lua") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "nvim-config"; Sintaxis = "nvim-config [-Edit]"; Detalle = "Navega a la carpeta de configuración de Neovim (~/.dotfiles/nvim) (alias: cdnvim, cd-nvim, nvimdir)"; Ejemplos = @("nvim-config", "cdnvim", "nvim-config -Edit") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "mark"; Sintaxis = "mark [nombre]"; Detalle = "Guarda la carpeta actual con una etiqueta rápida de navegación compartida entre terminales"; Ejemplos = @("mark", "mark api", "mark logs") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "jump"; Sintaxis = "jump [nombre]"; Detalle = "Navega a un marcador guardado (alias: j, autocompleta con Tab o menú difuso si fzf)"; Ejemplos = @("jump api", "j logs", "j") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "marks"; Sintaxis = "marks"; Detalle = "Lista todos los marcadores guardados y su estado en disco (alias: lmarks)"; Ejemplos = @("marks", "lmarks") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "unmark"; Sintaxis = "unmark <nombre> [-All] [-Clean]"; Detalle = "Elimina un marcador, todos (-All) o purga rutas inexistentes (-Clean)"; Ejemplos = @("unmark api", "unmark -All", "unmark -Clean") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "layout-dev"; Sintaxis = "layout-dev [ruta] [-NewTab] [-NewWindow]"; Detalle = "Abre el espacio de 3 paneles en la pestaña actual (o -NewTab / -NewWindow) (alias: wtd, dev-layout)"; Ejemplos = @("wtd", "wtd mi-proyecto", "wtd -NewTab", "wtd -NewWindow") }
        [PSCustomObject]@{ Categoria = "Navegación & Entorno"; Comando = "split-term"; Sintaxis = "split-term [-V | -H]"; Detalle = "Divide el panel actual de Windows Terminal en la misma carpeta (alias: split-v, split-h)"; Ejemplos = @("split-term", "split-v", "split-h") }

        # 1.5. Notas & Diario Developer
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "note"; Sintaxis = "note [texto/fecha]"; Detalle = "Abre nota del día en Neovim o realiza capturas rápidas desde consola (alias: today, diario)"; Ejemplos = @("note", "note 'Revisar bug en traspasos'", "note yesterday", "note 2") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "nclip"; Sintaxis = "nclip [título] [-Lang <lang>]"; Detalle = "Captura el portapapeles y lo añade a la nota diaria como bloque de código formateado (alias: note-clip)"; Ejemplos = @("nclip", "nclip 'Error traspaso' -Lang sql", "nclip 'Stack trace'") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "ntopic"; Sintaxis = "ntopic <tema> [texto...]"; Detalle = "Gestiona notas temáticas por proyecto en Notes\topics\ con apertura en Neovim o apuntes rápidos (alias: note-topic)"; Ejemplos = @("ntopic cinfa", "ntopic cinfa 'Reunión soporte'", "ntopic rsga-back") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "ltopics"; Sintaxis = "ltopics [-Open <tema>]"; Detalle = "Lista todas las notas temáticas con fecha, tamaño y vista previa de contenido (alias: list-topics)"; Ejemplos = @("ltopics", "ltopics -Open cinfa") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "nmeeting"; Sintaxis = "nmeeting <título> [-Topic <tema>]"; Detalle = "Inserta plantilla estructurada de reunión (asistentes, temas, checklist) en hoy o en tema (alias: note-meeting)"; Ejemplos = @("nmeeting 'Sincronización sprint'", "nmeeting 'Arquitectura' -Topic 'arquitectura'") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "snote"; Sintaxis = "snote <patrón>"; Detalle = "Busca texto en todas las notas históricas con Ripgrep resaltando en color (alias: find-note)"; Ejemplos = @("snote 'inventario'", "snote 'wizard'") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "vnote"; Sintaxis = "vnote <patrón>"; Detalle = "Busca texto en las notas con Ripgrep y abre resultados en Neovim con Quickfix (:copen)"; Ejemplos = @("vnote 'traspaso'") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "ntag"; Sintaxis = "ntag <etiqueta>"; Detalle = "Busca notas que contengan un hashtag (#tag) específico usando Ripgrep resaltado (alias: note-tag)"; Ejemplos = @("ntag bug", "ntag urgente", "ntag sql") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "ltags"; Sintaxis = "ltags"; Detalle = "Analiza todas las notas y muestra un resumen estadístico de frecuencia de hashtags (alias: list-tags)"; Ejemplos = @("ltags") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "lnotes"; Sintaxis = "lnotes [n] [-Open n]"; Detalle = "Dashboard de notas recientes con fechas relativas y primeros puntos tratados (alias: recent-notes)"; Ejemplos = @("lnotes", "lnotes 5", "lnotes -Open 2") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "ngit"; Sintaxis = "ngit [repos|nombre] [-Repos] [-CurrentBranchOnly] [-AllAuthors]"; Detalle = "Inserta en la nota diaria los commits de hoy de todas las ramas locales (o solo la actual) del repo o de todos los proyectos (alias: note-git)"; Ejemplos = @("ngit", "ngit repos", "ngit -Repos", "ngit rsga", "ngit -CurrentBranchOnly") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "standup"; Sintaxis = "standup [-Clip]"; Detalle = "Genera resumen diario de Daily Standup (ayer, hoy, bloqueos) con opción de copiar al portapapeles (alias: note-standup)"; Ejemplos = @("standup", "standup -Clip") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "note-sql"; Sintaxis = "note-sql <nombre>"; Detalle = "Crea un script SQL fechado en Documentos\Notes\sql y lo abre en Neovim (alias: nsql)"; Ejemplos = @("note-sql fix_inventario") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "notes-sync"; Sintaxis = "notes-sync [mensaje]"; Detalle = "Registra y sincroniza todos los cambios de notas en el repo Git local (alias: nsync, note-save)"; Ejemplos = @("notes-sync", "notes-sync 'Reunión sprint'") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "todo"; Sintaxis = "todo [tarea] [-Start n] [-Stop] [-Status] [-Log n h [txt]] [-Note n [txt]] [-Check n] [-Skip n] [-Uncheck n] [-Open n] [-All] [-Today] [-Days n]"; Detalle = "Gestor interactivo de tareas y bitácora en notas (- [ ]) con cronómetro, imputación, sub-apuntes identados y filtros (alias: todos, tasks)"; Ejemplos = @("todo", "todo 'Revisar stock'", "todo -Start 2", "todo -Stop", "todo -Log 3 1.5 'Testing'", "todo -Note 6 'Dedicadas 3h a test'", "todo -Check 1", "todo -All -Days 3") }
        [PSCustomObject]@{ Categoria = "Notas & Diario"; Comando = "note-roll"; Sintaxis = "note-roll [-DaysAgo n] [-KeepUnmarked]"; Detalle = "Traspasa tareas pendientes (- [ ]) del día anterior al inicio de hoy con prefijo [> YYYYMMDD] y las marca como [>] en el origen (alias: note-rollover, roll-todos)"; Ejemplos = @("note-roll", "note-roll -DaysAgo 2", "note-roll -KeepUnmarked") }

        # 1.6. Bluemine & Control de Horas
        [PSCustomObject]@{ Categoria = "Bluemine & Horas"; Comando = "bm"; Sintaxis = "bm [filtro/índice] [-Add n] [-Open] [-Time] [-All]"; Detalle = "Catálogo de tickets Bluemine: añadir a nota ('bm 1'), abrir ticket ('bm 1 -Open') o imputar en web ('bm 1 -Time') (alias: tickets, bluemine)"; Ejemplos = @("bm", "bm 'rendimiento'", "bm 3", "bm 1 -Open", "bm 1 -Time", "bm -Add 221074") }
        [PSCustomObject]@{ Categoria = "Bluemine & Horas"; Comando = "bm-sync"; Sintaxis = "bm-sync [ruta]"; Detalle = "Auto-detecta y copia la última exportación issues*.csv de Descargas a Notes\bluemine.csv (alias: sync-bm, bluemine-sync)"; Ejemplos = @("bm-sync") }
        [PSCustomObject]@{ Categoria = "Bluemine & Horas"; Comando = "tstart"; Sintaxis = "tstart [tarea/índice]"; Detalle = "Inicia cronómetro de imputación en vivo para una tarea o índice de todo (alias: task-start)"; Ejemplos = @("tstart", "tstart 2", "tstart 'Soporte Cinfa'") }
        [PSCustomObject]@{ Categoria = "Bluemine & Horas"; Comando = "tstop"; Sintaxis = "tstop [comentario]"; Detalle = "Detiene el cronómetro activo, calcula horas transcurridas y registra el apunte en la nota (alias: task-stop)"; Ejemplos = @("tstop", "tstop 'Resolución de bug'") }
        [PSCustomObject]@{ Categoria = "Bluemine & Horas"; Comando = "tstatus"; Sintaxis = "tstatus"; Detalle = "Muestra la tarea que se está cronometrando actualmente y el tiempo acumulado (alias: task-status)"; Ejemplos = @("tstatus") }
        [PSCustomObject]@{ Categoria = "Bluemine & Horas"; Comando = "hours"; Sintaxis = "hours [-Fill] [-Step] [-Open] [-Clip] [-Days n]"; Detalle = "Control de jornada (8,5h L-J, 6h V) con barra de progreso, auto-balanceo (-Fill) y asistente web paso a paso (-Step) (alias: timesheet, imputar)"; Ejemplos = @("hours", "hours -Fill", "hours -Step", "hours -Open", "hours -Clip", "hours 5") }

        # 2. Archivos & Búsqueda
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "v"; Sintaxis = "v [ruta] | <cmd> | v"; Detalle = "Wrapper inteligente de Neovim: abre ficheros o vuelca salidas de pipeline a buffer temporal"; Ejemplos = @("v Program.cs", "gs | v", "q 'SELECT TOP 10 * FROM Articulos' | v") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "clip-diff"; Sintaxis = "clip-diff <archivo>"; Detalle = "Compara un archivo local contra el portapapeles en Neovim con vista dividida (alias: vdiff-clip)"; Ejemplos = @("clip-diff config.json", "clip-diff .\script.ps1", "vdiff-clip query.sql") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "watch"; Sintaxis = "watch <comando> [-n 2]"; Detalle = "Ejecuta un comando periódicamente refrescando la pantalla al estilo Unix watch (alias: watch-cmd)"; Ejemplos = @("watch 'git status -s'", "watch 'ports 8080' -n 5", "watch 'psfind node' 1") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "vrg"; Sintaxis = "vrg <patrón> [ruta]"; Detalle = "Busca texto con Ripgrep y abre resultados directamente en Neovim dentro de la lista Quickfix (:copen)"; Ejemplos = @("vrg 'Get-ActiveSql'", "vrg 'kill-port' src/") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "touch"; Sintaxis = "touch <archivo...>"; Detalle = "Crea archivos vacíos o actualiza su fecha de modificación al estilo Unix (crea carpetas si faltan)"; Ejemplos = @("touch nuevo.sql", "touch test1.cs test2.cs") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "rmrf"; Sintaxis = "rmrf [carpetas...] [-Find ...] [-f]"; Detalle = "Eliminación ultrarrápida protegida por lista blanca (restringido a Documentos\Proyectos y Scratch) (alias: rm-dir, purge-dir)"; Ejemplos = @("rmrf node_modules", "rmrf bin obj dist", "rmrf -Find node_modules", "rmrf -Find bin, obj", "rmrf -Force") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "ff"; Sintaxis = "ff <patrón> [ruta]"; Detalle = "Búsqueda recursiva ultrarrápida de archivos por nombre usando Ripgrep o fallback nativo"; Ejemplos = @("ff 'Controller'", "ff '*.sql' database/") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "which"; Sintaxis = "which <comando>"; Detalle = "Muestra la ruta absoluta, tipo (Cmdlet, Alias, App) y versión de cualquier comando ejecutable"; Ejemplos = @("which nvim", "which git", "which q") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "head"; Sintaxis = "head <archivo> [-n 10]"; Detalle = "Muestra las primeras N líneas de un archivo o flujo de datos sin cargarlo todo en memoria"; Ejemplos = @("head error.log", "head error.log -n 25") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "tail"; Sintaxis = "tail <archivo> [-n 10]"; Detalle = "Muestra las últimas N líneas de un archivo o log (útil para inspeccionar errores recientes)"; Ejemplos = @("tail error.log", "tail error.log -n 50") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "extract"; Sintaxis = "extract <archivo> [dest]"; Detalle = "Descomprime automáticamente archivos (.zip, .tar.gz, .7z, .rar) usando 7z, tar o Expand-Archive"; Ejemplos = @("extract release.zip", "extract backup.7z ./salida") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "cb"; Sintaxis = "cb [texto] | <cmd> | cb"; Detalle = "Copia texto o cualquier objeto de la consola directamente al portapapeles de Windows"; Ejemplos = @("cb 'Texto a copiar'", "Get-Location | cb") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "fe"; Sintaxis = "fe [ruta]"; Detalle = "Búsqueda difusa interactiva de archivos con fzf y apertura directa en Neovim (alias: vf)"; Ejemplos = @("fe", "fe src/", "vf") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "fcd"; Sintaxis = "fcd [ruta]"; Detalle = "Búsqueda difusa interactiva de carpetas con fzf y navegación (cd) automática"; Ejemplos = @("fcd", "fcd C:\Proyectos") }
        [PSCustomObject]@{ Categoria = "Archivos & Búsqueda"; Comando = "fhist"; Sintaxis = "fhist"; Detalle = "Búsqueda difusa interactiva en el historial de comandos de PowerShell con fzf"; Ejemplos = @("fhist") }

        # 3. Git & Lazygit
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "lg"; Sintaxis = "lg"; Detalle = "Lanza la interfaz de terminal interactiva (TUI) de Lazygit en el repositorio actual"; Ejemplos = @("lg") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "repos"; Sintaxis = "repos [-f] [índice|nombre] [-i] [-v|-o|-Code]"; Detalle = "Dashboard Git en vivo con salto rápido o selector difuso interactivo -i (alias: repo-status, proj)"; Ejemplos = @("repos", "repos -i", "repos 1", "repos backend -v") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "fco"; Sintaxis = "fco"; Detalle = "Selector difuso interactivo de ramas Git con fzf para checkout inmediato (alias: fbr)"; Ejemplos = @("fco", "fbr") }
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
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "glog"; Sintaxis = "glog [n] [args]"; Detalle = "Historial gráfico compacto y coloreado (por defecto 10 commits o 'glog 50')"; Ejemplos = @("glog", "glog 25", "glog 50 --all", "glog 20 --stat") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gundo"; Sintaxis = "gundo"; Detalle = "Deshace el último commit conservando todos los cambios preparados (staged) en el árbol de trabajo"; Ejemplos = @("gundo") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gwip"; Sintaxis = "gwip [mensaje]"; Detalle = "Guarda todo el trabajo en curso en un commit temporal rápido para poder cambiar de rama al vuelo"; Ejemplos = @("gwip", "gwip 'trabajando en auth'") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gunwip"; Sintaxis = "gunwip"; Detalle = "Restaura el commit temporal creado previamente con gwip y devuelve los cambios al árbol de trabajo"; Ejemplos = @("gunwip") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gclean"; Sintaxis = "gclean [-Force]"; Detalle = "Poda referencias remotas (fetch -p) y elimina de forma segura ramas locales ya borradas en el remoto"; Ejemplos = @("gclean", "gclean -Force") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gme"; Sintaxis = "gme"; Detalle = "Lista ramas remotas donde los últimos commits pertenecen al usuario actual"; Ejemplos = @("gme") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gss"; Sintaxis = "gss [mensaje]"; Detalle = "Guarda cambios en el stash con timestamp y rama activa (incluye archivos sin rastrear)"; Ejemplos = @("gss", "gss 'refactor conexion'") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gsl"; Sintaxis = "gsl"; Detalle = "Lista los stashes guardados con fechas relativas y colores legibles"; Ejemplos = @("gsl") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gsp"; Sintaxis = "gsp [índice]"; Detalle = "Aplica y retira el stash indicado (por defecto el último stash@{0})"; Ejemplos = @("gsp", "gsp 1") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "vmod"; Sintaxis = "vmod [-l] [-Splits]"; Detalle = "Muestra cambios coloreados y los abre en Neovim en pestañas con Quickfix (alias: vdiff)"; Ejemplos = @("vmod", "vmod -List", "vmod -Splits") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "vd"; Sintaxis = "vd [archivo]"; Detalle = "Abre el diff de un archivo en Neovim con vista dividida en paralelo (:diffsplit)"; Ejemplos = @("vd Program.cs", "vd") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gcompare"; Sintaxis = "gcompare [rama] [-Fetch] [-Stat]"; Detalle = "Compara la rama actual contra develop/main mostrando commits por delante (ahead), por detrás (behind) y cambios (alias: gcomp, branch-diff)"; Ejemplos = @("gcompare", "gcompare develop", "gcompare main", "gcompare -Stat") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gconflict"; Sintaxis = "gconflict [-List]"; Detalle = "Detecta archivos con conflictos de merge/rebase y los abre en Neovim con Quickfix en el primer conflicto (alias: vconflict, conflicts)"; Ejemplos = @("gconflict", "gconflict -List", "vconflict") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gshow"; Sintaxis = "gshow [commit] [-Stat] [-Files] [-v]"; Detalle = "Inspecciona los cambios de un commit con diff coloreado, selector interactivo fzf o en Neovim (alias: git-show)"; Ejemplos = @("gshow", "gshow 447686c", "gshow HEAD~1 -Stat", "gshow ae887bf -v") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "vshow"; Sintaxis = "vshow [commit]"; Detalle = "Abre el diff completo de un commit directamente en Neovim con resaltado de sintaxis (alias: gshow -v)"; Ejemplos = @("vshow", "vshow 447686c", "vshow HEAD~1") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "gfind"; Sintaxis = "gfind [ticket/texto] [-Code] [-Stat] [-v]"; Detalle = "Busca commits en todo el historial y ramas por ticket, mensaje o código diff (alias: gsearch, git-find)"; Ejemplos = @("gfind 181865", "gfind 'RECEPCIONES'", "gfind 181865 -Stat", "gfind 'NumSerie' -Code", "gfind 181865 -v") }
        [PSCustomObject]@{ Categoria = "Git & Lazygit"; Comando = "agy-review-pr"; Sintaxis = "agy-review-pr <rama>"; Detalle = "Audita y analiza una PR con Antigravity comparando contra develop sin cambiar de rama (alias: agy-pr-review)"; Ejemplos = @("agy-review-pr feature/login", "agy-pr-review bugfix/320 main -Print") }

        # 4. Sistema & Red
        [PSCustomObject]@{ Categoria = "Sistema & Red"; Comando = "ports"; Sintaxis = "ports [filtro]"; Detalle = "Muestra todos los puertos TCP en escucha con su PID y nombre de proceso (alias: listening)"; Ejemplos = @("ports", "ports 4200", "ports sql") }
        [PSCustomObject]@{ Categoria = "Sistema & Red"; Comando = "kill-port"; Sintaxis = "kill-port <puerto...>"; Detalle = "Finaliza los procesos que bloquean uno o varios puertos TCP (alias: kp)"; Ejemplos = @("kp 4200", "kp 5000, 7000") }
        [PSCustomObject]@{ Categoria = "Sistema & Red"; Comando = "psfind"; Sintaxis = "psfind <nombre>"; Detalle = "Busca procesos en ejecución mostrando PID, memoria en MB y consumo de CPU (alias: psgrep)"; Ejemplos = @("psfind node", "psfind sql", "psfind dotnet") }
        [PSCustomObject]@{ Categoria = "Sistema & Red"; Comando = "myip"; Sintaxis = "myip"; Detalle = "Muestra la dirección IP local de la tarjeta de red activa y la IP pública externa"; Ejemplos = @("myip") }
        [PSCustomObject]@{ Categoria = "Sistema & Red"; Comando = "sysinfo"; Sintaxis = "sysinfo"; Detalle = "Resumen de salud del equipo: uptime de Windows, uso de memoria RAM y espacio libre en discos"; Ejemplos = @("sysinfo") }
        [PSCustomObject]@{ Categoria = "Sistema & Red"; Comando = "wiztree"; Sintaxis = "wiztree [ruta/disco]"; Detalle = "Analizador ultrarrápido de espacio en disco vía NTFS MFT con mapa visual de bloques"; Ejemplos = @("wiztree", "wiztree C:", "wiztree .") }
        [PSCustomObject]@{ Categoria = "Sistema & Red"; Comando = "dust"; Sintaxis = "dust [ruta] [-d n] [-n n]"; Detalle = "Árbol gráfico en terminal con barras de consumo de espacio en disco en tiempo real"; Ejemplos = @("dust", "dust -d 2", "dust -n 15", "dust C:\Users") }
        [PSCustomObject]@{ Categoria = "Sistema & Red"; Comando = "btop"; Sintaxis = "btop"; Detalle = "Monitor TUI de recursos en tiempo real (CPU, RAM, discos, red y procesos interactivos)"; Ejemplos = @("btop") }

        # 5. SQL Server Toolkit
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "qenv"; Sintaxis = "qenv [perfil]"; Detalle = "Muestra o activa los entornos/conexiones de sql-connections.json (alias: qprofiles, qconns)"; Ejemplos = @("qenv", "qenv pre", "qenv local") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "sql-ping"; Sintaxis = "sql-ping [perfil]"; Detalle = "Diagnóstico de conectividad, versión y latencia de todos los servidores de sql-connections.json (alias: qping)"; Ejemplos = @("sql-ping", "qping", "qping local") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "q"; Sintaxis = "q <query/.sql> [switches]"; Detalle = "Motor ultrarrápido ADO.NET (switches: -Grid, -Clip, -Csv, -Json, -DryRun, -Timeout N)"; Ejemplos = @("q 'SELECT TOP 10 * FROM Articulos'", "q ./cambios.sql -DryRun", "q 'SELECT * FROM Clientes' -Grid") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "qconnect"; Sintaxis = "qconnect [perfil/srv] [bd]"; Detalle = "Abre una conexión persistente reutilizable de alto rendimiento (soporta perfiles de sql-connections.json)"; Ejemplos = @("qconnect", "qconnect pre", "qconnect 'localhost' 'MiBaseDatos'") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "qdisc"; Sintaxis = "qdisc"; Detalle = "Cierra la sesión persistente activa y vuelve a conexiones transitorias (alias: qdisconnect)"; Ejemplos = @("qdisc") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "use"; Sintaxis = "use <BaseDatos>"; Detalle = "Cambia la base de datos activa al vuelo con autocompletado y refresco de caché"; Ejemplos = @("use MiBaseDatos", "use MiBaseDatos_DEV") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "dbs"; Sintaxis = "dbs [-Grid] [-Clip]"; Detalle = "Lista todas las bases de datos de la instancia SQL actual con tamaño en MB y estado (alias: show-dbs)"; Ejemplos = @("dbs", "dbs -Grid") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "tables"; Sintaxis = "tables [filtro]"; Detalle = "Lista todas las tablas de la BD activa con su esquema y recuento exacto de filas (sin scan)"; Ejemplos = @("tables", "tables Articulos", "tables -Grid") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "views"; Sintaxis = "views [filtro]"; Detalle = "Lista todas las vistas de la BD activa con su fecha de creación y última modificación"; Ejemplos = @("views", "views vStock") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "top"; Sintaxis = "top <tabla> [n]"; Detalle = "Consulta rápida de las primeras N filas (por defecto 20) con soporte -Grid, -Clip, -Json"; Ejemplos = @("top Articulos", "top Articulos 50 -Grid", "top Clientes 10 -Clip") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "desc"; Sintaxis = "desc <tabla>"; Detalle = "Describe columnas, tipos de datos, nulabilidad y defaults de una tabla o vista"; Ejemplos = @("desc Articulos", "desc dbo.Clientes -Grid") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "count"; Sintaxis = "count <tabla>"; Detalle = "Recuento ultrarrápido de filas en 0 ms usando particiones DMVs (sys.dm_db_partition_stats)"; Ejemplos = @("count Articulos", "count MovimientosStock") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "find-table"; Sintaxis = "find-table <patrón>"; Detalle = "Busca tablas y vistas por coincidencia de texto en el nombre"; Ejemplos = @("find-table Stock", "find-table Pedido -Grid") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "find-col"; Sintaxis = "find-col <columna>"; Detalle = "Busca en qué tablas y vistas existe una columna dada en toda la base de datos"; Ejemplos = @("find-col IdArticulo", "find-col FechaCreacion") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "find-code"; Sintaxis = "find-code <patrón>"; Detalle = "Busca texto dentro del DDL de SPs, Vistas, Funciones y Triggers (alias: find-sp, grep-sql)"; Ejemplos = @("find-code 'usp_Calcular'", "find-sp 'ActualizarStock' -Grid") }
        [PSCustomObject]@{ Categoria = "SQL Server"; Comando = "who"; Sintaxis = "who [-Grid] [-Clip]"; Detalle = "Monitor en tiempo real de sesiones activas de usuario, bloqueos (blocking) y consultas (alias: locks, sql-who)"; Ejemplos = @("who", "locks", "who -Grid") }
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
        [PSCustomObject]@{ Categoria = "Consola & Atajos"; Comando = "PredictiveIntelliSense"; Sintaxis = "→  |  Tab  |  F2"; Detalle = "Autocompletado predictivo (PSReadLine): acepta sugerencia de historial con flecha derecha y conmuta vista con F2"; Ejemplos = @("Escribe comando y pulsa → para autocompletar", "Pulsa F2 para conmutar vista en línea / menú desplegable") }
        [PSCustomObject]@{ Categoria = "Consola & Atajos"; Comando = "KillWord"; Sintaxis = "Ctrl + Backspace"; Detalle = "Elimina la palabra completa anterior en la línea de comandos de forma rápida"; Ejemplos = @("Pulsa Ctrl+Backspace para borrar una palabra") }
        [PSCustomObject]@{ Categoria = "Consola & Atajos"; Comando = "SqlTableCompletion"; Sintaxis = "Ctrl + Espacio"; Detalle = "Autocompletado predictivo inteligente de nombres de tablas y vistas de SQL Server en la consola"; Ejemplos = @("Escribe 'SELECT * FROM Art' y pulsa Ctrl+Espacio") }
        [PSCustomObject]@{ Categoria = "Consola & Atajos"; Comando = "ViEditVisually"; Sintaxis = "Ctrl+X, Ctrl+E"; Detalle = "Abre el comando que estás escribiendo en una ventana de Neovim para edición multilínea compleja"; Ejemplos = @("Pulsa Ctrl+X seguido de Ctrl+E en el prompt") }

        # 7. Asistente IA (Antigravity CLI / agy)
        [PSCustomObject]@{ Categoria = "Asistente IA"; Comando = "??"; Sintaxis = "?? <pregunta en lenguaje natural>"; Detalle = "Traduce lenguaje natural a comando de PowerShell 5.1 con menú para ejecutar o copiar (alias: ask-cmd)"; Ejemplos = @("?? como listar archivos de mas de 100MB", "?? procesos con mas CPU") }
        [PSCustomObject]@{ Categoria = "Asistente IA"; Comando = "explain-error"; Sintaxis = "explain-error"; Detalle = "Analiza el último error de la sesión (`$Error[0]) con IA y explica causa y solución concisa (alias: why-error, perror)"; Ejemplos = @("explain-error", "why-error") }
        [PSCustomObject]@{ Categoria = "Asistente IA"; Comando = "gai"; Sintaxis = "gai"; Detalle = "Analiza los cambios en stage (`git diff --staged) y genera un mensaje de commit convencional interactivo"; Ejemplos = @("gai") }
        [PSCustomObject]@{ Categoria = "Asistente IA"; Comando = "agy-history"; Sintaxis = "agy-history [n] [filtro]"; Detalle = "Lista el historial de conversaciones recientes de Antigravity con su índice y asunto (alias: achats, agy-chats)"; Ejemplos = @("agy-history", "achats", "agy-history 15") }
        [PSCustomObject]@{ Categoria = "Asistente IA"; Comando = "agy-resume"; Sintaxis = "agy-resume [n/ID]"; Detalle = "Reanuda una conversación de Antigravity por índice (1, 2...), ID o selector interactivo fzf (alias: aresume, agy-c)"; Ejemplos = @("agy-resume", "aresume 1", "aresume 8f79c406") }

        # 8. Codex CLI & VS Code
        [PSCustomObject]@{ Categoria = "Codex CLI & VS Code"; Comando = "codex"; Sintaxis = "codex / cx [prompt]"; Detalle = "Invoca el CLI oficial de OpenAI Codex en modo interactivo o con argumentos (alias: cx)"; Ejemplos = @("codex", "cx", "cx 'Refactoriza este script'", "cx --version") }
        [PSCustomObject]@{ Categoria = "Codex CLI & VS Code"; Comando = "cxchats"; Sintaxis = "cxchats [n] [filtro]"; Detalle = "Historial cronológico de hilos de Codex compartidos con VS Code (alias: codex-history, cx-chats)"; Ejemplos = @("cxchats", "cxchats 15", "cxchats 10 'Adobe'") }
        [PSCustomObject]@{ Categoria = "Codex CLI & VS Code"; Comando = "cxresume"; Sintaxis = "cxresume [n/ID]"; Detalle = "Reanuda un hilo de VS Code o CLI por índice [1], UUID o menú difuso interactivo fzf (alias: codex-resume, cx-resume, codex-c)"; Ejemplos = @("cxresume", "cxresume 1", "cxresume 01a0fc19") }
        [PSCustomObject]@{ Categoria = "Codex CLI & VS Code"; Comando = "cxreview"; Sintaxis = "cxreview"; Detalle = "Ejecuta una revisión automatizada de código con Codex contra los cambios del repo Git (alias: codex-review, cx-review)"; Ejemplos = @("cxreview", "codex-review") }
        [PSCustomObject]@{ Categoria = "Codex CLI & VS Code"; Comando = "cxapply"; Sintaxis = "cxapply"; Detalle = "Aplica el último diff o parche producido por el agente de Codex al árbol de trabajo de Git (alias: codex-apply, cx-apply)"; Ejemplos = @("cxapply", "codex-apply") }
        [PSCustomObject]@{ Categoria = "Codex CLI & VS Code"; Comando = "cxexec"; Sintaxis = "cxexec <prompt> [-Json]"; Detalle = "Ejecuta tareas en segundo plano en modo no interactivo con Codex (alias: codex-exec, cx-exec)"; Ejemplos = @("cxexec 'Genera un script de backup'", "cxexec -Json 'Analiza este JSON'") }
        [PSCustomObject]@{ Categoria = "Codex CLI & VS Code"; Comando = "cxdoctor"; Sintaxis = "cxdoctor"; Detalle = "Diagnóstico exhaustivo de salud, autenticación, base de datos y sandbox de Codex (alias: codex-doctor)"; Ejemplos = @("cxdoctor", "codex-doctor") }
        [PSCustomObject]@{ Categoria = "Codex CLI & VS Code"; Comando = "cxradar"; Sintaxis = "cxradar [n] [-Full] [-Json]"; Detalle = "Monitor y digest en tiempo real de agentes activos de Codex en VS Code/CLI (alias: cxstatus, codex-radar)"; Ejemplos = @("cxradar", "cxradar 5", "cxradar -Full", "cxradar -Json") }
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
 


