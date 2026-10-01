# PowerShell Profile & Entorno Git / SQL

Configuración personalizada de Windows PowerShell 5.1 (`Microsoft.PowerShell_profile.ps1`). Diseñada para aunar la potencia del paso de objetos y scripts de PowerShell con las comodidades habituales de un entorno Unix/Git (`sh`/`bash`/`zsh`): estado de repositorio en el prompt y autocompletado avanzado.

---

## 🚀 Requisitos y Módulos Externos

### 1. `posh-git` (Indispensable)
Proporciona integración nativa de Git en PowerShell:
- **Autocompletado con `<Tab>`**: Comandos de Git (`checkout`, `switch`, `merge`, `rebase`), ramas locales y remotas (`origin/<rama>`), tags, modificadores (`--amend`, `--no-verify`) y nombres de remotos.
- **Estado en el Prompt**: Muestra la rama activa y el estado del árbol de trabajo en tiempo real:
  - Formato: `[nombre-rama +A ~M -D !U]`
    - `+A`: Archivos añadidos al índice (staged).
    - `~M`: Archivos modificados (en índice o working directory).
    - `-D`: Archivos eliminados.
    - `!U`: Archivos no rastreados (*untracked*) o en conflicto.
    - `↑N / ↓N`: Commits pendientes de subir (push) o bajar (pull) respecto al tracking remoto.

#### Instalación (o configuración en un equipo nuevo):
Ejecutar en una consola de PowerShell:
```powershell
# 1. Habilitar TLS 1.2 (requerido por PowerShell Gallery en PowerShell 5.1)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# 2. Instalar el módulo para el usuario actual
Install-Module posh-git -Scope CurrentUser -Force
```

El perfil ya incluye la comprobación automática: si `posh-git` está instalado, se importa silenciosamente al iniciar la sesión.

---

### 2. `PSReadLine` (Manejo de consola y autocompletado)
Viene preinstalado por defecto en Windows PowerShell 5.1 (versión 2.0.0). Se encarga de la edición de línea de comandos, resaltado sintáctico y atajos de teclado.

#### Mejoras opcionales recomendadas:
Si deseas tener autocompletado predictivo tenue (estilo Fish Shell) y menú interactivo con flechas al pulsar `Tab` (estilo Zsh):
```powershell
# Actualizar a la versión más reciente (2.2+)
Install-Module PSReadLine -Scope CurrentUser -Force -SkipPublisherCheck
```
Opciones recomendadas para añadir al perfil si se desea:
```powershell
# Menú seleccionable con Tab
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# Sugerencias predictivas basadas en el historial
Set-PSReadLineOption -PredictionSource History
```

---

## 📂 Estructura del Perfil (`Microsoft.PowerShell_profile.ps1`)

| Sección | Descripción |
| :--- | :--- |
| **0. Codificación** | Establece `UTF-8` en entrada, salida y consola. |
| **1. Utilidades** | Funciones comunes como `cb` (portapapeles) y `kill-port` / `kp` (liberar puertos TCP). |
| **2. Navegación** | Atajos a proyectos: `sga`, `rsga`, `rsga2`, `rsga3`, `profile`, `notes`. |
| **3. Atajos de Git** | Integración de `posh-git` + atajos rápidos (`g`, `gs`, `ga`, `gp`, `gpush`, `gpsup`, `gco`, `glog`, `gss`, `gsl`, `gsp`, `agy-review-pr`). |
| **4. Ayuda Rápida** | `phelp` o `?p` con filtro opcional (`phelp git`, `phelp sql`). |
| **5. SQL Server Toolkit** | Conexión interactiva persistente, consultas (`q`, `q2excel`), descripciones (`desc`), explorador (`find-table`, `find-col`, `find-code`, `see`, `who`...). |
| **6. Autocompletado SQL** | `Ctrl + Espacio` en PSReadLine para autocompletar tablas de SQL Server en caché. |
| **7. Prompt Personalizado** | Muestra la ruta actual, el estado de Git (`posh-git`) y la sesión activa de SQL (`[BD ⚡]`). |

---

## 💡 Atajos rápidos de Git y Ayuda

