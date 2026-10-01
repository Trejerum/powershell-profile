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
| **1. Utilidades** | Funciones comunes como `cb` (copiar al portapapeles desde pipe o texto). |
| **2. Navegación** | Atajos a proyectos: `sga`, `rsga`, `rsga2`, `rsga3`, `profile`, `notes`. |
| **3. Atajos de Git** | Integración de `posh-git` + atajos rápidos (`g`, `gs`, `ga`, `gp`, `gpush`, `gpsup`, `gco`, `glog`, `gss`, `gsl`, `gsp`, `agy-review-pr`). |
| **4. Ayuda Rápida** | `phelp` o `?p` con filtro opcional (`phelp git`, `phelp sql`). |
| **5. SQL Server Toolkit** | Conexión interactiva persistente, consultas directas (`q`), descripciones (`desc`), explorador (`find-table`, `see`, `who`...). |
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

## ⚠️ Reglas Críticas sobre la Codificación del Perfil

Windows PowerShell 5.1 requiere estrictamente:
- **Codificación**: `UTF-8 con BOM` (Byte Order Mark: bytes `0xEF, 0xBB, 0xBF`).
- **Saltos de línea**: `CRLF` (`\r\n`).

> **Nota:** Si se edita este perfil con un editor que guarde en UTF-8 sin BOM (UTF-8 puro), PowerShell 5.1 lo interpretará como codificación ANSI (Windows-1252), provocando errores sintácticos o corrupción de caracteres especiales y emojis como `⚡`.
