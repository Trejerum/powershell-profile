# PowerShell Profile & Centro de Mando Developer

Configuración avanzada para **PowerShell 7 (`pwsh`)** y **Windows PowerShell 5.1** (`Microsoft.PowerShell_profile.ps1`). Diseñada con arquitectura híbrida y compatibilidad dual total (ver [Guía de Migración y Arquitectura Dual](docs/powershell-7-migration.md)). Convierte la consola en un centro de mando integral que aúna la velocidad del paso de objetos en .NET moderno (.NET 9) con la agilidad de los flujos de trabajo Unix, integrando **Git**, **Lazygit**, **Neovim**, **Ripgrep**, **SQL Server** y herramientas de diagnóstico de sistema y red.

---

## 🚀 Requisitos y Herramientas del Entorno

El perfil detecta automáticamente las herramientas instaladas y activa sus aceleradores:

| Herramienta | Utilidad en el Perfil |
| :--- | :--- |
| **`posh-git`** | Estado del repo en el prompt (`[rama +A ~M -D !U]`) y autocompletado nativo con `<Tab>`. |
| **`PSReadLine 2.2+`** | Autocompletado predictivo inteligente (ghost-text desde historial), menú <kbd>F2</kbd> y edición visual con Neovim. |
| **`fzf`** *(Fuzzy Finder)* | Búsqueda difusa interactiva de archivos (`fe`/`vf`), carpetas (`fcd`), historial (`fhist`), ramas (`fco`) y repos (`repos -i`). |
| **`fd`** *(Find Directory/File)* | Búsqueda de archivos y directorios ultrarrápida que alimenta el motor de `fzf` (`fe`/`fcd`). |
| **`bat`** *(Cat con syntax highlighting)* | Previsualizador con resaltado de sintaxis y numeración para `fzf` (`fe`) y lectura en consola. |
| **`Neovim` (`nvim`)** | Editor principal de Git, visor de diffs, visor de tuberías (`v`), quickfix de Ripgrep (`vrg`) y scratchpad SQL (`vsql`). |
| **`Ripgrep` (`rg`)** | Búsqueda ultrarrápida de archivos (`ff`) y de texto con Quickfix (`vrg`). |
| **`Lazygit` (`lg`)** | Interfaz TUI completa para Git directamente desde la terminal. |
| **`7-Zip` (`7z`)** | Descompresor multiformato unificado (`extract`). |

---

## 📦 Instalación y Puesta a Punto (`install.ps1`)

El perfil reside en tu directorio local de **dotfiles** (`$HOME\.dotfiles\powershell`) para garantizar máximo rendimiento de I/O en disco SSD y aislar tu repositorio Git y módulos de carpetas sincronizadas en la nube (**OneDrive**).

Para clonar y poner a punto el entorno en **cualquier ordenador nuevo**:

```powershell
# 1. Clonar el repositorio en la ruta estándar de dotfiles
git clone https://github.com/Trejerum/powershell-profile.git "$HOME\.dotfiles\powershell"

# 2. Entrar en el directorio y ejecutar el aprovisionador
cd "$HOME\.dotfiles\powershell"
.\install.ps1

# 3. Recargar la consola para activar el perfil
. $PROFILE
```

El script [`install.ps1`](install.ps1) se encarga de todo automáticamente:
- **Configura automáticamente la Unión NTFS (*Directory Junction*) en `$PROFILE`:** Detecta la ubicación oficial de tu perfil en Windows (esté o no redirigido por OneDrive/políticas corporativas) y genera un enlace de sistema de archivos a nivel de kernel hacia `~/.dotfiles/powershell`, respaldando cualquier perfil existente en `.bak`.
- Configura TLS 1.2 y el proveedor NuGet.
- Instala o actualiza los módulos necesarios (`posh-git`, `PSReadLine 2.2+`).
- Inicializa tu `sql-connections.json` a partir de [`sql-connections.example.json`](sql-connections.example.json) si aún no existe.
- Comprueba la disponibilidad de herramientas clave (`nvim`, `rg`, `lg`, `fzf`, `7z`), sugiriendo comandos de instalación rápida con `winget`.

