# Convenciones del profesor (guías 06–12 de Programación III)

> Fuente: guías vistas en clase hasta ahora (06 a 12), en https://caflorezvi.github.io/guias-programacion3/
> Este documento resume **cómo escribe código el profesor** para que el proyecto se vea como él espera.
> Claude Code: sigue estas convenciones al escribir o revisar código de este repo.

---

## 1. Nombres e idioma (todas las guías)

- **Todo en español**: módulos, funciones, variables, campos de structs, átomos de dominio y comentarios.
  - Ejemplos del profe: `calcular_diferencia`, `registrar_pokemon`, `mostrar_resultado`, `:aprobado`, `:dia_invalido`.
- Solo quedan en inglés los átomos estándar (`:ok`, `:error`) y las palabras del lenguaje.
- Módulos en `PascalCase`; funciones y variables en `snake_case`.
- Predicados (devuelven booleano) terminan en `?`: `es_primo?/1`, `frecuente?/1`, `conoce_movimiento?/2`.
- Constantes como **atributos de módulo**, nunca números sueltos: `@max_movimientos 4`, `@minimo 1`, `@maximo 10`.

## 2. Estructura de módulos (06, 07, 09)

- Funciones **pequeñas y de una sola responsabilidad**; una función por cálculo o métrica.
- Lo interno va en `defp`; solo es público lo que otro módulo necesita.
- Los datos de prueba van en su propia función (p. ej. `estudiantes_del_curso/0`) y `main` solo orquesta.
- Encadenar con `|>`; usar `then/2` cuando el valor no entra como primer argumento.
- Comentarios breves en español explicando la intención (`# Constructor con validación`).
- **No usa `@moduledoc`, `@doc` ni `@spec`**. Se documenta con comentarios cortos.
- Patrón repetido (guía 09): módulo de dominio (struct + su lógica) → módulo gestor (colección) → módulo con `main`.
- Aislar lo impuro (guía 06): la función que usa `:rand` queda separada para que el resto sea puro y fácil de probar.

## 3. Manejo de errores y resultados (06, 09)

- Las operaciones que pueden fallar devuelven `{:ok, valor}` o `{:error, motivo}`.
  - Motivo como **átomo** cuando es categórico (`{:error, :nivel_invalido}`, `{:error, :fondos_insuficientes}`).
  - Motivo como **string** cuando es un mensaje para mostrar.
- Errores como valores; **no usa `try/rescue`**.
- `with` para encadenar validaciones; sin `else` si basta con propagar el primer error, con `else` si hay que construir el mensaje.
- `cond` cuando hay varios motivos de falla (`:ya_lo_conoce`, `:movimientos_llenos`).
- `case` para decidir qué mostrar según `:ok`/`:error`.
- Si una operación falla, se devuelve el estado original sin cambios y se informa el error por la salida de errores.

## 4. Estructuras de control (tabla de la guía 06)

| Estructura | Cuándo |
|---|---|
| `if` | Una sola condición booleana |
| `cond` | Varias condiciones independientes |
| `case` | Un valor contra varios patrones |
| guards (`when`) | Elegir la cláusula de una función según sus argumentos |
| `with` | Encadenar pasos que pueden fallar |

- Prefiere **varias cláusulas con guards** sobre bloques largos de `if`.
- Orden de cláusulas: **lo más específico primero**; la cláusula de respaldo con `_` al final.
- Forma idiomática de rango: `when numero in @minimo..@maximo`.

## 5. Colecciones y `Enum` (07)

- Listas para colecciones variables; tuplas para grupos pequeños fijos o devolver varios valores; mapas para acceso por clave; keyword lists para opciones.
- Mapas con claves átomo cuando son descriptivas; claves string cuando son identificadores.
- `fn ... end` es lo más usado; `&` en casos cortos (`&(&1 >= 3)`).
- Buenas prácticas explícitas:
  - **Recorrer una sola vez**: `Enum.reduce/3` con tupla de acumulador en vez de dos `Enum.count/2`.
  - `Map.update/4` para acumular dentro de un mapa.
  - Funciones `_by` (`sort_by`, `min_max_by`) cuando se necesita el elemento completo.
  - Funciones que se detienen temprano (`any?`, `all?`, `find`) en vez de `filter` si solo se necesita una respuesta.
  - Considerar el `nil` de `Enum.find/2` (o envolverlo en tupla).
  - Agregar al inicio con `[x | lista]`; evitar `lista ++ [x]`.
- `Enum.each/2` cuando solo interesa el efecto (imprimir).
- `IO.inspect(valor, label: "...")` para estructuras; texto con interpolación para mensajes.

## 6. Recursividad (08)

- Caso base **primero**; `[]` con su propia cláusula.
- Patrón **función pública + privada con acumulador** (mismo nombre, distinta aridad):
  ```elixir
  def sumar(lista), do: sumar(lista, 0)
  defp sumar([], acumulado), do: acumulado
  defp sumar([cabeza | cola], acumulado), do: sumar(cola, cabeza + acumulado)
  ```
