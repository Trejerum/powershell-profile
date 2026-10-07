# ⚡ Arquitectura y Migración Dual a PowerShell 7 (`pwsh`)

Este documento detalla la arquitectura, decisiones de diseño, compatibilidad y configuración del entorno híbrido **PowerShell 7 (`pwsh`) + Windows PowerShell 5.1** implementado en los dotfiles.

---

## 🎯 1. Objetivos y Filosofía del Diseño

El objetivo principal era modernizar el entorno de desarrollo aprovechando las ventajas de **PowerShell 7** (motor .NET moderno, ejecución asíncrona, mayor velocidad de I/O) manteniendo **cero riesgo de rotura**:
1. **Compatibilidad Dual 100%:** Ambas versiones (5.1 y 7) leen los mismos scripts sin conflictos.
2. **Cero Doble Mantenimiento:** Un único repositorio Git físico gestiona ambas configuraciones.
3. **Aislamiento en Espacio de Usuario:** Instalación sin permisos de administrador ni modificaciones invasivas en el registro de Windows.
4. **PowerShell 5.1 como Red de Seguridad:** Si alguna herramienta legacy lo requiere, PS 5.1 permanece intacto y listo para usar.

---

## 🏛️ 2. Arquitectura de Archivos y Enlaces NTFS

PowerShell busca sus perfiles en rutas diferentes según la versión y las directivas de Windows/OneDrive:
* **Windows PowerShell 5.1:** `OneDrive\Documentos\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`
* **PowerShell 7 (Core):** `OneDrive\Documentos\PowerShell\Microsoft.PowerShell_profile.ps1`

### Estructura de Enlaces (Junctions)

```
C:\Users\diego.corral\
 ├── .dotfiles\powershell\                 <-- Repositorio Git Físico (Única fuente de verdad)
 │    ├── Microsoft.PowerShell_profile.ps1
 │    ├── profile.d\
 │    ├── Modules\
 │    └── config\
 │
 └── OneDrive - PKF ATTEST\Documentos\
      ├── WindowsPowerShell\  =============> NTFS Junction -> C:\Users\diego.corral\.dotfiles\powershell
      └── PowerShell\         =============> NTFS Junction -> C:\Users\diego.corral\.dotfiles\powershell
```

Ambas carpetas de Documentos apuntan mediante un enlace a nivel de sistema de archivos (`mklink /J`) al mismo repositorio físico. **Cualquier cambio, alias o script añadido en el repositorio se propaga automáticamente a ambas versiones.**

---

## ⚙️ 3. Adaptaciones Clave en `profile.d/`

Para garantizar que el mismo código se ejecute sin errores en ambos motores (.NET Framework 4.8 vs .NET Core / .NET 9), se realizaron las siguientes adaptaciones:

### 3.1. SQL Toolkit (`profile.d/30-sql.ps1`)
* **Problema:** El módulo `SqlServer` contenía DLLs compiladas específicamente para .NET Framework que fallaban en .NET Core (`DbProviderFactory.CreatePermission missing method`).
* **Solución:** Se implementó una factoría de conexiones basada directamente en ADO.NET estándar (`System.Data.SqlClient`).
* **Resultado:** Tanto PS 5.1 como PS 7 disponen de la librería `System.Data.SqlClient` integrada. Los comandos `q`, `qping`, `qtop`, `qconnect` y la gestión de sesiones funcionan de manera idéntica y sin dependencias de ensamblados externos.

### 3.2. Navegación y Paneles (`profile.d/10-navigation.ps1`)
* Los comandos `split-term` y `layout-dev` detectan dinámicamente el ejecutable del motor activo:
  ```powershell
  $script:CurrentShellExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
  ```
* Al dividir la pantalla o abrir nuevos paneles, se preserva el mismo motor en el que se encuentra el usuario.

### 3.3. Benchmark y Utilidades (`profile.d/40-utils.ps1`)
* El comando `profile-bench` ejecuta la prueba de arranque contra el shell en el que se invoca (`pwsh.exe` si estás en PS 7, `powershell.exe` si estás en PS 5.1).

