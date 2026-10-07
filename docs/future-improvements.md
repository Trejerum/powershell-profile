# 🗺️ Hoja de Ruta y Mejoras Futuras (Future Improvements)

Este documento sirve como registro, especificación y planificación de posibles mejoras, nuevos módulos y utilidades a incorporar en el perfil de PowerShell a medio y largo plazo.

Cada propuesta incluye su **propósito**, **impacto en el flujo diario**, **módulo de integración**, **sintaxis de uso** y **evaluación de riesgo/compatibilidad** (con especial foco en compatibilidad total con Windows PowerShell 5.1, codificación UTF-8 con BOM y entornos corporativos).

---

## 📊 Matriz de Evaluación Rápida

| Área | Propuesta | Estado | Módulo Destino |
| :--- | :--- | :---: | :--- |
| **SQL & Datos** | Diagnóstico en vivo con DMVs (`who`, `see`, `see-idx`) | ✅ Implementado | `profile.d/30-sql.ps1` |
| **SQL & Datos** | Comparador de resultados entre entornos (`sql-diff`) | 🟡 Pendiente | `profile.d/30-sql.ps1` |
| **Terminal / Logs** | Visor de logs con coloreado semántico en vivo (`tailf` / `watch-log`) | 🟢 Pendiente | `profile.d/40-utils.ps1` |
| **Terminal / Monitoreo** | Loop de monitoreo continuo interactivo (`watch`) | ✅ Implementado | `profile.d/40-utils.ps1` |
| **Desarrollo / Scaffolding** | Generador de scripts y migraciones (`new-script`, `new-migration`) | 🟡 Pendiente | `profile.d/40-utils.ps1` |
| **Editor / Portapapeles** | Comparador inteligente de portapapeles (`clip-diff` / `vdiff-clip`) | ✅ Implementado | `profile.d/40-utils.ps1` |
| **Workspaces** | Cambio de contexto y espacio de trabajo (`work <proyecto>`) | 🟡 Pendiente | `profile.d/10-navigation.ps1` |
| **Rendimiento** | Benchmark y profiling del perfil (`profile-bench` / `pbench`) | ✅ Implementado | `profile.d/40-utils.ps1` |

---

## 1. 🗄️ Diagnóstico y Monitoreo SQL en Vivo (DMVs de SQL Server)

- [x] **Comandos de diagnóstico rápido de base de datos (`who`, `see`, `see-idx`)** *(Implementado en `profile.d/30-sql.ps1`)*
  - **Contexto:** Actualmente `profile.d/30-sql.ps1` cuenta con un motor completo de ADO.NET (`q`, `sql-session`, `table`, `sp`, `sql-ping`, `sql-export`), pero ante cuellos de botella o bloqueos en servidores de desarrollo o producción, es necesario escribir consultas complejas a mano.
  - **Propuestas:**
    1. **`sql-who`**: Alternativa limpia y formateada a `sp_who2`:
       - Consulta `sys.dm_exec_requests` y `sys.dm_exec_sessions`.
       - Muestra SPID, Login, Hostname, Base de datos, Estado (`RUNNING`, `SUSPENDED`), Tiempo CPU, Lecturas y el texto truncado de la consulta activa.
    2. **`sql-locks` / `sql-blocks`**: Detección inmediata de bloqueos en cascada:
       - Muestra qué SPID bloqueador (Blocker) está deteniendo a qué SPID bloqueado (Blocked), el tiempo de espera y el recurso afectado.
    3. **`sql-top-cpu` / `sql-top-io`**:
       - Top 10 consultas más pesadas acumuladas en la caché del servidor (`sys.dm_exec_query_stats`), formateadas con tiempo medio y número de ejecuciones.
  - **Beneficio:** Diagnóstico inmediato de incidentes en bases de datos directamente desde PowerShell sin necesidad de abrir SQL Server Management Studio (SSMS).
  - **Riesgo:** **Nulo**. Consultas de solo lectura (`NOLOCK`) a vistas de gestión dinámica estándar de SQL Server mediante la conexión ADO.NET ya configurada en `sql-connections.json`.