---

## 📂 Arquitectura Modular (`profile.d/`)

El perfil utiliza un cargador raíz ultraligero (`Microsoft.PowerShell_profile.ps1`) que importa de forma ordenada y aislada los módulos temáticos ubicados en el directorio `profile.d/`. Esto garantiza que un fallo puntual nunca bloquee la consola y facilita enormemente el mantenimiento y control de versiones en Git:

| Archivo | Área | Descripción |
| :--- | :--- | :--- |
| **`00-env.ps1`** | **Entorno & Consola** | Codificación `UTF-8` global. Neovim como editor predeterminado (`$env:EDITOR`). Integración con `PSReadLine 2.2+`: autocompletado predictivo (ghost-text), atajos de palabras (<kbd>Ctrl+Backspace</kbd>), conmutación <kbd>F2</kbd>, búsqueda contextual (<kbd>↑</kbd>/<kbd>↓</kbd>) y edición visual (<kbd>Ctrl+X, Ctrl+E</kbd>). |
| **`10-navigation.ps1`** | **Navegación Ágil** | Subida de niveles (`..`, `...`, `....`), creación y entrada (`mkcd`), sandboxes desechables (`scratch`/`sandbox`), explorador (`open`/`o`), recarga (`reload`/`rel`) y edición de perfil (`ep`, `en`, `ep local`). |
| **`15-notes.ps1`** | **Notas & Diario** | Gestión de notas diarias en Neovim (`note`/`today`), captura rápida desde consola, buscador histórico (`snote`/`vnote`), dashboard (`lnotes`), scratchpad SQL (`note-sql`) y versionado Git (`notes-sync`). |
| **`20-git.ps1`** | **Git & Lazygit** | Hub universal de proyectos (`repos`, `proj`) con modo interactivo `fzf` (`-i`), checkout difuso (`fco`/`fbr`), commits temporales (`gwip`/`gunwip`), poda de ramas muertas (`gclean`), alias `g`, TUI (`lg`), commits rápidos (`gcom`), checkout/switch (`gco`, `gcob`), ramas ordenadas (`gb`), deshacer (`gundo`), diff split (`vd`), visor de modificados (`vmod`), stash (`gss`, `gsl`, `gsp`) y auditorías con Antigravity (`agy-review-pr`). |
| **`30-sql.ps1`** | **SQL Server Toolkit** | Motor ADO.NET (`q`), diagnóstico de conectividad multi-perfil (`sql-ping`/`qping`), sesión persistente (`qconnect`, `qdisc`, `use`), exploración (`dbs`, `tables`, `views`, `top`, `desc`, `count`), búsqueda (`find-table`, `find-col`, `find-code`), monitor (`who`, `see`, `see-idx`), exportación (`q2excel`, `qclip`, `qfmt`), scratchpad (`vsql`) y autocompletado en consola (<kbd>Ctrl</kbd>+<kbd>Espacio</kbd>). |
| **`40-utils.ps1`** | **Utilidades Generales** | Búsqueda difusa interactiva con `fzf` (`fe`/`vf`, `fcd`, `fhist`), benchmark del perfil (`profile-bench`/`pbench`), archivos (`touch`, `ff`, `head`, `tail`, `extract`), diagnóstico (`ports`, `kill-port`/`kp`, `psfind`, `myip`, `sysinfo`), portapapeles (`cb`), integración Neovim (`v`, `vrg`) y buscador de comandos (`hist`). |
| **`50-help.ps1`** | **Centro de Ayuda** | Guía de comandos agrupada por áreas (`phelp`, `phelp git`, `phelp sql`, `phelp fzf`) y fichas técnicas detalladas con ejemplos (`phelp <comando>`). |
| **`99-prompt.ps1`** | **Prompt Personalizado** | Muestra el prefijo de versión activa (`PS7`/`PS5`), la ruta activa, el estado en vivo de Git vía `posh-git` y el badge de conexión persistente a SQL Server (`[BD ⚡]`). |

