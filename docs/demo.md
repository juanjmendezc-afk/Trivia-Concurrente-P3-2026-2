# Guion de demostración y sustentación

## Estado y preparación

Este es un guion para ejecutar, no un acta de pruebas aprobadas. Las casillas permanecen pendientes hasta observar el resultado. La bitácora T11 registra pruebas previas del equipo; repetir en la versión que se va a entregar.

1. Completar nombres de integrantes en README y revisar el registro de IA.
2. Preparar una copia de ensayo del repositorio para no afectar usuarios e historial que quieran conservar. No borrar datos entre la medición previa y posterior del reinicio.
3. Desde esa copia ejecutar `mix deps.get`, `mix compile --warnings-as-errors` y `mix test`. Guardar el resumen real, fecha y versión de Elixir.
4. Abrir tres terminales como indica README: `servidor`, `pedro` y `carlos`, con la misma cookie. En Windows se puede usar `iex.bat`.
5. Tener a mano el código del bot, Partida, Persistencia y Cliente. El primer cliente usará historia y el segundo ciencia; no necesitan compartir una misma partida.

En este documento, **PowerShell** significa la terminal antes de abrir IEx; **IEx servidor** significa la consola Elixir del servidor; **cliente** significa el prompt del juego después de `Trivia.Cliente.iniciar()`.

## Demostración principal

En el cliente Pedro:

```text
connect demo_pedro 1234
create_game tema=historia preguntas=3 tiempo=15
add_bot facil
add_bot dificil
start_game
```

En el cliente Carlos, sin esperar a que termine Pedro:

```text
connect demo_carlos abcd
create_game tema=ciencia preguntas=3 tiempo=20
add_bot facil
add_bot dificil
add_bot dificil
start_game
```

Responder al menos una pregunta en Pedro con `answer A` (o la opción que elija el jugador). Dejar una ronda de Carlos sin contestar para que cierre por tiempo. No asumir que A es correcta: leer el cierre y contrastar los puntos. Al finalizar, usar `score`, `ranking`, `ranking historia` y `ranking ciencia`. Registrar los IDs mostrados, no asumir P-1001 si ya hubo otras partidas.

## Los 13 criterios

| Criterio | Acción y evidencia esperada | Estado |
|---|---|---|
| 1 Servidor disponible | Iniciar servidor; mostrar mensaje de listo, `node()` y conexión de un cliente. | [ ] |
| 2 Partida completa | Pedro agrega dos bots y recibe todas las preguntas, cierres y ranking final. | [ ] |
| 3 Concurrencia | Pedro y Carlos juegan al mismo tiempo, con temas y tiempos diferentes; cada receptor muestra solo su partida. | [ ] |
| 4 Preguntas y tiempo | Mostrar que una ronda se notifica a todos sus participantes y que termina sin respuesta humana al vencer el plazo. No afirmar entrega física exactamente simultánea: los mensajes se envían en la apertura y la impresión se planifica por proceso. | [ ] |
| 5 Puntos y ranking | Contrastar letra, nivel, tiempo de llegada y puntos. Revisar empates. Apoyar con Puntaje y sus pruebas. | [ ] |
| 6 Nivel y reparto | Mostrar score por tema y reparto; acumular hasta cruzar un umbral, crear una nueva partida del mismo tema y verificar el nuevo nivel y reparto. Ver procedimiento específico. | [ ] |
| 7 Bots | Mostrar respuestas programadas y puntos en partida; comprobar ausencia en ranking histórico y usuarios. Complementar con muestra estadística de decidir/4. | [ ] |
| 8 Cliente sin archivos | Revisar Cliente/Receptor/Util y ejecutar un cliente desde copia sin `data/`; sigue jugando por mensajes al servidor. | [ ] |
| 9 Desconexión | Cerrar un cliente durante una partida; comprobar fin y registro de esa partida y que el otro cliente sigue operando. | [ ] |
| 10 Persistencia | Guardar score/ranking e historial, detener y reiniciar servidor con la misma carpeta; reconectar y comparar. | [ ] |
| 11 Coherencia histórica | Comparar results.log con score y rankings global y por tema. Bots no se suman al histórico de humanos. | [ ] |
| 12 Errores | Ejecutar la matriz de errores y comprobar después un comando válido y al otro cliente. | [ ] |
| 13 Suite | Ejecutar `mix test`; conservar cantidad y resultado actuales. | [ ] |

## Criterio 5 Puntaje que se puede explicar

En IEx del servidor, demostración aislada del cálculo (no altera ninguna partida):