---

## 2. ⚖️ Comparador de Consultas entre Entornos (`sql-diff`)

- [ ] **Comparar resultados de consultas entre bases de datos**
  - **Contexto:** Al realizar migraciones, despliegues o depuración de inconsistencias, a menudo se necesita verificar si el resultado de una consulta es idéntico entre dos entornos (ej. `dev` vs `staging` o `prod`).
  - **Propuesta:**
    - Sintaxis: `sql-diff -Query "SELECT Codigo, Nombre, Stock FROM Articulos" -ProfileA dev -ProfileB staging`
    - Ejecuta la consulta en ambos perfiles, compara los DataTables fila por fila y resalta en amarillo/rojo las discrepancias o filas faltantes.
    - Soporte para volcar la comparación a Neovim diff (`nvim -d fileA.csv fileB.csv`).
  - **Beneficio:** Auditoría rápida de datos y validación de sincronización sin herramientas externas pesadas.
  - **Riesgo:** **Nulo**.

---

## 3. 📜 Visor de Logs con Coloreado Semántico (`tailf` / `watch-log`)

- [ ] **Seguimiento inteligente de ficheros de log en tiempo real**
  - **Contexto:** El cmdlet estándar `Get-Content -Wait -Tail 50` muestra texto plano monocromo sin jerarquía visual.
  - **Propuesta:**
    - Comando `tailf <archivo.log> [-Filter "regex"]`
    - Procesamiento en streaming línea por línea con resaltado ANSI:
      - `[ERROR]`, `[FATAL]`, `Exception`, `Failed` ➔ **Rojo brillante**.
      - `[WARN]`, `[WARNING]` ➔ **Amarillo**.
      - `[INFO]` ➔ **Cian**.
      - Timestamps (ISO o `yyyy-MM-dd HH:mm:ss`) ➔ **Gris oscuro**.
      - `[SUCCESS]`, `[OK]` ➔ **Verde**.
  - **Beneficio:** Lectura descansada e identificación instantánea de errores en logs largos de aplicaciones o servicios.
  - **Riesgo:** **Nulo**.

---

## 4. ⏱️ Monitoreo Continuo en Terminal (`watch`)

- [x] **Ejecución periódica en bucle de comandos y consultas (`watch`)** *(Implementado en `profile.d/40-utils.ps1`)*
  - **Contexto:** En entornos Linux, la herramienta `watch` permite observar la evolución de un comando cada N segundos. En PowerShell no existe un comando nativo estándar equivalente.
  - **Propuesta:**
    - Sintaxis: `watch <segundos> { <scriptblock> }`
    - Limpia la pantalla, muestra un encabezado con la hora exacta y el comando evaluado, y actualiza el resultado en bucle (cancelable con `Ctrl+C`).
    - **Ejemplos de uso:**
      ```powershell
      watch 2 { port 1433 }                                            # Vigilar conexiones al puerto SQL
      watch 5 { q "SELECT COUNT(*) FROM Logs WHERE Nivel = 'ERROR'" }   # Vigilar inserciones de errores
      watch 3 { git status -s }                                         # Vigilar cambios en el workspace
      ```
  - **Beneficio:** Evita tener que pulsar repetidamente la tecla `Enter` o la flecha arriba para comprobar el estado de un proceso o tabla.
  - **Riesgo:** **Nulo**.

---

## 5. 🧱 Generación y Scaffolding de Plantillas (`new-*`)

