# PowerShell Profile & Centro de Mando Developer

Configuración avanzada para Windows PowerShell 5.1 (`Microsoft.PowerShell_profile.ps1`). Convierte la consola en un centro de mando integral que aúna la velocidad del paso de objetos en .NET con la agilidad de los flujos de trabajo Unix, integrando **Git**, **Lazygit**, **Neovim**, **Ripgrep**, **SQL Server** y herramientas de diagnóstico de sistema y red.

---

## 🚀 Requisitos y Herramientas del Entorno

El perfil detecta automáticamente las herramientas instaladas y activa sus aceleradores:

| Herramienta | Utilidad en el Perfil |
| :--- | :--- |
| **`posh-git`** | Estado del repo en el prompt (`[rama +A ~M -D !U]`) y autocompletado nativo con `<Tab>`. |
| **`PSReadLine`** | Historial predictivo contextual (<kbd>↑</kbd>/<kbd>↓</kbd>) y edición visual con Neovim. |
| **`Neovim` (`nvim`)** | Editor principal de Git, visor de diffs, visor de tuberías (`v`), quickfix de Ripgrep (`vrg`) y scratchpad SQL (`vsql`). |
| **`Ripgrep` (`rg`)** | Búsqueda ultrarrápida de archivos (`ff`) y de texto con Quickfix (`vrg`). |
| **`Lazygit` (`lg`)** | Interfaz TUI completa para Git directamente desde la terminal. |
| **`7-Zip` (`7z`)** | Descompresor multiformato unificado (`extract`). |

---

## 📂 Arquitectura Modular (`profile.d/`)

El perfil utiliza un cargador raíz ultraligero (`Microsoft.PowerShell_profile.ps1`) que importa de forma ordenada y aislada los módulos temáticos ubicados en el directorio `profile.d/`. Esto garantiza que un fallo puntual nunca bloquee la consola y facilita enormemente el mantenimiento y control de versiones en Git:

| Archivo | Área | Descripción |
| :--- | :--- | :--- |
| **`00-env.ps1`** | **Entorno & Consola** | Codificación `UTF-8` en entrada, salida y consola. Asigna Neovim como editor global (`$env:EDITOR = 'nvim'`) y configura navegación contextual en el historial (<kbd>↑</kbd>/<kbd>↓</kbd>) y edición visual (<kbd>Ctrl+X, Ctrl+E</kbd>). |
| **`10-navigation.ps1`** | **Navegación Ágil** | Subida de niveles (`..`, `...`, `....`), creación y entrada (`mkcd`), explorador (`open`/`o`), salto dinámico a proyectos (`proj`), recarga (`reload`/`rel`) y atajos a repositorios (`sga`, `rsga`, `rsga2`, `rsga3`, `ep`, `en`). |
| **`15-notes.ps1`** | **Notas & Diario** | Gestión de notas diarias en Neovim (`note`/`today`), captura rápida desde consola, buscador histórico (`snote`/`vnote`), dashboard (`lnotes`), scratchpad SQL (`note-sql`) y versionado Git (`notes-sync`). |
| **`20-git.ps1`** | **Git & Lazygit** | Alias universal `g`, integración con `posh-git`, dashboard en vivo (`repo-status`/`repos`), TUI (`lg`), commits rápidos (`gcom`), checkout/switch (`gco`, `gcob`), ramas ordenadas (`gb`), deshacer (`gundo`), diff split (`vd`), visor de modificados (`vmod`), stash (`gss`, `gsl`, `gsp`) y auditorías con Antigravity (`agy-review-pr`). |
| **`30-sql.ps1`** | **SQL Server Toolkit** | Motor ADO.NET (`q`), sesión persistente (`qconnect`, `qdisc`, `use`), exploración (`dbs`, `tables`, `views`, `top`, `desc`, `count`), búsqueda (`find-table`, `find-col`, `find-code`), monitor (`who`, `see`, `see-idx`), exportación (`q2excel`, `qclip`, `qfmt`), scratchpad (`vsql`) y autocompletado en consola (<kbd>Ctrl</kbd>+<kbd>Espacio</kbd>). |
| **`40-utils.ps1`** | **Utilidades Generales** | Archivos (`touch`, `ff`, `head`, `tail`, `extract`), diagnóstico (`ports`, `kill-port`/`kp`, `psfind`, `myip`, `sysinfo`), portapapeles (`cb`), integración Neovim (`v`, `vrg`) y buscador de comandos de consola (`hist`). |
| **`50-help.ps1`** | **Centro de Ayuda** | Guía de comandos agrupada por áreas (`phelp`, `phelp git`, `phelp sql`) y fichas técnicas detalladas con ejemplos (`phelp <comando>`). |
| **`99-prompt.ps1`** | **Prompt Personalizado** | Muestra la ruta activa, el estado en vivo de Git vía `posh-git` y el badge de conexión persistente a SQL Server (`[BD ⚡]`). |

---

## 🧭 1. Navegación Ágil y Gestión de Directorios