---

## 🧭 1. Navegación Ágil y Gestión de Directorios

- **`..` / `...` / `....`**: Sube 1, 2 o 3 niveles en el árbol de directorios sin teclear `cd ..\..`.
- **`mkcd <carpeta>`**: Crea un directorio (incluyendo carpetas intermedias si faltan) y entra en él inmediatamente.
- **`rmrf <carpetas...> [-Find ...] [-f]` (alias `rm-dir`, `purge-dir`)**: Eliminación ultrarrápida y segura de directorios en Windows (10x más rápido que `Remove-Item` vía `cmd /c rmdir /s /q` con fallback a Robocopy para rutas >260 caracteres). **Protegido por lista blanca**: estrictamente limitado a subdirectorios dentro de `Documentos\Proyectos` y `Scratch` para evitar accidentes. Calcula el espacio liberado, soporta comodines/múltiples carpetas, búsqueda recursiva de artefactos (`-Find node_modules`, `-Find bin, obj`) y selector interactivo `fzf`.
- **`scratch [nombre] [-List] [-Clean n] [-v]` (alias `sandbox`)**: Gestor de entornos desechables fechados en `$HOME\Documentos\Scratch\yyyy-MM-dd` para pruebas rápidas y clonado provisional:
  - `scratch`: Crea y navega a la carpeta de hoy.
  - `scratch test-api`: Crea un subentorno `test-api` dentro de la carpeta de hoy.
  - `scratch -List` (o `-l`): Lista los sandboxes existentes, fechas de modificación y espacio ocupado en disco.
  - `scratch -Clean 7`: Elimina automáticamente todos los entornos temporales con más de 7 días.
  - `scratch -Nvim` (o `-v`): Entra y abre Neovim inmediatamente.
- **`profile-bench` (alias `pbench`, `profile-time`)**: Diagnóstico de rendimiento del perfil. Mide milisegundo a milisegundo el tiempo de carga de cada módulo (`profile.d/*.ps1`) y el arranque completo en frío de PowerShell.
- **`open [ruta]` (alias `o`)**: Abre el Explorador de Windows en la carpeta actual o en la ruta especificada.
- **`proj [nombre]` (alias de `repos`)**: Salto dinámico a cualquier subproyecto dentro de `Documentos\Proyectos` con autocompletado <kbd>Tab</kbd>. Si se ejecuta sin parámetros, muestra el dashboard de proyectos.
- **`reload` (alias `rel`, `rprof`, `reload-profile`)**: Recarga el perfil en la consola actual con confirmación visual.
- **Atajos de entorno y configuración:**
  - `profile` (alias `cdprofile`, `dotfiles`): Salta al repositorio de dotfiles de PowerShell (`~/.dotfiles/powershell`).
  - `notes [args]`: Navega a `$HOME\Documentos\Notes` (o ejecuta captura/apertura si recibe argumentos).
  - `ep [modulo]` (alias `edit-profile`): Abre `Microsoft.PowerShell_profile.ps1`, un módulo específico (ej. `ep notes`, `ep sql`, `ep git`, `ep utils`) o tu configuración local personal (`ep local`) en Neovim.
  - `en` (alias `edit-nvim`) / `nvim-config` (alias `cdnvim`): Abre o navega a la configuración de Neovim (`~/.dotfiles/nvim`).

---

## 📝 1.5. Notas Personales & Diario Developer (`$HOME\Documentos\Notes`)

El perfil automatiza y potencia tu flujo de notas diarias con Neovim, captura rápida sin cambio de contexto y sincronización Git:

- **`note` (alias `today`, `diario`)**:
  - `note`: Abre la nota de hoy (`YYYYMMDD.md`) en Neovim ubicada al final del archivo. Si no existe, la crea automáticamente con la cabecera `# YYYYMMDD`.
  - `note "texto a apuntar"`: **Captura rápida instantánea** sin abrir Neovim. Añade `- [HH:mm] <texto>` al final de la nota del día sin interrumpir tu tarea.
  - `<comando> | note`: Soporta tubería directa (ej. `q "SELECT..." | note` o `"Error SP..." | note`).
  - `note yesterday` (o `note -1`, `note ayer`): Abre la nota de ayer (o del viernes si hoy es lunes).
  - `note last` (o `note ultimo`): Abre la última nota diaria existente.
  - `note <número>` (ej. `note 1`, `note 2`): Abre la nota correspondiente según el listado de `lnotes`.
  - `note <YYYYMMDD>` (ej. `note 20261001`): Abre la nota de una fecha concreta.
- **`snote <patrón>` (alias `find-note`)**: Busca texto en todas las notas históricas con Ripgrep resaltando en color las coincidencias, líneas y archivos.
- **`vnote <patrón>`**: Busca texto en las notas con Ripgrep y abre todos los resultados directamente en Neovim dentro de la lista **Quickfix** (`:copen`) para navegar entre notas con `<Enter>`.
- **`lnotes [n] [-Open n]` (alias `recent-notes`)**: Muestra un dashboard con las últimas N notas diarias, tiempo relativo (*"Hoy"*, *"Ayer"*, *"Hace 4 días"*), tamaño y las primeras líneas tratadas. Permite abrir directamente una nota con `-Open <n>` o `note <n>`.
- **`note-sql <nombre>` (alias `nsql`)**: Crea un script SQL fechado (`YYYYMMDD_nombre.sql`) en `Documentos\Notes\sql\` con cabecera y plantilla, abriéndolo en Neovim.
- **`notes-sync [mensaje]` (alias `nsync`, `note-commit`, `note-save`)**: Añade todos los cambios de tus notas y crea un commit en el repositorio Git local de `Documentos\Notes`.
- **`todo` (alias `todos`, `tasks`)**:
  - `todo`: Escanea las notas de los últimos 7 días y muestra tus tareas pendientes (`- [ ]`) agrupadas por fecha con tiempo relativo y número de línea.
  - `todo "texto de la tarea"`: Añade una nueva tarea a la nota de hoy (`- [ ] [HH:mm] <tarea>`).
  - `todo -Today`: Muestra solo las tareas de la nota de hoy.
  - `todo -Done` / `todo -All`: Muestra también las tareas completadas (`- [x]`) en verde.
  - `todo -Open <n>`: Abre **Neovim directamente en la línea exacta** donde está la tarea indicada.
  - `todo -Check <n>`: Marca la tarea `[n]` como **completada** (`- [x]`) en el archivo markdown sin necesidad de abrir Neovim.
  - `todo -Uncheck <n>`: Desmarca la tarea `[n]` devolviéndola a pendiente (`- [ ]`).
- **`note-roll` (alias `note-rollover`, `roll-todos`)**:
  - Revisa la nota anterior (ayer o último día laboral) y **traspasa automáticamente a hoy las tareas no terminadas** bajo el encabezado `## Pendientes de YYYYMMDD`. Evita duplicados si se ejecuta más de una vez.
  - `note-roll -MarkMoved`: Marca las tareas en la nota origen como migradas (`- [>]`).

---

## 📄 2. Archivos, Búsqueda y Productividad Unix