- [ ] **Scaffolding estructurado y seguro de nuevos ficheros**
  - **Contexto:** Crear nuevos scripts de PowerShell o migraciones SQL desde cero suele implicar copiar y pegar estructuras boilerplate o olvidar cabeceras críticas (como UTF-8 con BOM o transacciones seguras).
  - **Propuestas:**
    1. **`new-script <nombre>`**:
       - Crea un archivo `.ps1` profesional con `[CmdletBinding()]`, bloques `param()`, manejo estructurado de errores con `try/catch`, cabecera UTF-8 con BOM (`0xEF, 0xBB, 0xBF`) y saltos de línea CRLF.
       - Abre el archivo automáticamente en Neovim listo para programar.
    2. **`new-migration <nombre>`**:
       - Genera un archivo `.sql` fechado (`yyyyMMdd_HHmm_nombre.sql`) con plantilla de transacción idempotente:
         ```sql
         SET XACT_ABORT ON;
         BEGIN TRANSACTION;
         BEGIN TRY
             -- Script de migración idempotente aquí
             COMMIT TRANSACTION;
         END TRY
         BEGIN CATCH
             IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
             THROW;
         END CATCH;
         ```
  - **Beneficio:** Estandarización de calidad y ahorro de tiempo al iniciar nuevos scripts o migraciones de base de datos.
  - **Riesgo:** **Nulo**.

---

## 6. 📋 Comparador Inteligente de Portapapeles (`clip-diff`)

- [x] **Comparar portapapeles contra archivos o selecciones (`clip-diff` / `vdiff-clip`)** *(Implementado en `profile.d/40-utils.ps1`)*
  - **Contexto:** Frecuentemente se copia una respuesta JSON de una API, un snippet o un log al portapapeles y se quiere comparar rápidamente con un archivo local sin tener que crear y guardar archivos temporales a mano.
  - **Propuesta:**
    - Comando `clip-diff [archivo_local]` (alias: `vdiff-clip`):
      - Vuelca el portapapeles (`Get-Clipboard`) en un archivo temporal en `$env:TEMP`.
      - Si se especifica un archivo local, lanza `nvim -d $tempFile $archivoLocal` (o `code --diff` si se prefiere).
      - Si no se especifica archivo, permite comparar dos capturas consecutivas del portapapeles.
      - Al cerrar el editor, limpia automáticamente los temporales.
  - **Beneficio:** Diagnóstico y comparación de datos ultrarrápida sin ensuciar el árbol de trabajo de Git.
  - **Riesgo:** **Nulo**.

---

## 7. 🚀 Espacios de Trabajo por Proyecto (`work <proyecto>`)

- [ ] **Orquestación de cambio de contexto de desarrollo**
  - **Contexto:** Al cambiar de proyecto a lo largo del día, normalmente se requiere:
    1. Cambiar de directorio (`cd`).
    2. Cambiar el perfil de SQL activo (`Set-SqlProfile`).
    3. Abrir o revisar las notas del día de ese proyecto (`n <proyecto>`).
  - **Propuesta:**
    - Crear `work <proyecto>` (con autocompletado de los repositorios de `$global:ProjectsRoot`):
      - Navega al directorio del repositorio.
      - Si existe un perfil SQL con el mismo nombre (o configurado en un archivo `.project.json`), cambia automáticamente el perfil SQL por defecto.
      - Muestra un resumen rápido del estado de Git y notas recientes asociadas.
  - **Beneficio:** Reduce a un solo comando todo el cambio de contexto entre clientes o aplicaciones.
  - **Riesgo:** **Nulo**.

---

## 8. 📊 Profiling y Benchmark de Rendimiento (`bench`)

- [ ] **Medición estadística de ejecución de bloques de código**
  - **Contexto:** `Measure-Command` solo mide una única ejecución, lo que genera lecturas sesgadas por calentamiento de caché, conexiones iniciales o I/O de disco.
  - **Propuesta:**
    - Sintaxis: `bench { <scriptblock> } [-Iterations 10] [-Warmup 1]`
    - Ejecuta el bloque N veces y genera una tabla con:
      - Tiempo medio, mediano, mínimo y máximo.
      - Desviación típica.
      - Memoria consumida / asignada.
    - Soporta tanto scripts PowerShell como consultas SQL (`bench { q "SELECT ..." }`).
  - **Beneficio:** Optimización rigurosa de algoritmos, scripts y consultas pesadas.
  - **Riesgo:** **Nulo**.