- **`..` / `...` / `....`**: Sube 1, 2 o 3 niveles en el árbol de directorios sin teclear `cd ..\..`.
- **`mkcd <carpeta>`**: Crea un directorio (incluyendo carpetas intermedias si faltan) y entra en él inmediatamente.
- **`open [ruta]` (alias `o`)**: Abre el Explorador de Windows en la carpeta actual o en la ruta especificada.
- **`proj [nombre]`**: Salto dinámico a cualquier subproyecto dentro de `Documentos\Proyectos` con autocompletado <kbd>Tab</kbd>. Si se ejecuta sin parámetros, lista los proyectos disponibles.
- **`reload` (alias `rel`, `rprof`, `reload-profile`)**: Recarga el perfil en la consola actual con confirmación visual.
- **Atajos directos de proyectos:**
  - `sga`: Salta a `$HOME\Documentos\Proyectos\SGA`.
  - `rsga` / `rsga2` / `rsga3`: Salta a las instancias locales del repositorio RSGA.
  - `profile`: Salta a la carpeta del perfil de PowerShell.
  - `notes [args]`: Navega a `$HOME\Documentos\Notes` (o ejecuta captura/apertura si recibe argumentos).
  - `ep [modulo]` (alias `edit-profile`): Abre `Microsoft.PowerShell_profile.ps1` o un módulo específico (ej. `ep notes`, `ep sql`, `ep git`, `ep utils`) en Neovim.
  - `en` (alias `edit-nvim`): Abre la configuración de Neovim (`~\AppData\Local\nvim`).

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

---

## 📄 2. Archivos, Búsqueda y Productividad Unix

- **`touch <archivo...>`**: Crea archivos vacíos (o actualiza su timestamp si ya existen) al estilo Unix. Si la ruta incluye carpetas que no existen, las crea automáticamente.
- **`ff <patrón> [ruta]`**: Búsqueda recursiva ultrarrápida de archivos por coincidencia de nombre usando `rg --files` (o fallback nativo .NET).
- **`which <comando>`**: Muestra la ruta absoluta, tipo de comando (Cmdlet, Alias, Application) y versión de cualquier ejecutable.
- **`head <archivo> [-n 10]`**: Muestra las primeras N líneas de un archivo o flujo sin cargarlo entero en memoria.
- **`tail <archivo> [-n 10]`**: Muestra las últimas N líneas de un archivo o fichero de log.
- **`extract <archivo> [destino]`**: Descompresor universal para `.zip`, `.tar.gz`, `.7z` o `.rar` utilizando `7z`, `tar` o `Expand-Archive`.
- **`cb [texto] | <comando> | cb`**: Copia texto o cualquier objeto de la consola directamente al portapapeles de Windows.

---

## 🌿 3. Git & Lazygit Superpowers

- **`lg`**: Lanza la interfaz gráfica interactiva de terminal de **Lazygit**.
- **`repo-status` (alias `repos`, `sga-status`)**: Dashboard en tiempo real de tus entornos/clones Git de SGA (`RSGA`, `RSGA_2`, `RSGA_3`):
  - Muestra rama activa, cambios locales pendientes (`+staged`, `~mod`, `!new` o `Limpio`), estado de sincronización con origin (`Al día`, `↑ N pendiente(s)`, `↓ N por bajar`) y el último commit con fecha relativa.
  - **Salto rápido:** `repos 1` (salta a `RSGA`), `repos 2` (`RSGA_2`), `repos 3` (`RSGA_3`).
  - **Refresco remoto:** `repos -f` (hace `git fetch` en los clones antes de evaluar para reflejar el estado de origin al instante).
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
  - `gco <rama>`: `git checkout <rama>` con autocompletado inteligente de ramas.
  - `glog`: Historial compacto gráfico de los últimos 10 commits.
  - `gss [msg]` / `gsl` / `gsp [idx]`: Guardar, listar y aplicar stashes con timestamps y rama activa.
  - `agy-review-pr <rama> [base]`: Auditoría de Pull Requests con Antigravity sin saltar de rama.

---

## 🖥️ 4. Diagnóstico de Sistema, Red y Procesos

- **`ports [filtro]` (alias `listening`)**: Muestra todos los puertos TCP a la escucha en la máquina con su puerto, IP, PID y nombre del proceso asociado.
- **`kill-port <puerto...>` (alias `kp`)**: Busca y finaliza los procesos que retienen uno o varios puertos locales (ej. `kp 4200` o `kp 5000, 7000`).
- **`psfind <nombre>` (alias `psgrep`)**: Busca procesos en ejecución mostrando PID, memoria en MB y tiempo de CPU consumido.
- **`myip`**: Muestra la dirección IP local de las interfaces activas y consulta la IP pública externa.
- **`sysinfo`**: Muestra el tiempo de encendido (uptime) de Windows, uso de memoria RAM (usada/total/libre) y espacio libre en discos.

---

## 🗄️ 5. SQL Server Toolkit (ADO.NET)

Motor de alto rendimiento conectado por defecto a la instancia local `PORT1220\SQL_SERVER`:

### Conexión y Contexto
- **`qconnect [servidor] [bd]`**: Abre una conexión persistente reutilizable de alto rendimiento (muestra `[BD ⚡]` en el prompt).
- **`qdisc` (alias `qdisconnect`)**: Cierra la sesión persistente activa y vuelve al modo transitorio.
- **`use <BaseDatos>`**: Cambia la base de datos activa al vuelo con autocompletado y refresca la caché de autocompletado.
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
