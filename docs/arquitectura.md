# Arquitectura — Trivia Concurrente

> Diseño acordado del proyecto. Se construye sección por sección.
> Fuentes: `docs/enunciado-resumen.md` (enunciado del proyecto) y `docs/convenciones-profesor.md` (guías 06–12).

| # | Sección | Estado |
|---|---|---|
| 1 | Vista general | ✅ Aprobada |
| 2 | Módulos | ✅ Aprobada |
| 3 | Formatos de datos | ✅ Aprobada |
| 4 | Mensajes | ✅ Aprobada |
| 5 | Flujo de una partida | Pendiente |
| 6 | Errores | Pendiente |
| 7 | Tareas | Pendiente |
| 8 | Reparto | Pendiente |

---

## 1. Vista general

```
NODO SERVIDOR   (iex --sname servidor -S mix)
│
├── Servidor ............. recibe las peticiones de los clientes y las reparte
├── GestorJugadores ...... usuarios, sesiones abiertas, score y ranking
├── GestorPartidas ....... qué partida tiene cada jugador; avisa reinicios
├── Persistencia ......... ÚNICO proceso que lee y escribe en data/
└── SupervisorPartidas ... vigila las partidas y reinicia la que falle
     ├── Partida P-1001 ── bot_1, bot_2   (cada bot es su propio proceso)
     └── Partida P-1002 ── bot_1, bot_2, bot_3

NODO CLIENTE   (iex --sname pedro -S mix)   ← uno por jugador
│
├── Cliente .............. lee comandos del teclado y los envía al servidor
└── Receptor ............. recibe notificaciones y las imprime

LÓGICA PURA (sin proceso, fácil de probar):
   Nivel, Puntaje, sorteo de preguntas, decisión del bot, estadísticas del historial
```

### Ideas clave

- **El servidor es el único dueño del estado.** Solo él lee y escribe archivos y conoce las respuestas correctas.
- **Cada partida es un proceso independiente** con sus propios bots. Si una falla, las demás siguen.
- **El cliente no tiene lógica de juego.** Traduce comandos en mensajes y muestra lo que recibe.
- **Dos procesos en el cliente** (enunciado 8.3):
  - `Cliente` se queda bloqueado esperando el teclado.
  - `Receptor` es un bucle `receive` (como la caja de la guía 12) que imprime las notificaciones que llegan sin pedirlas: preguntas, cierre de ronda, ranking final.
  - Al crear la partida, el cliente entrega al servidor el **PID del Receptor**, y la partida envía las notificaciones a ese PID.
- **La lógica pura vive aparte** de los procesos y los archivos, porque las pruebas del enunciado (6 y 7) lo exigen.

---

## 2. Módulos

Todos los módulos van en `lib/trivia/` con el prefijo `Trivia.` (por ejemplo `lib/trivia/partida.ex` → `Trivia.Partida`).

### Decisiones

- **Procesos al estilo de la guía 12** (`spawn` + `loop` + `receive` + `Process.register`). Solo `Partida` es `GenServer` y solo `SupervisorPartidas` es `DynamicSupervisor`, porque el enunciado lo exige (8.4 y 8.5).
- **Arranque manual, nada arranca solo:**
  - Consola del servidor: `iex --sname servidor -S mix` y luego `Trivia.Servidor.iniciar()`.
  - Consola de cada cliente: `iex --sname pedro -S mix` y luego `Trivia.Cliente.iniciar()`.
  - Así un cliente nunca levanta su propio servidor.

### Lado servidor