```elixir
Trivia.Puntaje.calcular(:basico, :correcta, 14_000, 15)
Trivia.Puntaje.calcular(:basico, :incorrecta, 14_000, 15)
Trivia.Puntaje.calcular(:basico, :sin_responder, 0, 15)
```

Esperado: 14, −5 y 0. El primer caso suma 10 + trunc(5 × 14000 / 15000) = 14. En vivo, teclear «al segundo uno» no garantiza exactamente 14000 ms restantes: la partida mide la llegada real con reloj monotónico. Las cifras anteriores son una comprobación controlada de la función.

## Criterio 6 Nivel y reparto

En IEx servidor:

```elixir
Enum.map([59, 60, 179, 180, -1], &Trivia.Nivel.calcular/1)
Trivia.Nivel.reparto(:basico, 5)
Trivia.Nivel.reparto(:avanzado, 10)
```

Esperado: niveles básico, intermedio, intermedio, avanzado y básico; reparto de 5 en básico = 4 básicas y 1 intermedia; reparto de 10 en avanzado = 3 intermedias y 7 avanzadas.

Para la evidencia integrada, usar un usuario nuevo en la copia de ensayo. Jugar partidas de historia, responder y consultar `score` hasta alcanzar al menos 60 puntos en ese tema. Anotar el valor real. Al crear la siguiente partida de historia, debe informar intermedio (si aún está por debajo de 180). No basta con que suba el total global: debe subir el puntaje del tema. No hay un número fijo de partidas porque hay azar y penalizaciones. Preparar este usuario antes de la exposición y conservar una evidencia del antes y después.

En la consola del servidor se puede inspeccionar una partida de ensayo recién creada para verificar su nivel y, tras iniciarla, las preguntas sorteadas con `:sys.get_state(pid)`. Es una herramienta de diagnóstico del servidor, no un comando del cliente; evita mostrar la respuesta correcta a quien está jugando. También están las pruebas de reparto en `banco_preguntas_test.exs` y las de nivel en `nivel_test.exs` y `estadisticas_test.exs`.

## Criterio 7 Bots sin confundir probabilidad con garantía

Un bot difícil no tiene que ganar cada partida. Con pocas preguntas puede acertar menos por azar. Para comprobar las seis combinaciones, pegar en IEx servidor (no en el prompt del juego):

```elixir
muestras = 10_000
for dificultad <- [:facil, :dificil], nivel <- [:basico, :intermedio, :avanzado] do
  resultados = Enum.map(1..muestras, fn _ ->
    Trivia.Bot.decidir(dificultad, nivel, "A", 15)
  end)
  aciertos = Enum.count(resultados, fn {letra, _} -> letra == "A" end)
  retardos = Enum.map(resultados, fn {_, ms} -> ms end)
  {dificultad, nivel, 100 * aciertos / muestras,
   Enum.min(retardos), Enum.max(retardos)}
end
```

La tupla muestra dificultad, nivel, porcentaje observado, mínimo y máximo observados. Esperar porcentajes próximos a 40/30/20 para fácil y 80/70/60 para difícil; no exigir igualdad exacta. Para 15 s, todos los retardos fáciles deben quedar entre 6000 y 13500 ms y los difíciles entre 1500 y 6000 ms. Los extremos observados no tienen que coincidir exactamente con los límites.

Esto ejecuta la decisión muchas veces sin esperar los retardos: decidir/4 devuelve números, no duerme. La prueba en vivo complementaria es ver que cada bot responde mediante su proceso y `Process.send_after`, suma puntos y desaparece del ranking histórico. La función es aislable de procesos y archivos, pero usa aleatoriedad: no es pura en el sentido estricto de devolver siempre lo mismo con iguales entradas.

## Criterio 8 Cliente sin data

En el editor, comprobar que Cliente, Receptor y Util no usan File ni llaman directamente Persistencia o gestores. Preparar **otra copia solo para el cliente**, sin carpeta data (no quitarla de la copia del servidor). Compilar esa copia y arrancar el cliente con cookie común y nombre de nodo distinto. Si está en el mismo equipo, `Cliente.iniciar()` encuentra al servidor; si está en otro, usar su nombre explícito como indica README.

Debe poder conectar, jugar y consultar ranking sin archivos locales de usuarios o preguntas. El servidor sí conserva su carpeta. La revisión del código y la ejecución desde esa copia son evidencias complementarias; una demo sola no prueba ausencia de todos los accesos posibles.

## Criterios 9 y 10 Desconexión y persistencia

### Cerrar un cliente