- **`touch <archivo...>`**: Crea archivos vacíos (o actualiza su timestamp si ya existen) al estilo Unix. Si la ruta incluye carpetas que no existen, las crea automáticamente.
- **`ff <patrón> [ruta]`**: Búsqueda recursiva ultrarrápida de archivos por coincidencia de nombre usando `rg --files` (o fallback nativo .NET).
- **`which <comando>`**: Muestra la ruta absoluta, tipo de comando (Cmdlet, Alias, Application) y versión de cualquier ejecutable.
- **`head <archivo> [-n 10]`**: Muestra las primeras N líneas de un archivo o flujo sin cargarlo entero en memoria.
- **`tail <archivo> [-n 10]`**: Muestra las últimas N líneas de un archivo o fichero de log.
- **`extract <archivo> [destino]`**: Descompresor universal para `.zip`, `.tar.gz`, `.7z` o `.rar` utilizando `7z`, `tar` o `Expand-Archive`.
- **`cb [texto] | <comando> | cb`**: Copia texto o cualquier objeto de la consola directamente al portapapeles de Windows.
- **Búsqueda difusa interactiva con `fzf`:**
  - **`fe [ruta]` (alias `vf`)**: Búsqueda difusa interactiva de archivos con vista previa; pulsa <kbd>Enter</kbd> para abrirlo en Neovim.
  - **`fcd [ruta]`**: Búsqueda difusa interactiva de carpetas y navegación (`cd`) automática sin escribir rutas.
  - **`fhist`**: Búsqueda difusa interactiva en el historial de comandos de PowerShell; pulsa <kbd>Enter</kbd> para ejecutar el comando seleccionado.

---

## 🌿 3. Git & Lazygit Superpowers

- **`repos [índice|nombre]` (alias `repo-status`, `proj`)**: Hub universal de proyectos y dashboard interactivo de Git:
  - Escanea automáticamente los repositorios en `$global:ProjectsRoot` (por defecto `Documentos\Proyectos`, configurable vía `$env:PROJECTS_DIR`).
  - Muestra rama activa, cambios locales pendientes (`+staged`, `~mod`, `!new` o `Limpio`), estado de sincronización con origin (`Al día`, `↑ N pendiente(s)`, `↓ N por bajar`) y el último commit con fecha relativa.
  - **Salto instantáneo por número:** `repos 1`, `repos 2` (salta al número del listado).
  - **Salto por nombre con autocompletado <kbd>Tab</kbd>:** `repos <nombre>` (búsqueda inteligente con autocompletado nativo).
  - **Apertura directa:** `repos 1 -Nvim` (o `-v`), `repos 1 -Open` (o `-o`), `repos 1 -Code`.
  - **Refresco remoto:** `repos -f` (hace `git fetch` silencioso en los repositorios antes de evaluar para reflejar el estado de origin al instante).
  - **Selector interactivo con `fzf`:** `repos -i` (filtra y salta a cualquier proyecto con búsqueda difusa en vivo).
- **`fco` (alias `fbr`)**: Selector difuso interactivo de ramas locales y remotas con `fzf` para cambiar de rama al vuelo sin teclear su nombre. Si ejecutas `gco` sin argumentos, se activa automáticamente si `fzf` está presente.
- **`gwip [mensaje]`**: Guarda todo el trabajo en curso en un commit temporal rápido (`WIP: ... [skip ci]`) permitiendo cambiar de rama de inmediato sin perder nada.
- **`gunwip`**: Restaura el commit temporal creado previamente con `gwip`, devolviendo todos los archivos a cambios sin confirmar en el árbol de trabajo.
- **`gclean [-Force]`**: Sincroniza y poda referencias remotas (`git fetch -p`) y elimina de forma segura ramas locales cuyo upstream en el servidor remoto ya no existe (protege `main`/`master`/`develop`).
- **`gcom "<mensaje>"`**: Prepara todos los cambios (`git add -A`) y crea el commit en un solo paso rápido.
- **`gcob <nueva-rama>` (alias `gswc`)**: Crea una nueva rama y cambia a ella de inmediato (`git checkout -b` / `git switch -c`).
- **`gb`**: Lista las ramas locales ordenadas por fecha de último commit con indicador de tiempo relativo.
- **`gundo`**: Deshace el último commit manteniendo todos los cambios en el árbol de trabajo y preparados en *staged* (`git reset --soft HEAD~1`).
- **`vd [archivo]`**: Abre la comparación diff de Git de un archivo en Neovim con vista dividida en paralelo (`nvim -d`).
- **`vmod` (alias `vdiff`)**: Muestra en consola la lista coloreada de cambios (`[Modificado]`, `[Nuevo]`, `[Staged]`) y los abre en Neovim en pestañas individuales con la lista Quickfix (`:copen`) activa abajo.
  - `vmod -List` (o `-l`): Solo lista los cambios en consola sin abrir el editor.
  - `vmod -Splits`: Abre los archivos en divisiones verticales en lugar de pestañas.