| Módulo | Tipo | Responsabilidad |
|---|---|---|
| `Servidor` | Proceso | Puerta de entrada. Recibe las peticiones de los clientes, verifica la sesión y las pasa al gestor que corresponde. Si un cliente desaparece, avisa para cerrar su sesión. `iniciar/0` arranca todo el lado servidor. |
| `GestorJugadores` | Proceso | Usuarios registrados, sesiones abiertas (una por usuario), `connect`/`disconnect`, `score` y `ranking`. |
| `GestorPartidas` | Proceso | Guarda el banco de preguntas en memoria, crea partidas, sabe en qué partida está cada jugador y detecta reinicios de partidas para avisar al creador. |
| `SupervisorPartidas` | DynamicSupervisor | Arranca cada partida y la reinicia si falla (`restart: :transient`). |
| `Partida` | GenServer | Una partida: jugadores, bots, rondas, temporizador y puntajes. Notifica a los Receptores y a los bots. Al terminar, envía la línea del historial a `Persistencia`. |
| `Bot` | Proceso + función pura | El proceso recibe cada pregunta y programa su respuesta. La función pura `decidir` elige la letra y el retardo. |
| `Persistencia` | Proceso | **Único** que lee y escribe en `data/`: usuarios, preguntas e historial. |

### Lógica pura (sin procesos ni archivos)

| Módulo | Responsabilidad | Prueba del enunciado |
|---|---|---|
| `Nivel` | Nivel según puntaje (umbrales 60 y 180) y cantidad de preguntas por nivel (reparto). | 7 |
| `BancoPreguntas` | Filtrar por tema, verificar suficiencia, sortear según el reparto y ordenar de menor a mayor nivel. | 2 |
| `Puntaje` ➕ | Puntos de una ronda: correcta, incorrecta o sin responder, más la bonificación por rapidez. | 1 |
| `Estadisticas` ➕ | Desde las líneas del historial: puntaje y partidas por jugador, puntaje y nivel por tema, ranking. Ignora bots. | 5 |

➕ Agregados por nosotros: el enunciado ubica esa lógica dentro de otros módulos, pero sus pruebas piden calcularla sin procesos ni archivos.

### Lado cliente

| Módulo | Tipo | Responsabilidad |
|---|---|---|
| `Cliente` | Proceso | `iniciar/0`: se conecta al nodo servidor, arranca el Receptor y entra al bucle leer comando → enviar → mostrar respuesta. |
| `Receptor` | Proceso | Bucle `receive` que imprime las notificaciones (preguntas, cierre de ronda, ranking final, avisos). |
| `Util` | Lógica pura | `leer` e `imprimir` como en la guía 06; errores por la salida de errores. |

---

## 3. Formatos de datos

Todos los archivos van en `proyecto_trivia/data/`. Solo `Persistencia` los toca. La ruta se arma con `Path.join` y `__DIR__` (guía 11).

**Temas del banco de preguntas:** `historia`, `ciencia`, `geografia`, `programacion`.

### `data/users.json` — usuarios

```json
[
  {"usuario": "pedro", "clave": "1234"},
  {"usuario": "carlos", "clave": "abcd"}
]
```

- Solo usuario y clave (texto plano). Nada de estadísticas.
- Al cargarlo se convierte en un mapa `%{"pedro" => "1234", ...}`.
- Si no existe (primer arranque) → mapa vacío.

### `data/questions.json` — banco de preguntas

```json
[
  {
    "tema": "historia",
    "nivel": "basico",
    "enunciado": "¿En qué año llegó Colón a América?",
    "opciones": {"A": "1492", "B": "1500", "C": "1810", "D": "1453"},
    "respuesta": "A"
  }
]
```

- Mínimo **4 temas × 24 preguntas** (8 por nivel) = **96 preguntas**.
- `tema` en minúscula y sin espacios; `nivel` ∈ `basico`, `intermedio`, `avanzado`; `respuesta` ∈ `A`, `B`, `C`, `D`.
- Se carga una vez al arrancar y queda en memoria (en `GestorPartidas`). Nunca se envía a los clientes.

### `data/results.log` — historial (una línea por partida)

```
2026-11-12 20:15:03|P-1001|historia|basico|pedro|pedro:45,bot_1:30,bot_2:-5
2026-11-12 20:31:47|P-1002|ciencia|intermedio|bot_2|carlos:20,bot_1:15,bot_2:38
```