1. Iniciar otra partida en Pedro y otra en Carlos.
2. Esperar al menos un cierre de ronda de Pedro para obtener un resultado no trivial.
3. Cerrar de golpe la terminal de Pedro.
4. En Carlos, seguir respondiendo o consultar un comando válido. El servidor debe seguir vivo.
5. En el servidor, comprobar que el historial contiene la partida abandonada. Solo cuentan rondas cerradas; si se abandonó antes del primer cierre, puede aparecer empate a cero.
6. Abrir un nodo cliente nuevo y volver a entrar como demo_pedro: la sesión anterior debe haberse liberado.

### Reiniciar el servidor conservando resultados

1. Terminar todas las partidas. En ambos clientes consultar score y ranking y guardar las cifras. Escribir `salir` para volver a IEx.
2. En IEx servidor, guardar las líneas antes del reinicio:

```elixir
{:ok, antes} = Trivia.Persistencia.leer_historial()
length(antes)
Trivia.Servidor.detener()
Trivia.Servidor.iniciar()
{:ok, despues} = Trivia.Persistencia.leer_historial()
antes == despues
```

3. Esperado: igualdad `true` y misma cantidad de líneas, sin partidas en curso entre las lecturas. Se reiniciaron los procesos con los mismos archivos.
4. Para probar también el reinicio completo del nodo, salir de IEx servidor con `System.stop()`, volver a arrancarlo desde PowerShell con el mismo nombre/cookie y ejecutar `Trivia.Servidor.iniciar()`. Las variables de IEx ya no existirán: comparar con las cifras y evidencias guardadas.
5. En cada cliente volver a ejecutar `Trivia.Cliente.iniciar()` y conectar con el usuario y clave anteriores. No hay sesiones restauradas automáticamente. Una clave equivocada debe rechazarse; la correcta debe permitir entrar al usuario ya registrado.
6. `score`, `ranking` y `ranking historia` deben conservar las cifras. Leer historial de nuevo en el servidor. No limpiar, sustituir ni cambiar la carpeta de datos durante esta prueba.

## Reinicio de una partida bajo supervisión

Ensayo adicional en copia de prueba. No mata al servidor. Preparar exactamente una partida activa y localizar su PID en IEx servidor:

```elixir
hijos = DynamicSupervisor.which_children(:supervisor_partidas)
Enum.map(hijos, fn {_, pid, _, _} ->
  estado = :sys.get_state(pid)
  {estado.id, pid}
end)
```

Elegir el PID de la partida de ensayo mostrada (si terminó mientras se inspecciona, crear otra). Cuando hay exactamente un hijo:

```elixir
[{_, pid, _, _}] = hijos
Process.exit(pid, :kill)
```

El creador debe recibir el aviso de reinicio. Consultar otra vez los hijos: mismo ID y PID nuevo; estado esperando, sin bots ni puntos. En el cliente agregar dos bots y usar start_game. La caída no debe agregar resultados al historial. Una terminación normal no se reinicia por la política `:transient`.

## Criterio 12 Matriz de errores

Hacer estos casos en el orden indicado o restaurar la precondición antes de cada uno. Después de cada rechazo probar un comando válido y comprobar que Carlos conserva su sesión. Para errores automatizados ejecutar en PowerShell `mix test test/trivia/errores_test.exs`.

| Caso | Precondición y comando | Esperado |
|---|---|---|
| Sin sesión | Cliente recién iniciado: `score`. | Solicitud de conectar. |
| Clave incorrecta | Usuario ya registrado y desconectado: `connect demo_pedro incorrecta`. | Clave incorrecta. |
| Ya conectado | demo_pedro conectado en otra terminal; intentar conectarlo en cliente sin sesión. | Usuario ya conectado. |
| Reservado | Sin sesión: `connect bot_prueba 1234`. | Prefijo reservado. |
| Servidor no disponible | Cliente separado en IEx: `Trivia.Cliente.iniciar(:"ausente@EQUIPO-REAL")`, con nombre del equipo real. | Error de conexión. No detener la demo concurrente para este caso. |
| Ya en partida | Crear partida y volver a ejecutar create_game. | Ya estás en una partida. |
| Tema inexistente | Sin partida: `create_game tema=noexiste preguntas=2 tiempo=15`. | Tema inexistente. |
| Preguntas insuficientes | En copia de ensayo con catálogo limitado por nivel; reiniciar ese servidor y pedir más preguntas de las disponibles. | Preguntas insuficientes. No basta pedir 11: eso da parámetros inválidos. |
| Sin partida | Con sesión, sin partida: `add_bot facil` y `start_game`. | Sin partida. |
| Partida llena | En espera, añadir tres bots y pedir un cuarto. | Partida llena. |
| Partida iniciada | Con ronda en curso: `add_bot facil`. | Partida ya empezó. |
| Bots insuficientes | En espera con cero o un bot: `start_game`. | Requiere dos bots. |
| Letra inválida | Durante ronda: `answer Z`; después `answer A`. | Rechaza Z sin consumir la respuesta; admite A si sigue abierta. |
| Fuera de ronda | En espera o durante pausa: `answer A`. | No hay pregunta abierta. |
| Respuesta repetida | Ronda suficientemente larga: responder dos veces antes del cierre. | Solo cuenta la primera. Si ya cerró, corresponde fuera de ronda. |

