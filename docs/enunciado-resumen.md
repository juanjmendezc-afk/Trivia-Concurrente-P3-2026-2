# Trivia Concurrente — resumen técnico del enunciado

> Fuente oficial: https://caflorezvi.github.io/guias-programacion3/proyecto20262.html
> Este es un resumen de trabajo. Ante cualquier duda, **manda el enunciado original**.

---

## Idea general

Juego de preguntas por consola. Cada jugador humano crea una partida y compite contra 2–3 bots.
Un **servidor central** (nodo Elixir) tiene todo el estado; los **clientes** (otro nodo cada uno) solo envían comandos y muestran lo que reciben.
Varias partidas corren al mismo tiempo, cada una en su propio `GenServer` bajo un `DynamicSupervisor`.

## Comandos del cliente

| Comando | Tipo | Qué hace |
|---|---|---|
| `connect <usuario> <clave>` | petición | Inicia sesión; si el usuario no existe, lo registra |
| `disconnect` | — | Cierra sesión (si hay partida en curso → regla de abandono) |
| `create_game tema=<t> preguntas=<n> tiempo=<s>` | petición | Crea partida, deja al creador dentro, responde id y nivel |
| `add_bot <facil\|dificil>` | petición | Agrega un bot (`bot_1`, `bot_2`, …) |
| `start_game` | petición | Inicia (requiere ≥ 2 bots) |
| `answer <letra>` | petición | Responde la ronda abierta (A–D) |
| `leave_game` | — | Abandona la partida |
| `score` | petición | Puntaje acumulado, partidas jugadas y, por tema, puntaje y nivel |
| `ranking [tema]` | petición | Ranking histórico global o filtrado por tema |

**Notificaciones** (el servidor las envía sin que se pidan): enunciado de cada pregunta, cierre de ronda, ranking final, aviso de reinicio. El cliente debe poder recibirlas mientras espera al teclado.

## Reglas de jugadores

- Usuario único, sin espacios; clave en texto plano.
- Una sola sesión por usuario (rechazar si ya está conectado en otro cliente).
- Prefijo `bot_` reservado → rechazar.
- No se guardan estadísticas en `users.json`: todo se recalcula desde `results.log`.

## Reglas de partida

- 3 a 4 jugadores (creador + bots). Mínimo 2 bots para iniciar.
- `add_bot` rechazado si hay 4 jugadores o la partida ya inició.
- Un jugador solo puede estar en una partida.
- El tema debe existir y tener preguntas suficientes por nivel.
- Si el creador abandona antes de iniciar → partida cancelada.
- Estados: `esperando` → `en_curso` → `finalizada`.
- Id de ejemplo: `P-1001`.

## Nivel por tema

Puntaje acumulado del jugador en ese tema (desde el historial):

| Puntaje | Nivel |
|---|---|
| < 60 (o nunca jugó) | `basico` |
| 60 – 179 | `intermedio` |
| ≥ 180 | `avanzado` |

Puede bajar con puntajes negativos. Se fija al crear la partida.

## Reparto de preguntas (% básico / intermedio / avanzado)

| Nivel del jugador | Básico | Intermedio | Avanzado |
|---|---|---|---|
| `basico` | 70 | 30 | 0 |
| `intermedio` | 20 | 60 | 20 |
| `avanzado` | 0 | 30 | 70 |

- Para los **dos niveles distintos** al del jugador: `trunc(total * porcentaje / 100)`.
- El resto son del nivel del jugador.
- Ej.: 5 preguntas, `basico` → 1 intermedia + 4 básicas. 10 preguntas, `avanzado` → 3 intermedias + 7 avanzadas.
- Sorteo al iniciar: del tema, sin repetir. Orden final: de menor a mayor nivel; dentro del mismo nivel, el orden del sorteo. Todos reciben las mismas preguntas en el mismo orden.

## Ronda

