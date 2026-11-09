# Trivia Concurrente — Programación III (UQ, 2026-2)

Proyecto final en Elixir (Mix): juego de trivia por consola con servidor central, clientes en nodos distintos, partidas concurrentes y bots.

## Documentos de referencia (leer antes de programar)

@docs/enunciado-resumen.md
@docs/convenciones-profesor.md

- Enunciado oficial: https://caflorezvi.github.io/guias-programacion3/proyecto20262.html — si el resumen y el original no coinciden, manda el original.
- `docs/arquitectura.md` — diseño acordado y tareas numeradas (cuando exista).
- `docs/progreso.md` — qué está hecho, qué falta, decisiones tomadas.

## Reglas obligatorias

- Seguir **las convenciones del profesor** (guías 06–12): nombres en español, `{:ok, _}` / `{:error, :atomo}`, sin `try/rescue`, sin `@doc`/`@spec`, comentarios cortos en español.
- **Usar solo lo visto en clase siempre que alcance.** Si el enunciado exige algo que aún no se ha visto (ver el final de `convenciones-profesor.md`), usar la forma más simple y anotarlo en `docs/progreso.md`, porque habrá que explicarlo en la sustentación.
- **Lógica pura separada de procesos y archivos** (lo exige el enunciado para las pruebas). Nivel, reparto, puntaje y decisión de bot son funciones puras que se prueban sin levantar procesos ni abrir archivos.
- **Un solo módulo toca archivos**, y todas las escrituras pasan por un único proceso.
- El cliente **nunca** llama módulos del servidor directamente ni lee `data/`. Solo se comunica por mensajes.
- Las respuestas correctas y el banco de preguntas nunca salen del servidor.
- No sincronizar con `sleep`; sincronizar con mensajes.

## Forma de trabajo

- **Una tarea por sesión.** La tarea viene de `docs/arquitectura.md`; no implementar cosas fuera de ella.
- No modificar módulos de otro integrante sin avisar. Si hace falta un cambio de interfaz, anotarlo en `docs/progreso.md`.
- Antes de terminar una tarea:
  1. `mix compile` sin warnings.
  2. `mix test` en verde.
  3. Agregar una entrada en `docs/progreso.md`: qué se hizo, qué se decidió por cuenta propia, qué queda pendiente.
  4. Agregar una línea en `docs/uso-ia.md`: herramienta, para qué se usó, qué parte.
- Al final de la sesión, explicar en lenguaje sencillo el código escrito: el equipo debe poder sustentarlo.

## Comandos

```
mix deps.get
mix compile
mix test
iex --sname servidor -S mix     # nodo servidor
iex --sname pedro -S mix        # un nodo cliente por consola
```