- **Atajos clásicos:**
  - `g <args>`: Alias universal a `git` con soporte total de autocompletado en `posh-git`.
  - `gs`: `git status -sb`.
  - `ga`: `git add .`.
  - `gp` / `gf`: `git pull` / `git fetch`.
  - `gpush`: `git push`.
  - `gpsup` (alias `gpu`): `git push --set-upstream origin <rama_actual>`.
  - `gco <rama>`: `git checkout <rama>` con autocompletado inteligente de ramas (o selector difuso `fco` si se pulsa sin argumentos).
  - `glog [n]`: Historial compacto gráfico de los últimos 10 commits (o N commits si se indica número, ej. `glog 50`, `glog 25 --all`).
  - `gss [msg]` / `gsl` / `gsp [idx]`: Guardar, listar y aplicar stashes con timestamps y rama activa.
  - `agy-review-pr <rama> [base]` (alias `agy-pr-review`): Auditoría de Pull Requests con Antigravity sin saltar de rama.

---

## 🖥️ 4. Diagnóstico de Sistema, Red y Procesos

- **`ports [filtro]` (alias `listening`)**: Muestra todos los puertos TCP a la escucha en la máquina con su puerto, IP, PID y nombre del proceso asociado.
- **`kill-port <puerto...>` (alias `kp`)**: Busca y finaliza los procesos que retienen uno o varios puertos locales (ej. `kp 4200` o `kp 5000, 7000`).
- **`psfind <nombre>` (alias `psgrep`)**: Busca procesos en ejecución mostrando PID, memoria en MB y tiempo de CPU consumido.
- **`myip`**: Muestra la dirección IP local de las interfaces activas y consulta la IP pública externa.
- **`sysinfo`**: Muestra el tiempo de encendido (uptime) de Windows, uso de memoria RAM (usada/total/libre) y espacio libre en discos.

---

## 🗄️ 5. SQL Server Toolkit (ADO.NET)

Motor de alto rendimiento desacoplado de credenciales y entornos locales mediante un archivo de configuración JSON local y git-ignorado.

### Configuración Multientorno (`sql-connections.json`)
El perfil lee dinámicamente sus conexiones desde `sql-connections.json` en la raíz del perfil (ignorado por Git para máxima seguridad):
- **Plantilla versionada:** [`sql-connections.example.json`](sql-connections.example.json) sirve como modelo para configurar entornos locales, desarrollo, preproducción o remotos con autenticación integrada o SQL Auth:
```json
{
  "default": "local",
  "connections": {
    "local": {
      "server": "localhost\\SQLEXPRESS",
      "database": "MiBaseDatos",
      "integratedSecurity": true,
      "description": "Base de datos local de desarrollo"
    },
    "pre": {
      "server": "SRV-PRE\\SQL_SERVER",
      "database": "MiBaseDatos_PRE",
      "integratedSecurity": true,
      "description": "Entorno de preproducción"
    },
    "remote_sql": {
      "server": "10.0.0.50,1433",
      "database": "ERP_QA",
      "integratedSecurity": false,
      "user": "sa",
      "password": "Password123!",
      "description": "Servidor remoto con SQL Authentication"
    }
  }
}
```
Si `sql-connections.json` no existe en una máquina nueva, el perfil lo copia automáticamente desde la plantilla de ejemplo.

