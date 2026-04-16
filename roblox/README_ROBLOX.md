# Guía de Instalación — EduVerse en Roblox Studio

## Arquitectura de Scripts

```
Roblox Studio
├── ServerScriptService/          ← Scripts del SERVIDOR (no visibles al jugador)
│   ├── EduVerseRenderer          ← Polling al backend, renderiza la escena 3D
│   └── QuizManager               ← Valida respuestas, lleva puntaje
└── StarterPlayerScripts/         ← Scripts del CLIENTE (se ejecutan en cada jugador)
    ├── QuizUI                    ← Interfaz de preguntas (ScreenGui)
    └── EduVerseHUD               ← HUD con tema activo y botón de quiz
```

> **Importante:** Los archivos `.client.lua` van en **StarterPlayerScripts**.  
> Los archivos `.server.lua` van en **ServerScriptService**.

---

## Paso 1 — Publicar el Juego

1. En Roblox Studio, abre un nuevo Baseplate.
2. **File → Publish to Roblox** → Ponle nombre `EduVerse Test`.

## Paso 2 — Habilitar HTTP

1. **File → Experience Settings → Security**
2. Activa **Allow HTTP Requests** (verde).
3. **Save**.

## Paso 3 — Instalar Scripts del Servidor (ServerScriptService)

En el panel **Explorer** → Clic derecho en **ServerScriptService** → **Insert Object → Script**

Repite para cada script:

| Nombre en Studio | Archivo fuente |
|---|---|
| `EduVerseRenderer` | `roblox/src/EduVerseRenderer.server.lua` |
| `QuizManager` | `roblox/src/QuizManager.server.lua` |

Para cada uno: borra el `print("Hello world!")` y pega el contenido del archivo correspondiente.

## Paso 4 — Instalar Scripts del Cliente (StarterPlayerScripts)

En el panel **Explorer** → Clic derecho en **StarterPlayerScripts** → **Insert Object → LocalScript**

| Nombre en Studio | Archivo fuente |
|---|---|
| `QuizUI` | `roblox/src/QuizUI.client.lua` |
| `EduVerseHUD` | `roblox/src/EduVerseHUD.client.lua` |

## Paso 5 — Verificar y Jugar

1. Asegúrate de que el backend corre: `uvicorn app.main:app --reload --port 8000`
2. Dale a **Play** (F5) en Roblox Studio.
3. Verás el HUD en la esquina superior derecha.

## Paso 6 — Generar un Taller

1. Abre en tu navegador: [http://localhost:8000/docs](http://localhost:8000/docs)
2. `POST /workshop/generate` → `topic: "sistema solar"` → **Execute**
3. En ≤ 5 segundos:
   - Los objetos aparecen animados en el mundo
   - Se muestra una notificación verde deslizante
   - El quiz se abre automáticamente

---

## Flujo de Comunicación

```
[Backend FastAPI]
        │  GET /workshop/current (cada 5s)
        ▼
[EduVerseRenderer] ──→ Renderiza objetos 3D
        │              Guarda quiz en ReplicatedStorage
        │              Dispara RemoteEvent "EduVerse_WorkshopLoaded"
        ▼
[EduVerseHUD]      ──→ Actualiza tema/sesión en pantalla
[QuizUI]           ──→ Carga preguntas, muestra quiz

[Jugador responde] ──→ RemoteEvent "EduVerse_QuizAnswer" → [QuizManager]
[QuizManager]      ──→ Valida respuesta → RemoteEvent "EduVerse_QuizResult"
[QuizUI]           ──→ Muestra feedback verde ✅ o rojo ❌
```

## Sesiones — Rotar Temas

Para volver a un taller anterior, usa el endpoint:
```
POST http://localhost:8000/workshop/sessions/{id}/activate
```

O consulta el historial:
```
GET http://localhost:8000/workshop/sessions
```