| Campo | Ejemplo | Nota |
|---|---|---|
| fecha y hora | `2026-11-12 20:15:03` | La guía 11 pide fecha en cada línea del histórico |
| id | `P-1001` | |
| tema | `historia` | |
| nivel | `basico` | Nivel del creador al crear la partida |
| ganador(es) | `pedro` o `pedro,bot_1` | Empate → separados por coma |
| puntajes | `pedro:45,bot_1:30,bot_2:-5` | Todos los jugadores, bots incluidos |

- Dos niveles de separadores (como el CSV de la Pokédex, guía 11): `|` entre campos, `,` entre jugadores, `:` entre nombre y puntaje.
- Se escribe con `[:append]`; se lee con streams.
- Las estadísticas se calculan desde aquí, ignorando nombres que empiezan por `bot_`.
- Se registran las partidas terminadas y las abandonadas (con los puntajes hasta ese momento). **No** se registran las canceladas antes de iniciar ni las que se reiniciaron.

### Qué se sube a GitHub

- `data/questions.json`: **sí** (es entregable).
- `data/users.json` y `data/results.log`: **no** (están en `.gitignore`; se generan solos).

---

## 3. Formatos de datos

Todos los archivos van en `proyecto_trivia/data/`. Solo `Persistencia` los lee y escribe. La ruta se arma con `Path.join` y `__DIR__` (guía 11).

### `data/users.json` — usuarios

```json
[
  {"usuario": "pedro", "clave": "1234"},
  {"usuario": "carlos", "clave": "abcd"}
]
```

- Solo usuario y clave en texto plano (enunciado). Nada de estadísticas.
- Al cargarlo se convierte en un mapa `%{"pedro" => "1234", ...}`.
- Si no existe (primer arranque), se empieza con un mapa vacío.

### `data/questions.json` — banco de preguntas

```json
[
  {
    "tema": "historia",
    "nivel": "basico",
    "enunciado": "¿En qué año llegó Colón a América?",
    "opciones": {"A": "1492", "B": "1500", "C": "1810", "D": "1453"},
    "respuesta": "A"
  }
]
```

- Temas: **`historia`, `ciencia`, `geografia`, `programacion`**.
- **8 preguntas por nivel en cada tema** → 24 por tema → **96 en total**.
- `tema` en minúscula y sin espacios; `nivel` es `basico`, `intermedio` o `avanzado`; `respuesta` es una letra de `A` a `D`.

### `data/results.log` — historial (una línea por partida)

```
2026-11-12 20:15:03|P-1001|historia|basico|pedro|pedro:45,bot_1:30,bot_2:-5
2026-11-12 20:31:47|P-1002|ciencia|intermedio|bot_2|carlos:20,bot_1:15,bot_2:38
```

| Campo | Ejemplo | Nota |
|---|---|---|
| fecha y hora | `2026-11-12 20:15:03` | Fecha en cada línea del histórico (guía 11) |
| id | `P-1001` | |
| tema | `historia` | |
| nivel | `basico` | Nivel del creador al crear la partida |
| ganador(es) | `pedro` o `pedro,bot_1` | Empate: separados por coma |
| puntajes | `pedro:45,bot_1:30,bot_2:-5` | Todos los jugadores, bots incluidos |

- Dos niveles de separadores (como el CSV de la Pokédex, guía 11): `|` entre campos, `,` entre jugadores, `:` entre nombre y puntaje.
- Se escribe con `[:append]` y se lee con streams.
- **Única fuente de estadísticas.** Puntaje de un jugador en un tema = suma de sus puntajes en las líneas de ese tema. Los nombres que empiezan por `bot_` se ignoran.
- Se registran las partidas terminadas y las abandonadas (con los puntajes hasta ese momento). No se registran las canceladas antes de iniciar ni las reiniciadas.

### Qué va al repositorio

- `data/questions.json`: **sí** (entregable).
- `data/users.json` y `data/results.log`: **no**, se generan solos (están en `.gitignore`).

---

## 4. Mensajes

Estilo de la guía 12: tuplas con un átomo de acción y el PID del remitente cuando se espera respuesta.

```
① Cliente   ──petición──→  Servidor   ──→ respuesta al Cliente
② Servidor  ──────────→  Partida / Gestores / Persistencia   (interno)
③ Partida   ──notificación──→  Receptores y Bots
④ Bot       ──respuesta──→  Partida   (igual que un humano)
```

