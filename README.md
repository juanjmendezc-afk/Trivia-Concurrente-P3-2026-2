# Trivia concurrente

Proyecto final de Programación III. Cada humano juega una partida contra dos o tres bots. Un nodo servidor administra usuarios, partidas e historial; cada cliente se ejecuta en otro nodo y recibe notificaciones mientras espera comandos.

## Integrantes

- Samuel Arturo Rodríguez.
- Juan Jose Mendez Carranza.
- Daniel Yizack Gutiérrez Ruiz.

El reparto inicial está en `docs/arquitectura.md`; las contribuciones realizadas y las tareas asumidas por otro integrante están registradas en `docs/progreso.md` y `docs/uso-ia.md`.

## Requisitos e instalación

Elixir compatible con `~> 1.18` (declarado en `mix.exs`) y Erlang/OTP compatible con la instalación de Elixir. Dependencia JSON: Jason `~> 1.4`, fijada por `mix.lock`.

Abre una terminal en la carpeta que contiene `mix.exs`. Comprueba e instala las dependencias:

```powershell
elixir --version
mix deps.get
mix compile --warnings-as-errors
mix test
```

Si Mix solicita instalar Hex, acepta para descargar las dependencias. Conserva `mix.lock`. En Windows, si PowerShell no ejecuta correctamente `iex`, usa `iex.bat` con los mismos argumentos.

## Arranque en un mismo computador

Abre tres terminales en la raíz del proyecto. Los nombres de nodo deben ser diferentes. La cookie de ejemplo es solo para el ensayo local; usa el mismo valor en las tres terminales.

### Terminal 1 servidor

En PowerShell:

```powershell
iex --sname servidor --cookie trivia_demo -S mix
```

Dentro de IEx:

```elixir
Trivia.Servidor.iniciar()
node()
```

Debe mostrar el aviso de servidor listo y devolver `{:ok, pid}`. El nodo tendrá un nombre como `:"servidor@NOMBRE-EQUIPO"`. Conserva la terminal abierta. `mix` no arranca el servidor automáticamente.

### Terminal 2 primer cliente

```powershell
iex --sname pedro --cookie trivia_demo -S mix
```

Dentro de IEx:

```elixir
Trivia.Cliente.iniciar()
```

### Terminal 3 segundo cliente

```powershell
iex --sname carlos --cookie trivia_demo -S mix
```

Dentro de IEx:

```elixir
Trivia.Cliente.iniciar()
```

`Cliente.iniciar/0` busca `servidor` en el mismo equipo. Cuando aparece el prompt del cliente, escribe comandos del juego, no expresiones Elixir.

### Clientes en otros computadores

Todos necesitan una copia del proyecto compilada, nombres de nodo distintos, una cookie común y conectividad entre los equipos. Usa el nombre real que devolvió `node()` en el servidor:

```elixir
Trivia.Cliente.iniciar(:"servidor@NOMBRE-EQUIPO-REAL")
```

Sustituye ese nombre; no lo copies literalmente. Con `--sname`, los nombres cortos de los equipos deben resolverse en la red. Comprueba red, resolución de nombres y permisos del firewall para Erlang. El cliente no debe llamar `Trivia.Servidor.iniciar()` ni requiere usuarios o historial locales. Esta aplicación es una práctica para una red de confianza, con claves en texto plano; no es un servicio para exponer en Internet.

## Una partida completa

En el prompt del primer cliente, escribe una línea a la vez:

```text
connect pedro 1234
create_game tema=historia preguntas=3 tiempo=15
add_bot facil
add_bot dificil
start_game
```

Cuando aparezca una pregunta, responde con la letra que elijas, por ejemplo `answer B`. Repite en cada ronda. No pegues todas las respuestas de golpe: fuera de la ronda abierta se rechazan y solo cuenta la primera respuesta válida por jugador.

Al terminar:

```text
score
ranking
ranking historia
```

En el segundo cliente puedes iniciar simultáneamente otra partida:

```text
connect carlos abcd
create_game tema=ciencia preguntas=3 tiempo=20
add_bot dificil
add_bot facil
start_game
```

## Comandos

