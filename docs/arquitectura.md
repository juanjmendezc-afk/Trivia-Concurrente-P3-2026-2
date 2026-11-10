# Arquitectura — Trivia Concurrente

> Diseño acordado del proyecto. Se construye sección por sección.
> Fuentes: `docs/enunciado-resumen.md` (enunciado del proyecto) y `docs/convenciones-profesor.md` (guías 06–12).

| # | Sección | Estado |
|---|---|---|
| 1 | Vista general | ✅ Aprobada |
| 2 | Módulos | ✅ Aprobada |
| 3 | Formatos de datos | ✅ Aprobada |
| 4 | Mensajes | ✅ Aprobada |
| 5 | Flujo de una partida | ✅ Aprobada |
| 6 | Errores | ✅ Aprobada |
| 7 | Tareas | ✅ Aprobada |
| 8 | Reparto | ✅ Aprobada |

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
- `connect` → `{:ok, %{usuario: "pedro", registrado: true}}` (`registrado: false` si el usuario ya existía)
- `disconnect` → `{:ok, %{usuario: "pedro"}}`
- `add_bot` → `{:ok, "bot_1"}`
- `score` → `{:ok, %{puntaje: 120, partidas: 6, por_tema: %{"historia" => %{puntaje: 75, nivel: :intermedio}}}}`

### ② Servidor → resto del servidor (interno)

- **Gestores y Persistencia:** mensajes estilo guía 12, `{:accion, remitente, datos}` → respuesta al remitente.
- **Partida** (GenServer): `GenServer.call(pid_partida, {:add_bot, :facil})`, `{:start_game}`, `{:responder, "pedro", "B"}`, `{:abandonar, "pedro"}`.
- La Partida, al arrancar, envía `{:partida_iniciada, id, self()}` al `GestorPartidas`. Si el `id` ya existía con otro PID → hubo reinicio → el gestor actualiza el PID y avisa al creador.
- Al terminar, la Partida llama `Persistencia.guardar_resultado(linea)` con la línea **sin fecha** (`P-1001|historia|basico|pedro|pedro:45,bot_1:30`); `Persistencia` le antepone la fecha y hora de Colombia (decisión de T2). También envía `{:partida_terminada, id}` al `GestorPartidas` (libera a los jugadores).

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

---

## 5. Flujo de una partida

### A. Arranque

1. **Servidor:** `iex --sname servidor -S mix` → `Trivia.Servidor.iniciar()`
   - Arranca `Persistencia`, que carga `users.json` y `questions.json`.
   - Arranca `GestorJugadores` (con los usuarios), `GestorPartidas` (con el banco de preguntas en memoria) y `SupervisorPartidas`.
   - Registra el proceso `Servidor` como `:servidor`.
2. **Cliente:** `iex --sname pedro -S mix` → `Trivia.Cliente.iniciar()`
   - Se conecta al nodo `servidor`. Si falla → "servidor no disponible".
   - Arranca su `Receptor` y queda esperando comandos.

### B. `connect pedro 1234`

- `GestorJugadores` verifica en orden: no empieza por `bot_`, no está ya conectado, la clave coincide.
- Si el usuario no existe, lo registra y `Persistencia` actualiza `users.json`.
- El `Servidor` empieza a vigilar el proceso del cliente para detectar si se cierra (ver G).

### C. `create_game tema=historia preguntas=5 tiempo=15`

1. Verifica sesión y que el jugador no esté en otra partida.
2. Calcula el nivel del jugador en el tema: `Persistencia` entrega las líneas del historial → `Estadisticas` suma sus puntajes en el tema → `Nivel` lo convierte.
3. `GestorPartidas` verifica que el tema exista y que alcancen las preguntas de cada nivel.
4. Genera el id (`P-1001`, `P-1002`… con un contador) y pide a `SupervisorPartidas` arrancar la `Partida` con: id, creador, tema, nivel, número de preguntas, tiempo, preguntas del tema y PID del receptor.
5. La Partida nace en `esperando`, con solo el creador, y envía `{:partida_iniciada, id, self()}` a `GestorPartidas`.
6. El cliente recibe `{:ok, %{id: "P-1001", nivel: :basico}}`.

### D. `add_bot` y `start_game`

- **`add_bot`:** si está `esperando` y hay menos de 4 jugadores → crea un proceso `Bot` enlazado (`bot_1`, `bot_2`, …) y lo agrega como participante.
- **`start_game`:** si hay al menos 2 bots → `BancoPreguntas` sortea según el reparto del nivel → pasa a `en_curso` → abre la ronda 1.