### Conexión, Entornos y Contexto
- **`qenv [perfil]` (alias `qprofiles`, `qconns`)**: Muestra la tabla de entornos configurados, servidor, base de datos, tipo de autenticación y cuál está activo/predeterminado. Al pasar un nombre (`qenv pre`), activa ese perfil de inmediato para todos los comandos del toolkit.
- **`sql-ping [perfil]` (alias `qping`)**: Diagnóstico de conectividad y latencia multi-perfil. Comprueba en paralelo o por servidor si cada base de datos está accesible, mide el tiempo de respuesta en milisegundos y muestra la versión exacta del motor SQL Server.
- **`qconnect [perfil|servidor] [bd]`**: Abre una conexión persistente reutilizable de alto rendimiento (soporta nombres de perfil de `sql-connections.json` o servidor/BD arbitrarios). Muestra el badge `[perfil:BD ⚡]` en el prompt interactivo.
- **`qdisc` (alias `qdisconnect`)**: Cierra la sesión persistente activa y vuelve al modo transitorio (sigue usando el perfil activo por defecto).
- **`use <BaseDatos>`**: Cambia la base de datos activa al vuelo con autocompletado y refresca la caché de tablas y vistas.
- **`dbs` (alias `show-dbs`)**: Lista todas las bases de datos de la instancia con su tamaño en MB, estado y modelo de recuperación.

### Exploración y Búsqueda
- **`tables [filtro]`**: Lista todas las tablas de la base de datos activa con recuento exacto de filas en 0 ms (vía DMVs de partición, sin `COUNT(*)` lento).
- **`views [filtro]`**: Lista todas las vistas con su esquema, fecha de creación y última modificación.
- **`top <tabla> [n]`**: Muestra rápidamente las primeras N filas (por defecto 20) de cualquier tabla o vista (soporta `-Grid`, `-Clip`, `-Json`).
- **`desc <tabla>`**: Describe columnas, tipos de datos, nulabilidad y valores por defecto con autocompletado.
- **`count <tabla>`**: Recuento instantáneo de filas usando particiones DMVs (`sys.dm_db_partition_stats`).
- **`find-table <patrón>`**: Busca tablas y vistas por coincidencia en el nombre.
- **`find-col <columna>`**: Encuentra en qué tablas y vistas existe una columna dada en toda la base de datos.
- **`find-code <patrón>` (alias `find-sp`, `grep-sql`)**: Busca texto o nombres de tablas dentro del DDL de SPs, Vistas, Funciones y Triggers.

### Monitorización y DDL
- **`who [-Grid]`**: Monitor de sesiones activas de usuario, bloqueos entre procesos (*blocking SPID*) y consultas en ejecución.
- **`see <objeto> [-Clip]`**: Extrae y muestra el código DDL de una vista, SP, función o trigger en consola.
- **`see-idx <tabla>`**: Inspecciona los índices definidos, tipo (Clustered/Nonclustered) y columnas clave.
- **`open-sql <objeto>`**: Extrae el DDL de un objeto y lo abre en Neovim listo para inspeccionar o editar.
- **`vsql`**: Abre un scratchpad SQL temporal en Neovim con contexto de la BD activa y pregunta si deseas ejecutarlo con `q` al guardar y salir (`:wq`).

### Ejecución y Exportación
- **`q <query/.sql>`**: Ejecuta consultas ultrarrápidas o scripts `.sql` con salvaguardas:
  - `-Grid`: Muestra los resultados en una ventana gráfica interactiva de `Out-GridView`.
  - `-Clip`: Copia los resultados tabulados al portapapeles listos para pegar en Excel (<kbd>Ctrl+V</kbd>).
  - `-Csv <ruta>`: Exporta directamente a archivo delimitado por punto y coma `;`.
  - `-Json`: Convierte los resultados a JSON formateado.
  - `-DryRun`: Envoltorio de simulación de cambios con `ROLLBACK TRANSACTION` automático.
  - `-Timeout <segundos>`: Configura el tiempo límite de ejecución (por defecto 120 s).