| Comando | Resultado |
|---|---|
| `connect usuario clave` | Registra al usuario si es nuevo o valida su clave; abre sesión. |
| `disconnect` | Cierra sesión; aplica abandono si hay una partida. |
| `create_game tema=historia preguntas=5 tiempo=15` | Crea la partida; preguntas de 1 a 10 y tiempo entero mayor que cero. |
| `add_bot facil` / `add_bot dificil` | Agrega un participante bot en espera; máximo tres bots. |
| `start_game` | Sortea e inicia; requiere al menos dos bots. |
| `answer A` | Responde la ronda abierta; A, B, C o D. |
| `leave_game` | Cancela si no inició; termina y registra si estaba en curso. |
| `score` | Puntaje, partidas y puntaje/nivel por tema del usuario. |
| `ranking` / `ranking ciencia` | Clasificación histórica de humanos, global o por tema. |
| `salir` | Comando local: cierra el cliente y regresa a IEx. |

Temas: `historia`, `ciencia`, `geografia`, `programacion`. Los temas de creación y ranking se normalizan a minúsculas. Los usuarios no pueden contener espacios, `|`, `,` ni `:`; el prefijo exacto `bot_` está reservado. Solo se admite una sesión por usuario y una partida por humano. `list_games` y `join_game` no están implementados; son extensión opcional.

## Reglas de juego

- La ronda cierra cuando todos respondieron o vence su tiempo. Entre rondas hay una pausa de tres segundos.
- Acierto: básico +10, intermedio +15, avanzado +20; error: −5, −8, −10. Sin respuesta: 0.
- Una respuesta correcta agrega `trunc(5 * ms_restantes / tiempo_total_ms)`. El tiempo se mide al llegar la respuesta a la partida.
- El nivel por tema se calcula desde el historial: menos de 60 básico; 60 a 179 intermedio; desde 180 avanzado. Se fija al crear cada partida.
- Bots fáciles: 40/30/20 % de acierto según nivel de pregunta; difíciles: 80/70/60 %. Retardo fácil 40–90 % del tiempo, difícil 10–40 %.
- Los bots aparecen en la clasificación de la partida, pero no en el ranking histórico de humanos.

## Archivos y persistencia

Solo `Trivia.Persistencia` accede a archivos durante el funcionamiento de la aplicación. Sus escrituras se canalizan por un único proceso del servidor.

| Archivo | Uso | Git |
|---|---|---|
| `data/questions.json` | Banco de 96 preguntas: cuatro temas, tres niveles, ocho por combinación. | Incluir. |
| `data/users.json` | Usuarios y claves; se crea al registrar usuarios. | Excluido. |
| `data/results.log` | Historial; se agrega una línea por partida completada o abandonada en curso. | Excluido. |

Para detener ordenadamente, primero termina las partidas y usa `salir` en los clientes. Después, en IEx del servidor:

```elixir
Trivia.Servidor.detener()
```

Volver a llamar `Trivia.Servidor.iniciar()` carga los mismos archivos. Los usuarios y resultados persisten; las sesiones y partidas en memoria no. No borres `data/` para demostrar persistencia.

## Pruebas y demostración

```powershell
mix compile --warnings-as-errors
mix test
mix test test/trivia/bot_test.exs
mix test test/trivia/errores_test.exs
```

La bitácora T11 reporta 317 pruebas aprobadas en el entorno del equipo. Ejecuta nuevamente la suite en la copia que se entregará; ese registro no sustituye la ejecución actual.

Guion de los 13 criterios, pruebas manuales, errores y conceptos para sustentar: [docs/demo.md](docs/demo.md). Diseño y contratos: [docs/arquitectura.md](docs/arquitectura.md). Uso de herramientas: [docs/uso-ia.md](docs/uso-ia.md).

## Limitaciones conocidas

- Las partidas tienen supervisión; los gestores y Persistencia no se reinician automáticamente si sus procesos fallan.
- Si se abandona antes de cerrar la primera ronda, el resultado puede ser empate a cero; solo cuentan las rondas cerradas.
- La primera pregunta puede imprimirse antes del mensaje de confirmación de inicio, porque Cliente y Receptor son procesos distintos.
- `Util.leer` no trata expresamente EOF. Para la salida normal usa `salir`.
- Los IDs de partida se generan en memoria; no deben usarse como identificadores globales únicos entre reinicios.