Ejecuta en cualquier momento:
```powershell
phelp Git
```
Para ver todos los comandos de Git disponibles:
- `g <args>`: Alias nativo a `git` con soporte total de autocompletado (`g sw<Tab>` -> `g switch`, `g switch <Tab>` -> ramas, remotos, flags).
- `gco <rama>`: `git checkout <rama>` con autocompletado directo de ramas (`gco <Tab>` o `gco ma<Tab>`).
- `posh-git`: Proporciona la rama actual y estado en el prompt y el autocompletado inteligente con `Tab`.
- `gs`: `git status -sb`
- `ga`: `git add .`
- `gp` / `gf`: `git pull` / `git fetch`
- `gpush`: `git push`
- `gpsup` (o `gpu`): `git push --set-upstream origin <rama_actual>`
- `glog`: Historial compacto gráfico de los últimos 10 commits.
- `gss [mensaje]`: Guardar stash con timestamp y rama actual.
- `gsl`: Listar stashes con colores y fechas relativas.
- `gsp [idx]`: Aplicar y retirar stash.
- `agy-review-pr`: Revisión de Pull Requests con Antigravity sin saltar de rama.

---

## 🛠️ Utilidades y SQL Server Toolkit Destacados

- **`kill-port <puerto>` (alias `kp`)**: Finaliza el proceso que retiene un puerto local (ej. `kp 4200` o `kp 5000, 7000`).
- **`find-code <patrón>` (alias `find-sp`, `grep-sql`)**: Busca texto o nombres de tablas dentro de la definición de Procedimientos Almacenados, Vistas, Funciones y Triggers (soporta `-Grid`, `-Clip`, `-Csv`, `-Json`).
- **`q2excel <consulta>` (alias `qexcel`)**: Ejecuta una consulta SQL y la abre directamente en Excel con delimitador de punto y coma `;` para formato español sin descuadre.
- **`find-col <columna>`**: Busca en qué tablas y vistas de la base de datos existe una columna dada.
- **`see <objeto>` / `open-sql <objeto>`**: Inspecciona el código DDL de una vista o SP en consola o directamente en Neovim.
- **`q <consulta>`**: Ejecuta consultas ultrarrápidas con salvaguardas (switches: `-Grid`, `-Clip`, `-Csv`, `-Json`, `-DryRun`, `-Timeout N`).

---

## ⚡ Integración con Neovim

El perfil convierte a Neovim en el editor central del flujo de trabajo:

- **Editor predeterminado (`$env:EDITOR = 'nvim'`)**: Git (`commit`, `rebase -i`) y herramientas de consola utilizan Neovim automáticamente.
- **`v [archivo]` o `<comando> | v`**: Wrapper inteligente. Si recibe argumentos abre el archivo (`v main.cs`); si recibe datos por tubería (`gs | v`, `q "SELECT..." | v`), vuelca la salida a un buffer temporal en Neovim y lo elimina al cerrar.
- **`vrg <patrón> [ruta]`**: Ejecuta Ripgrep y abre automáticamente Neovim cargando los resultados en la lista **Quickfix** (`:copen`), saltando al primer resultado.
- **`vmod` (alias `vdiff`)**: Muestra en consola la lista coloreada de cambios (`[Modificado]`, `[Nuevo]`, `[Staged]`) y los abre en Neovim en pestañas individuales con la lista Quickfix (`:copen`) activa abajo. Soporta `-List` (o `-l`) para solo ver la lista sin abrir el editor, y `-Splits` para divisiones verticales.
- **`vsql`**: Abre un scratchpad SQL temporal con sintaxis resaltada y contexto de la BD actual. Al guardar y salir (`:wq`), pregunta si deseas ejecutarlo directamente con `q`.
- **`ep` (alias `edit-profile`)**: Abre `Microsoft.PowerShell_profile.ps1` en Neovim.
- **`en` (alias `edit-nvim`)**: Abre la carpeta de configuración de Neovim (`~\AppData\Local\nvim`).
- **<kbd>Ctrl</kbd>+<kbd>X</kbd>, <kbd>Ctrl</kbd>+<kbd>E</kbd>**: Edita el comando que estés escribiendo en la consola dentro de una ventana de Neovim y lo devuelve al prompt listo para ejecutar.

---

## ⚠️ Reglas Críticas sobre la Codificación del Perfil

Windows PowerShell 5.1 requiere estrictamente:
- **Codificación**: `UTF-8 con BOM` (Byte Order Mark: bytes `0xEF, 0xBB, 0xBF`).
- **Saltos de línea**: `CRLF` (`\r\n`).

> **Nota:** Si se edita este perfil con un editor que guarde en UTF-8 sin BOM (UTF-8 puro), PowerShell 5.1 lo interpretará como codificación ANSI (Windows-1252), provocando errores sintácticos o corrupción de caracteres especiales y emojis como `⚡`.