- **`qclip <query/.sql>`**: Ejecuta la consulta y envía directamente los resultados tabulados al portapapeles.
- **`q2excel <query/.sql>` (alias `qexcel`)**: Ejecuta una consulta SQL y abre el resultado directamente en Excel en formato español.
- **`qfmt <query> [-Clip]`**: Formatea e indenta una consulta SQL desordenada para mayor legibilidad.
- **`qlog [filtro] [-Last 20]`**: Consulta el historial persistente de sentencias SQL ejecutadas en `$HOME\.sql_history.tsv`.

---

## ⚡ 6. Integración con Neovim & Consola Interactiva
- **Autocompletado Predictivo Inteligente (`PSReadLine 2.2+`):**
  - Muestra sugerencias en texto fantasma (ghost-text) gris a partir de tu historial de comandos reales mientras escribes.
  - Acepta la sugerencia completa con <kbd>→</kbd> (flecha derecha) o con <kbd>Tab</kbd>.
  - Pulsa <kbd>F2</kbd> para conmutar al vuelo entre sugerencia en línea (*InlineView*) o menú de lista desplegable (*ListView*).
- **Atajos de edición acelerada:**
  - <kbd>Ctrl + Backspace</kbd>: Borra la palabra completa anterior rápidamente sin pararse en barras o símbolos molestos.
  - <kbd>Ctrl + Delete</kbd>: Borra la palabra completa siguiente.
- **`v [archivo]` o `<comando> | v`**: Wrapper inteligente. Abre archivos o captura la salida por tubería (`gs | v`, `q "SELECT..." | v`) en un buffer temporal de Neovim.
- **`vrg <patrón> [ruta]`**: Ejecuta Ripgrep y abre automáticamente Neovim cargando los resultados en la lista **Quickfix** (`:copen`), saltando al primer resultado.
- **<kbd>Ctrl+X, Ctrl+E</kbd>**: Edita la línea de comandos actual dentro de una ventana completa de Neovim y la devuelve al prompt lista para ejecutar.
- **<kbd>Ctrl + Espacio</kbd>**: Autocompletado predictivo inteligente de nombres de tablas y vistas de SQL Server en la consola.
- **Historial Contextual (<kbd>↑</kbd> / <kbd>↓</kbd>)**: Escribe un prefijo (ej. `git ` o `q `) y pulsa la flecha arriba para buscar únicamente comandos que coincidan con lo ya escrito.
- **`hist [filtro]`**: Búsqueda rápida por texto dentro del historial de la sesión de PowerShell.

---

## 💡 7. Sistema de Ayuda Enriquecido (`phelp`)

El perfil incluye un centro de ayuda dinámico con dos niveles de inspección:

### 1. Vista por Categorías o Filtro Amplio
```powershell
phelp          # Muestra todos los comandos organizados por áreas con sintaxis y descripción
phelp git      # Filtra todos los comandos de Git & Lazygit
phelp sql      # Filtra el kit de herramientas de SQL Server
phelp red      # Filtra utilidades de red y diagnóstico
```

### 2. Fichas Técnicas Detalladas con Ejemplos
Si se consulta un comando concreto por su nombre, `phelp` genera una ficha técnica con su sintaxis completa, categoría, descripción expandida y ejemplos reales de uso:
```powershell
phelp q
phelp vmod
phelp top
phelp ports
```

---

## ⚠️ Reglas Críticas sobre la Codificación del Perfil

Windows PowerShell 5.1 requiere estrictamente:
- **Codificación**: `UTF-8 con BOM` (Byte Order Mark: bytes `0xEF, 0xBB, 0xBF`).
- **Saltos de línea**: `CRLF` (`\r\n`).

> **Nota:** Si se edita este perfil con un editor que guarde en UTF-8 sin BOM, PowerShell 5.1 lo interpretará en codificación ANSI (Windows-1252), provocando errores sintácticos o corrupción de caracteres especiales y emojis como `⚡`.