### E. Una ronda

1. **Abrir:** guarda la hora de inicio, envía `{:pregunta, ...}` a todos (receptores y bots) y programa `{:fin_tiempo, numero_ronda}` para dentro de `tiempo` segundos.
2. **Llegan respuestas** (`answer` del humano, `{:responder, ...}` de los bots):
   - sin ronda abierta o letra distinta de A–D → rechazo;
   - el jugador ya respondió → se ignora con aviso;
   - válida → se guarda la letra y la **hora de llegada** (para la bonificación).
3. **Cerrar** cuando todos respondieron **o** llega `{:fin_tiempo, n}` (lo primero):
   - `Puntaje` calcula los puntos de cada jugador;
   - envía `{:cierre_ronda, ...}` a todos;
   - pausa de 3 segundos → siguiente ronda.
4. Un `{:fin_tiempo, n}` que llega tarde (la ronda ya cerró) se descarta comparando el número de ronda con el operador pin `^` (guía 12).

### F. Fin de la partida

1. Tras la última ronda: ranking y ganador(es); empate = ganador compartido.
2. Envía la línea a `Persistencia` → se agrega a `results.log`.
3. Envía `{:fin_partida, ...}` a todos. Los bots terminan su bucle al recibirlo.
4. Envía `{:partida_terminada, id}` a `GestorPartidas` → libera al jugador.
5. La Partida termina **normalmente** → el supervisor no la reinicia (`:transient`).

### G. Abandono (`leave_game`, `disconnect` o se cierra el cliente)

- **`esperando` y sale el creador:** se cancela, `{:aviso, ...}`, **no** se registra.
- **`en_curso`:** termina de inmediato con los puntajes hasta ese momento, **se registra** en el historial y se envía `{:fin_partida, ...}`.
- Si el cliente se cierra de golpe, el `Servidor` lo detecta (lo está vigilando), cierra la sesión y aplica lo anterior.

### H. Reinicio (la partida falla)

1. `SupervisorPartidas` la reinicia con los mismos datos de arranque: `esperando`, solo el creador, sin bots ni puntajes.
2. Los bots mueren con ella (están enlazados).
3. La partida nueva envía `{:partida_iniciada, id, nuevo_pid}` → `GestorPartidas` ve que el PID cambió, lo actualiza y envía al Receptor del creador: *"Tu partida falló y se reinició sin progreso. Agrega bots y ejecuta start_game."*
4. No se registra nada en el historial.

---

## 6. Errores

El servidor responde `{:error, :atomo}`. El **cliente** traduce el átomo a texto y lo imprime por la salida de errores (`Util.imprimir(msg, :error)`, guía 06). Ningún error tumba la partida, el servidor ni otros clientes: se informa y se sigue funcionando.

| # enunciado | Átomo | Mensaje al jugador |
|---|---|---|
| 1 | `:sin_sesion` | Primero inicia sesión: connect <usuario> <clave> |
| 2 | `:clave_incorrecta` | Clave incorrecta |
| 3 | `:ya_conectado` | Ese usuario ya tiene sesión abierta en otro cliente |
| 4 | `:usuario_reservado` | Los usuarios que empiezan por bot_ están reservados |
| 5 | `:servidor_no_disponible` | No se pudo conectar con el servidor |
| 6 | `:ya_en_partida` | Ya estás en una partida |
| 7 | `:tema_inexistente` | Ese tema no existe |
| 7 | `:preguntas_insuficientes` | No hay preguntas suficientes para esa partida |
| 8 | `:sin_partida` | No estás en ninguna partida |
| 9 | `:partida_llena` | La partida está llena |
| 9 | `:partida_iniciada` | La partida ya empezó |
| 10 | `:bots_insuficientes` | Se necesitan al menos 2 bots para iniciar |
| 11 | `:letra_invalida` | Responde A, B, C o D |
| 11 | `:sin_ronda_abierta` | No hay una pregunta abierta |
| extra | `:respuesta_repetida` | Ya respondiste esta pregunta (solo cuenta la primera) |
| extra | `:sesion_abierta` | Ya tienes una sesión abierta; usa disconnect antes de conectar otro usuario |
| extra | `:comando_invalido` | Comando no reconocido |
| extra | `:parametros_invalidos` | Revisa los parámetros del comando (por ejemplo, preguntas de 1 a 10 o tiempo mayor a 0) |

---

## 7. Tareas

Cada tarea = una sesión de Claude Code. Al terminar: `mix test` en verde, entrada en `docs/progreso.md` y línea en `docs/uso-ia.md`.