Para el catálogo limitado, copiar el proyecto a otra carpeta y conservar solo una pregunta de historia en questions.json mediante el editor, manteniendo un JSON válido. Levantar ese servidor de ensayo sin el servidor principal en uso; pedir cinco preguntas de historia con un usuario nuevo. Reponer la copia original antes de la entrega. Las pruebas de integración usan datos temporales para el mismo fin.

## Conceptos para explicar de palabra

| Concepto | Explicación y dónde se usa |
|---|---|
| Nodo y proceso | Un nodo es una máquina virtual Erlang con nombre; dentro viven muchos procesos. PID identifica un proceso. Servidor, clientes y partidas no son sinónimos. |
| send y receive | Entrega de mensajes al buzón y selección por patrones. Los gestores usan bucles recursivos. |
| GenServer | Encapsula el estado de una partida; call espera reply; handle_info trata temporizadores y mensajes sin llamada. |
| DynamicSupervisor | Crea partidas cuando se piden y supervisa sus procesos. transient reinicia terminaciones anormales. |
| spawn_link | Crea y enlaza el bot con la partida. Si la partida cae anormalmente, el enlace propaga la salida. |
| monitor y DOWN | Observan otro proceso sin el enlace bidireccional. Servidor detecta clientes cerrados. |
| spawn_monitor | Crea el auxiliar que hace call a la partida. Si cae, GestorPartidas recibe DOWN y sobrevive. |
| demonitor y flush | Retira el monitor y limpia un DOWN pendiente tras recibir la respuesta esperada. |
| send_after | Programa un mensaje futuro; no detiene el proceso como sleep. |
| Reloj monotónico | Mide duraciones; se usa al iniciar ronda y recibir respuesta para calcular bono. |
| Pin ^ | Exige el valor ya guardado: números de ronda y referencias de mensajes deben coincidir. |
| receive after 0 | Revisa sin esperar; Cliente descarta respuestas viejas antes de una petición. |
| Process.unregister | Libera un nombre registrado antes de confirmar la parada. |
| Jason | Convierte JSON a datos Elixir y viceversa; distinto de inspect. |
| Stream.flat_map | Lee historial y produce cero o un resultado por línea parseada, descartando inválidas. |
| Map y Enum | Map.new crea asociaciones; fetch exige clave o informa falta; pop extrae y elimina en un mapa nuevo; update! exige clave. Enum.random/take_random sortean, flat_map reúne listas, map_join transforma y une, sort_by ordena. |
| Sintaxis auxiliar | ~w produce lista de palabras; match? devuelve coincidencia; guards verifican tipos; elem/tuple_size consultan tuplas; argumentos por defecto permiten omitir un parámetro. |
| Conversión de texto | trim_trailing quita al final, upcase convierte a mayúscula, Atom.to_string convierte átomo a texto, Path.expand resuelve ruta absoluta. |
| ExUnit | describe agrupa, setup prepara, on_exit limpia, tmp_dir aísla archivos, CaptureIO comprueba consola. El timeout de una prueba no prueba por sí solo la corrección del protocolo. |

Cada integrante debe poder seguir un ejemplo de su módulo desde entrada hasta salida y explicar la integración. Para Samuel: decidir/4, selección de incorrectas, porcentajes, conversión a milisegundos, diferencia entre decidir e iniciar y descarte por número de ronda. Pregunta probable: «si falla, ¿puede escoger la correcta?» Respuesta: no, se excluye con Enum.reject antes de elegir entre las otras tres.

## Registro del ensayo

Completar tras ejecutar; no marcar por haber leído el guion.

- Fecha y responsables:
- Versión de Elixir y OTP:
- Commit o versión del ZIP probado:
- Resultado real de mix test:
- IDs de las dos partidas simultáneas:
- Resultado del reinicio y comparación de historial:
- Porcentajes observados de bots:
- Criterios pendientes y errores encontrados:

Pendientes conocidos que no deben confundirse con nuevas garantías: primera pregunta antes del aviso de inicio; abandono antes de cerrar ronda deja empate cero; EOF no tratado explícitamente; gestores y Persistencia sin reinicio automático. Si falla una comprobación, registrar el caso y corregirlo antes de marcar el criterio.