1. Se envía a todos a la vez: enunciado, 4 opciones y tiempo.
2. Cada jugador responde por su cuenta.
3. Cierra cuando todos respondieron **o** vence el tiempo (lo primero).
4. Se anuncia respuesta correcta, puntos de la ronda y acumulado de cada uno.
5. Pausa de 3 s (sin ronda abierta).

Respuestas:
- Solo cuenta la **primera** por jugador; las siguientes se ignoran con aviso.
- Fuera de ronda abierta → rechazo.
- Letra distinta de A/B/C/D → rechazo **sin** consumir la respuesta.

## Puntaje

| | Básico | Intermedio | Avanzado |
|---|---|---|---|
| Correcta | +10 | +15 | +20 |
| Incorrecta | −5 | −8 | −10 |
| Sin responder | 0 | 0 | 0 |

Bonificación (solo correctas, 0–5):
`bonificacion = trunc(5 * segundos_restantes / tiempo_pregunta)` → `puntos = puntos_nivel + bonificacion`.
`segundos_restantes` se mide cuando la respuesta **llega a la partida** (hay que registrar inicio de ronda y llegada de cada respuesta).
Ej. con 15 s: responde al segundo 1 → +4; al 4 → +3; al 9 → +2; al 14 → +0.

## Abandono en curso

`leave_game`, `disconnect` o cierre del cliente → la partida termina ya, se registra con los puntajes hasta ese momento.

## Bots

- Viven en el servidor, cada uno en su propio proceso, enlazado a la partida.
- Reciben las mismas notificaciones que un cliente (registran su PID en la partida). **Sin caminos especiales** dentro de la partida.
- Programan su respuesta con `Process.send_after`.

| | Acierto básica | intermedia | avanzada | Responde entre |
|---|---|---|---|---|
| Fácil | 40 % | 30 % | 20 % | 40 % y 90 % del tiempo |
| Difícil | 80 % | 70 % | 60 % | 10 % y 40 % del tiempo |

- Si falla, elige al azar una de las 3 incorrectas.
- Obtienen nivel y respuesta correcta de la partida (esos datos nunca van a los clientes).
- Aparecen en el ranking de la partida, **no** en `users.json` ni en el ranking histórico.

## Reinicio de partidas

- `DynamicSupervisor` con `restart: :transient`.
- Se reinicia con los mismos argumentos (id, creador, tema, preguntas, tiempo, PID del cliente) → vuelve a `esperando` con solo el creador, sin bots ni puntajes. No se registra nada.
- Al arrancar, la partida se reporta al gestor con **`cast`** (`id` + PID). Si el id ya existía con otro PID → el gestor actualiza el PID y avisa al creador (agregue bots y ejecute `start_game` de nuevo).

## Arquitectura

- Servidor: único dueño del estado, único que lee/escribe archivos, carga `questions.json` al arrancar.
- **Todas las escrituras de archivos pasan por un único proceso.**
- El servidor monitorea a los clientes; si uno desaparece, cierra su sesión y aplica la regla de abandono.
- Cliente: un nodo por jugador, sin lógica de juego, nunca levanta su propio servidor, nunca toca `data/`. Separa lectura de teclado y recepción de notificaciones.
- Arranque de referencia:
  ```
  iex --sname servidor -S mix
  iex --sname pedro -S mix
  iex --sname carlos -S mix
  ```

### Módulos sugeridos (`lib/trivia/`)

| Lado | Archivo | Responsabilidad |
|---|---|---|
| Servidor | `servidor.ex` | Recibe y enruta peticiones |
| Servidor | `gestor_jugadores.ex` | Registro, sesiones, puntajes, ranking |
| Servidor | `gestor_partidas.ex` | Crear/ubicar partidas, aviso de reinicio |
| Servidor | `partida.ex` | `GenServer` de una partida |
| Servidor | `supervisor_partidas.ex` | `DynamicSupervisor` |
| Servidor | `bot.ex` | Proceso bot |
| Servidor | `banco_preguntas.ex` | Carga y sorteo |
| Servidor | `nivel.ex` | Nivel y reparto |
| Servidor | `persistencia.ex` | Archivos |
| Cliente | `cliente.ex` | Consola y peticiones |
| Cliente | `receptor.ex` | Notificaciones |