### Representación de una pregunta en memoria

`Persistencia` convierte cada pregunta del JSON a un mapa con claves átomo:

```elixir
%{tema: "historia", nivel: :basico, enunciado: "...",
  opciones: %{"A" => "...", "B" => "...", "C" => "...", "D" => "..."},
  respuesta: "A"}
```

### Tareas puras (compañeros) — contratos fijos

| Tarea | Módulo / archivo | Funciones | Prueba enunciado |
|---|---|---|---|
| **P1** | `Trivia.Nivel` | `calcular(puntaje)` → `:basico` \| `:intermedio` \| `:avanzado` · `reparto(nivel, total)` → `%{basico: n, intermedio: n, avanzado: n}` | 7 |
| **P2** | `data/questions.json` | 96 preguntas: 4 temas × 3 niveles × 8, formato de la sección 3 | — |
| **P3** | `Trivia.BancoPreguntas` | `sortear(preguntas_del_tema, nivel, total)` → `{:ok, lista_ordenada}` \| `{:error, :preguntas_insuficientes}` | 2 |
| **P4** | `Trivia.Puntaje` | `calcular(nivel_pregunta, resultado, ms_restantes, tiempo_pregunta)` → entero; `resultado` es `:correcta` \| `:incorrecta` \| `:sin_responder` | 1 |
| **P5** | `Trivia.Estadisticas` | `parsear_linea(linea)` · `resumen(lineas, usuario)` → puntaje, partidas y puntaje por tema · `ranking(lineas, tema_o_nil)` → `[{usuario, puntaje}]` ordenado. Ignoran bots. | 5 |
| **P6** | `Trivia.Bot.decidir/4` | Hecha. Pendiente: error como `{:error, :argumentos_invalidos}` | 6 |

Archivos: `lib/trivia/<modulo>.ex` y `test/trivia/<modulo>_test.exs`.
P1 + P3 + P4 + P5 + P6 cubren las 5 pruebas mínimas del enunciado.

### Tareas del núcleo (Juanjo)

| Tarea | Qué | Hito |
|---|---|---|
| **T1** | Limpieza (borrar ejemplo de Mix), dependencia `jason`, carpeta `data/`, `Util` | `mix test` en verde |
| **T2** | `Persistencia` | Carga/guarda usuarios, preguntas e historial |
| **T3** | `GestorJugadores` + `Servidor` (`iniciar/0`, connect/disconnect, vigilar clientes) | |
| **T4** | `Cliente` + `Receptor` (conexión al nodo, comandos, mensajes de error) | **2 consolas: `connect` funciona** |
| **T5** | `GestorPartidas` + `SupervisorPartidas` + `Partida` en espera (create_game, add_bot, leave_game) | Crear partida y agregar bots |
| **T6** | Proceso `Bot` + rondas (start_game, pregunta, answer, temporizador, cierre, fin, historial) | **Partida completa contra 2 bots** |
| **T7** | Abandono y desconexión en curso | |
| **T8** | Reinicio de partidas + aviso al creador | |
| **T9** | `score` y `ranking` | |
| **T10** | Repaso de los 11 errores de punta a punta | Criterios 9–12 |
| **T11** | Integración: todas las pruebas en verde | `mix test` ✅ |
| **T12** | `README.md` + `docs/uso-ia.md` | Entregables |
| **T13** | Ensayo de la demo con los 13 criterios | Listo para entregar |

Si un módulo puro aún no existe cuando se necesita (T5, T6), se usa una versión provisional simple y se reemplaza al integrar.

---

## 8. Reparto y fechas

Entrega: **jueves 12 de noviembre, 11:59 pm** (fecha asumida).

| Quién | Tareas | Fecha límite |
|---|---|---|
| **Daniel** | P1 `Nivel`, P2 `questions.json`, P3 `BancoPreguntas` | **Martes 10 pm** |
| **Samuel** | P4 `Puntaje`, P5 `Estadisticas`, corregir P6 | **Martes 10 pm** |
| **Juanjo** | T1–T4 martes · T5–T6 miércoles · T7–T10 miércoles noche / jueves temprano · T11–T13 jueves | **Jueves 11:59 pm** |
| **Revisión** | Lo que falte o falle de los compañeros lo asume Juanjo | **Miércoles 9 am** |

Reglas para los tres:
- Cada uno toca **solo sus archivos**.
- Trabajar con **GitHub Desktop**: Pull antes de empezar, `mix test` antes de cada push.