- Preferir **recursión de cola**; construir con `[x | acum]` y `Enum.reverse/1` una vez al final.
- Para cadenas, convertir una vez con `String.graphemes/1` y recorrer la lista.
- En código real, preferir `Enum`/`String`; la recursión manual es para entender cómo funcionan.

## 7. Structs (09)

- `defstruct` con defaults (`movimientos: []`); campos sin default primero.
- `@enforce_keys` para campos obligatorios.
- Constructor `nuevo/n` que valida con guards y devuelve `{:ok, %__MODULE__{...}}` o `{:error, :motivo}`.
- Actualización con `%{struct | campo: valor}`; acceso con punto o pattern matching.
- Las funciones del struct reciben el struct y devuelven uno nuevo (encadenables con `|>`).
- El módulo gestor guarda la colección en un mapa indexado por id y cada operación devuelve el mapa nuevo.

## 8. Streams (10)

- `Stream` cuando solo se necesita parte del resultado, la secuencia es infinita, hay muchos datos o **se lee un archivo línea por línea**.
- `Enum` para colecciones pequeñas con resultado completo.
- Un stream no hace nada hasta consumirlo con una función de `Enum`.
- Preferir `take_while` a `filter` cuando el orden es conocido.

## 9. Archivos y persistencia (11)

- **Un único módulo con efectos secundarios** sobre archivos (el profe lo llama `Archivo`). El resto es puro: recibe datos y devuelve datos.
  ```elixir
  datos = Archivo.cargar()
  datos = registrar(datos, nuevo)   # función pura
  Archivo.guardar(datos)            # único efecto
  ```
- Rutas con `Path.join/2` y `__DIR__` en atributos de módulo.
- Primer arranque: si el archivo no existe, devolver colección vacía; nunca romper.
- Sin `!` cuando el fallo es esperable y se maneja (`File.read/1` + `case`); con `!` cuando no tiene sentido continuar (`File.mkdir_p!/1`).
- `File.stream!/1` no tiene variante con tupla → verificar antes con `File.exists?/1`.
- Históricos con `File.write(ruta, linea, [:append])`; cada línea termina en `\n` e incluye fecha.
- Al cargar: `String.trim/1` a cada línea y convertir tipos (`String.to_integer/1`).

## 10. Procesos y mensajes (12)

- Patrón actor: **bucle servidor** (`loop/1`, único que toca el estado) + **funciones cliente** que solo envían mensajes.
  ```elixir
  defp loop(total) do
    receive do
      {:sumar, valor} -> loop(total + valor)
      {:total, remitente} ->
        send(remitente, {:total, total})
        loop(total)
    end
  end
  ```
- Mensajes como tuplas con átomo de acción y el PID del remitente cuando se espera respuesta; la respuesta reutiliza la etiqueta.
- Guardar `self()` **antes** del `spawn` si el hijo debe responder al padre.
- `Process.register/2` para nombrar un proceso; `Process.whereis/1` y `Process.alive?/1` para inspeccionar.
- `receive ... after` para no esperar para siempre; pin `^` para aceptar solo la respuesta esperada.
- **Nunca sincronizar con tiempos** (`sleep`); si un proceso necesita saber que otro terminó, debe recibirlo en un mensaje.
- `spawn` para trabajo independiente; `Task.async/await` cuando se necesita el resultado (`Task` enlaza: si falla, falla quien la creó).

## 11. Entrada/salida por consola (06, 08)

- El profe usa siempre su módulo `Util`:
  - `Util.leer(mensaje, tipo)` con tipo `:string`, `:integer` o `:float`. En la guía 08 repite la pregunta hasta que la entrada sea válida.
  - `Util.imprimir(mensaje)` → salida estándar; `Util.imprimir(mensaje, :error)` → salida de errores.
- En el proyecto conviene conservar ese estilo en el cliente para leer comandos e imprimir errores.

---

## Lo que pide el enunciado y aún NO se ha visto en clase

El enunciado del proyecto exige estos temas, que no están en las guías 06–12. Hay que usarlos de la forma más simple posible, entenderlos bien para la sustentación y registrarlos en `docs/uso-ia.md` si se apoyaron en IA para aprenderlos. **Antes de implementarlos, revisar si el profesor ya los explicó en clase.**

| Tema | Dónde lo pide el enunciado |
|---|---|
| Proyecto **Mix** y pruebas **ExUnit** (`mix test`) | Entregables 1 y 4 |
| Dependencia externa `jason` (JSON) | Persistencia (sección 9) |
| **Nodos** Erlang conectados por nombre (`iex --sname ... -S mix`) | Arquitectura (8.2) |
| **GenServer** por partida | Concurrencia (8.4) |
| **DynamicSupervisor** con `restart: :transient` | Reinicio de partidas (8.5) |
| `Process.send_after` | Bots (6.6) y temporizador de ronda |
| Monitorear clientes (detectar que un cliente se cayó) | 8.2 |