Los módulos del cliente **nunca** llaman directamente a los del servidor (solo por mensajes/`GenServer.call` remoto).

## Persistencia (`data/`, solo en el servidor)

- `users.json`: usuario y clave.
- `questions.json` (semilla, la hacemos nosotros): ≥ 4 temas × 8 preguntas por nivel (24 por tema). Campos: tema (minúscula, sin espacios), nivel, enunciado, 4 opciones A–D, respuesta.
- `results.log`: una línea por partida con fecha, id, tema, nivel, ganador y puntaje de cada jugador. Se recorre con **streams**.
- El formato exacto de cada archivo **lo definimos nosotros** (el enunciado no lo fija).
- Dependencia `jason`.

## Errores propios (no deben tumbar nada)

1. Comando sin sesión.
2. Clave incorrecta.
3. Usuario ya conectado en otro cliente.
4. Usuario con prefijo `bot_`.
5. Servidor no disponible al conectar.
6. `create_game` estando ya en partida.
7. Tema inexistente o sin preguntas suficientes por nivel.
8. `add_bot`/`start_game` sin estar en partida.
9. `add_bot` con partida llena o iniciada.
10. `start_game` con menos de 2 bots.
11. Respuesta con letra inválida o fuera de ronda.

Regla: informar y seguir funcionando.

## Pruebas ExUnit (mínimo 5 de 7)

1. Puntaje de ronda (3 niveles × correcta/incorrecta/sin responder, bonificación en varios momentos y con 2 valores de tiempo).
2. Sorteo (cantidad, tema, sin repetidos, reparto por nivel, orden).
3. Validación de respuestas (solo la primera, letra inválida, fuera de ronda).
4. Armado de partida (`add_bot` lleno/iniciado, `start_game` con < 2 bots).
5. Estadísticas desde historial (ignora bots).
6. Decisión de bot (letra válida y retardo en rango) → **separar la decisión del proceso**.
7. Nivel del jugador (umbrales 59/60/179/180, negativo, tema nunca jugado) → **el cálculo recibe líneas, no abre el archivo**.

## Criterios de aceptación (sustentación)

1. Servidor arranca y espera clientes.
2. Un jugador conecta, agrega 2 bots y juega una partida completa.
3. Dos clientes distintos juegan a la vez (temas y tiempos distintos) sin interferencia.
4. Preguntas llegan a todos a la vez; el temporizador cierra la ronda.
5. Puntaje y ranking final correctos.
6. Reparto según nivel; si sube de nivel, la siguiente partida del tema usa el nuevo reparto.
7. Bots responden a tiempo, aciertan según dificultad, puntúan, salen en el ranking de partida y no en el histórico.
8. Clientes no acceden a `data/`.
9. Cerrar un cliente en curso termina su partida y el servidor sigue.
10. Usuarios e historial persisten tras reiniciar el servidor.
11. Ranking global y por tema coherentes con el historial.
12. Los errores de la lista no tumban el servidor.
13. `mix test` pasa.

## Entregables

1. Repo Git con el proyecto Mix y `data/questions.json`.
2. `README.md`: integrantes, compilación, cómo levantar servidor y clientes, comandos.
3. Documentación del uso de IA (herramientas y propósito).
4. Pruebas ExUnit (≥ 5 de 7) en verde.
5. Sustentación en vivo: servidor + ≥ 2 clientes jugando a la vez, cada uno con su partida y bots.

## Extensión opcional (sección 15)

`list_games` y `join_game <id>` para que varios humanos jueguen la misma partida. **No resta nota si no se hace.** Decidir más adelante.