### ① Cliente → Servidor (peticiones)

El cliente envía a `{:servidor, nodo_servidor}` y espera con `receive ... after 5000`. Sin respuesta → error "servidor no disponible".

| Comando | Mensaje |
|---|---|
| `connect pedro 1234` | `{:connect, pid_cliente, "pedro", "1234"}` |
| `disconnect` | `{:disconnect, pid_cliente}` |
| `create_game tema=historia preguntas=5 tiempo=15` | `{:create_game, pid_cliente, "historia", 5, 15, pid_receptor}` |
| `add_bot facil` | `{:add_bot, pid_cliente, :facil}` |
| `start_game` | `{:start_game, pid_cliente}` |
| `answer B` | `{:answer, pid_cliente, "B"}` |
| `leave_game` | `{:leave_game, pid_cliente}` |
| `score` | `{:score, pid_cliente}` |
| `ranking` / `ranking historia` | `{:ranking, pid_cliente, nil}` / `{:ranking, pid_cliente, "historia"}` |

- **El servidor identifica al jugador por el PID del cliente.** En `connect` guarda `pid_cliente → usuario`; los demás comandos no envían el usuario. PID sin sesión → `{:error, :sin_sesion}`.
- `create_game` incluye el **PID del Receptor** (enunciado 8.3).

**Respuesta** (siempre la misma forma): `{:respuesta, {:ok, datos}}` o `{:respuesta, {:error, :motivo}}`. Ejemplos:

- `create_game` → `{:ok, %{id: "P-1001", nivel: :basico}}`
- `add_bot` → `{:ok, "bot_1"}`
- `score` → `{:ok, %{puntaje: 120, partidas: 6, por_tema: %{"historia" => %{puntaje: 75, nivel: :intermedio}}}}`

### ② Servidor → resto del servidor (interno)

- **Gestores y Persistencia:** mensajes estilo guía 12, `{:accion, remitente, datos}` → respuesta al remitente.
- **Partida** (GenServer): `GenServer.call(pid_partida, {:add_bot, :facil})`, `{:start_game}`, `{:responder, "pedro", "B"}`, `{:abandonar, "pedro"}`.
- La Partida, al arrancar, envía `{:partida_iniciada, id, self()}` al `GestorPartidas`. Si el `id` ya existía con otro PID → hubo reinicio → el gestor actualiza el PID y avisa al creador.
- Al terminar, la Partida envía `{:guardar_resultado, linea}` a `Persistencia` y `{:partida_terminada, id}` al `GestorPartidas` (libera a los jugadores).

### ③ Partida → Receptores y Bots (notificaciones)

Bots y Receptores reciben **exactamente las mismas** notificaciones.

| Mensaje | Cuándo | Contenido |
|---|---|---|
| `{:pregunta, datos}` | Abre una ronda | número, total, enunciado, opciones A–D, tiempo. **Sin respuesta ni nivel.** |
| `{:cierre_ronda, datos}` | Todos respondieron o venció el tiempo | respuesta correcta, puntos de la ronda y acumulado de cada jugador |
| `{:fin_partida, datos}` | Última ronda o abandono | id, tema, nivel, ranking (posición, jugador, puntaje) y ganador(es) |
| `{:aviso, texto}` | Reinicio, cancelación, etc. | Texto para mostrar |

### ④ Bot → Partida

1. El bot recibe `{:pregunta, ...}` igual que un cliente.
2. Pide a su partida el nivel y la respuesta de la pregunta actual: `Partida.datos_pregunta(pid_partida)`. Estos datos nunca van a los clientes.
3. Llama a `Bot.decidir(...)` → `{letra, retardo_ms}`.
4. Programa `Process.send_after(self(), {:responder, letra}, retardo_ms)`.
5. Al recibir ese mensaje, envía `{:responder, "bot_1", letra}` a la partida: **el mismo camino que un humano** (el enunciado prohíbe caminos especiales para bots).
