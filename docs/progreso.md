# Progreso

> Claude Code agrega una entrada al terminar cada tarea: qué se hizo, qué se decidió por cuenta propia, qué queda pendiente.

| Fecha | Tarea | Quién | Qué se hizo | Decisiones propias | Pendiente |
|---|---|---|---|---|---|
| 2026-11-09 | Diseño | Juanjo + Claude (chat) | Arquitectura completa (secciones 1–8) en `docs/arquitectura.md` | — | Empezar T1 |
| 2026-11-09 | P6 | Samuel | `Trivia.Bot.decidir/4` + prueba | — | Error como átomo |
| 2026-11-10 | T1 | Juanjo + Claude Code | Borrado el ejemplo de Mix (`lib/proyecto_trivia.ex` y su prueba) y los `.gitkeep` de `lib/trivia/` y `test/trivia/`. Dependencia `{:jason, "~> 1.4"}` (instalada 1.4.5, `mix.lock` generado). Carpeta `data/`. `Trivia.Util` con `leer/2` (`:string`, `:integer`, `:float`) e `imprimir/1`, `imprimir/2` (`:error` → `:stderr`). `mix compile` sin warnings y `mix test` en verde (2 pruebas del bot). | `data/.gitkeep` para que git suba la carpeta (borrar cuando entre `questions.json`). `leer` con `:integer`/`:float` repite la pregunta hasta que sea válida, como en la guía 08. No se agregaron pruebas de `Util` (no están en T1 ni en las 7 del enunciado). `leer` no maneja `:eof` (entrada cerrada): el proceso del cliente se cae y el servidor lo trataría como cliente cerrado. | T2 `Persistencia`. Detalles ajenos a T1: `bot.ex` de Samuel ya devuelve `{:error, :argumentos_invalidos}` (la fila de P6 puede darse por cumplida); `.gitignore` tiene el bloque de `data/` duplicado. |
