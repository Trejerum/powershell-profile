# 🤖 Guía de Configuración del Asistente IA (AI Setup Guide)

Este documento detalla la arquitectura, instalación, autenticación y desacoplamiento del módulo de inteligencia artificial en la consola ([`profile.d/25-ai.ps1`](../profile.d/25-ai.ps1)).

---

## 1. 🏗️ Arquitectura Desacoplada

El módulo de IA está diseñado bajo el principio de **desacoplamiento total** entre los comandos de usuario y el motor de inferencia:

```text
┌────────────────────────────────────────────────────────┐
│  Comandos de Terminal: ??, explain-error, gai           │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│  Función Adaptadora: Invoke-AICompletion                │
└──────────────────────────┬─────────────────────────────┘
                           │  $global:AIProvider
                           ▼
     ┌─────────────────────┬─────────────────────┐
     │                     │                     │
     ▼                     ▼                     ▼
Antigravity CLI         OpenAI / Azure        Ollama Local
  (`agy.exe`)            (REST API)          (Local LLM)
 [ACTUAL / DEFAULT]      [FUTURO]              [FUTURO]
```

### Ventajas de este diseño
1. **Sin dependencias rígidas**: Si en unos meses dejas de utilizar `agy` y adoptas otro modelo o API corporativa, **no es necesario cambiar la sintaxis de tus comandos**. Solo se adapta la función interna `Invoke-AICompletion`.
2. **Cero impacto en el arranque**: Si un equipo nuevo no tiene instalado ningún CLI de IA, el perfil de PowerShell **inicia al 100% de velocidad sin errores**. Solo muestra un mensaje informativo si intentas ejecutar `??` o `explain-error`.
3. **Fácilmente removible**: El archivo [`profile.d/25-ai.ps1`](../profile.d/25-ai.ps1) es completamente autónomo. Si deseas desactivar las funciones de IA, basta con renombrarlo o borrarlo.

---

## 2. ⚡ Comandos Disponibles

| Comando | Alias | Descripción |
| :--- | :---: | :--- |
| `ask-cmd <consulta>` | `??` | Traduce una petición en lenguaje natural a código ejecutable de PowerShell 5.1 con menú interactivo (`[E]jecutar`, `[C]opiar`, `[S]alir`). |
| `explain-error` | `why-error`, `perror` | Analiza el último error del sistema (`$Error[0]`) y explica causa raíz y solución recomendada en 3 líneas concisas. |
| `gai` | - | Analiza los cambios en stage (`git diff --staged`) y redacta una propuesta de commit bajo la convención *Conventional Commits* con menú interactivo. |
| `agy-history [n] [filtro]` | `achats`, `agy-chats` | Lista el historial de conversaciones anteriores de Antigravity con su fecha, índice e intención inicial. |
| `agy-resume [n/ID]` | `aresume`, `agy-c` | Reanuda una conversación por su índice (`aresume 1`), ID (`aresume 8f79c406`) o selector interactivo con `fzf`. |

---

## 3. 💾 Persistencia y Gestión de Conversaciones

Las conversaciones de Antigravity son 100% persistentes y se guardan localmente en el disco duro:
* **Ubicación física**: `~/.gemini/antigravity-cli/brain/<UUID-conversacion>/`
* **Transcripts completos**: Cada carpeta contiene `.system_generated\logs\transcript.jsonl` con el registro de mensajes, preguntas y respuestas.
* **Continuar la última conversación**: Escribe `aresume` (o `agy -c`) desde cualquier sesión de PowerShell para retomar la última sesión abierta.
* **Reanudar por número**: Ejecuta `achats` para ver las conversaciones recientes numeradas (`[1], [2], [3]...`) y escribe `aresume <n>` (ej. `aresume 2`) para saltar a ella al instante.

## 4. 🚀 Configuración de Antigravity CLI (`agy`) en un Nuevo Equipo

El proveedor configurado por defecto es **Antigravity CLI** (`agy`), que utiliza modelos Gemini con inferencia rápida optimizada para terminal (`--effort low`).

### Paso 1: Instalación del ejecutable
En Windows, el CLI de Antigravity se ubica por defecto en:
```text
C:\Users\<usuario>\AppData\Local\agy\bin\agy.exe
```

Para asegurar que esté disponible globalmente en la consola, ejecuta:
```powershell
# Comprobar si ya está en el PATH
Get-Command agy -ErrorAction SilentlyContinue

# Si no está en el PATH, añadir la carpeta de instalación:
$agyPath = Join-Path $env:LOCALAPPDATA "agy\bin"
if (Test-Path $agyPath) {
    $env:PATH = "$agyPath;$env:PATH"
}
```

### Paso 2: Autenticación inicial
Para autenticar el CLI en un equipo nuevo:
1. Abre PowerShell y escribe simplemente:
   ```powershell
   agy
   ```
2. La primera vez, el CLI abrirá automáticamente una pestaña en tu navegador web predeterminado solicitando que inicies sesión con tu cuenta de Google.
3. Una vez aprobada la autorización, el token OAuth se guarda cifrado en tu carpeta de usuario local:
   ```text
   C:\Users\<usuario>\.gemini\oauth_creds.json
   ```
4. A partir de ese momento, todas las llamadas desatendidas (como `agy -p "..."`) funcionarán sin pedir credenciales.

### Paso 3: Configuración alternativa por API Key (Entornos sin navegador / Headless)
Si estás en una máquina virtual o servidor donde no puedes abrir un navegador web para hacer OAuth:
1. Obtén una clave de API de Google AI Studio o Vertex AI.
2. Define la variable de entorno en tu perfil local ([`profile.local.ps1`](../profile.local.ps1)):
   ```powershell
   $env:GEMINI_API_KEY = "tu-api-key-aqui"
   ```

---

## 5. 🔄 Cómo Cambiar de Proveedor en el Futuro

Si en el futuro deseas cambiar `agy` por otro servicio (como Ollama local o una API de OpenAI/Azure):

1. En tu sesión o en [`profile.local.ps1`](../profile.local.ps1), cambia la variable de proveedor:
   ```powershell
   $global:AIProvider = "ollama"  # o "openai"
   ```
2. En [`profile.d/25-ai.ps1`](../profile.d/25-ai.ps1), la función `Invoke-AICompletion` incluye una rama `elseif` donde puedes añadir llamadas REST directas con `Invoke-RestMethod`:

### Ejemplo para Ollama Local (Llama 3 / Mistral / Qwen)
```powershell
elseif ($global:AIProvider -ieq "ollama") {
    $body = @{
        model  = "qwen2.5-coder"
        prompt = "$SystemInstruction`n`n$Prompt"
        stream = $false
    } | ConvertTo-Json

    $resp = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post -Body $body -ContentType "application/json"
    return $resp.response.Trim()
}
```

### Ejemplo para OpenAI / Azure OpenAI
```powershell
elseif ($global:AIProvider -ieq "openai") {
    $headers = @{ "Authorization" = "Bearer $env:OPENAI_API_KEY" }
    $body = @{
        model = "gpt-4o-mini"
        messages = @(
            @{ role = "system"; content = $SystemInstruction },
            @{ role = "user"; content = $Prompt }
        )
    } | ConvertTo-Json

    $resp = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Headers $headers -Body $body -ContentType "application/json"
    return $resp.choices[0].message.content.Trim()
}
```