### 3.4. Prefijo Visual en el Prompt (`profile.d/99-prompt.ps1`)
* Para saber de un vistazo en qué entorno se está trabajando, el prompt incluye la versión mayor de PowerShell:
  * En PowerShell 7: `PS7 ~ >`
  * En Windows PowerShell 5.1: `PS5 ~ >`

### 3.5. Neovim (`~/.dotfiles/nvim/lua/config/sql.lua`)
* El plugin de SQL en Neovim detecta automáticamente si `pwsh` está instalado (`vim.fn.executable("pwsh") == 1`) para lanzar las consultas con el motor de PS 7, manteniendo fallback transparente a `powershell.exe`.

---

## 🖥️ 4. Configuración de Terminales Predeterminadas

PowerShell 7 ha quedado configurado como el shell principal en las aplicaciones de uso diario:

### 4.1. Windows Terminal
* **Archivo:** `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`
* **Perfil por defecto:** GUID `{574e775e-4f2a-5b96-ac1e-a2962a402336}` (PowerShell 7).
* **Definición en `profiles.list`:**
  ```json
  {
      "guid": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",
      "hidden": false,
      "name": "PowerShell 7",
      "source": "Windows.Terminal.PowershellCore",
      "startingDirectory": "%USERPROFILE%"
  }
  ```
  *(La propiedad `"source": "Windows.Terminal.PowershellCore"` vincula la personalización con el generador dinámico nativo de Windows Terminal, evitando advertencias de GUIDs duplicados).*
* Al pulsar `+` o iniciar Windows Terminal, arranca en PowerShell 7.
* En el desplegable de pestañas sigue disponible el perfil clásico `Windows PowerShell` para emergencias.

### 4.2. Visual Studio Code
* **Archivo:** `%APPDATA%\Code\User\settings.json`
* **Configuración:**
  ```json
  "terminal.integrated.defaultProfile.windows": "PowerShell 7",
  "terminal.integrated.profiles.windows": {
      "PowerShell 7": {
          "path": "pwsh.exe",
          "icon": "terminal-powershell"
      },
      "Windows PowerShell": {
          "path": "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
      }
  }
  ```

---

## 📊 5. Resultados de Rendimiento (Benchmarks Reales)

Mediciones realizadas en la máquina local (`profile-bench` y `qping`):

| Métrica | Windows PowerShell 5.1 | PowerShell 7 (`pwsh`) | Mejora |
| :--- | :---: | :---: | :---: |
| **Arranque en frío (Cold start)** | 2.094 ms | **1.347 ms** | 🟢 **-35,7%** más rápido |
| **Carga de módulos del perfil** | 260 ms | **196 ms** | 🟢 **-24,7%** más rápido |
| **Latencia SQL Ping (`qping`)** | 120 ms | **79 ms** | 🟢 **-34,2%** más rápido |
| **Arquitectura de Runtime** | .NET Framework 4.8 | .NET 9 CoreCLR | x64 moderno |

---

## 🛠️ 6. Filosofía de Mantenimiento y Futuro

1. **¿Tengo que programar todo dos veces?**  
   **No.** Las funciones y alias se añaden una sola vez en el archivo temático correspondiente de `profile.d/`. El 98% de la sintaxis estándar de PowerShell es idéntica en ambas versiones.
2. **Entorno de trabajo habitual:**  
   PowerShell 7 es tu entorno de trabajo diario. Todas las nuevas utilidades se desarrollan y usan en PS 7.
3. **Congelación de PS 5.1:**  
   PowerShell 5.1 queda como respaldo estable. No requiere mantenimiento activo.
4. **Desconexión futura de 5.1:**  
   Si en el futuro se decide que PS 5.1 ya no es necesario, basta con seguir usando PS 7 sin ninguna acción requerida.

---

## 🔄 7. Plan de Reversión (Rollback)

Si por cualquier motivo se deseara volver a tener Windows PowerShell 5.1 como terminal por defecto:
1. En Windows Terminal (`settings.json`), cambiar `"defaultProfile"` a `"{61c54bbd-c2c6-5271-96e7-009a87ff44bf}"`.
2. En VS Code (`settings.json`), cambiar `"terminal.integrated.defaultProfile.windows"` a `"Windows PowerShell"`.
3. Ambos perfiles siguen conviviendo sin necesidad de desinstalar nada.
