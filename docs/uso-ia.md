# Uso de inteligencia artificial

> Entregable 3 del enunciado: herramientas de IA usadas y su propósito.

| Fecha | Herramienta | Quién | Para qué | Parte del proyecto |
|---|---|---|---|---|
| 2026-11-08/09 | Claude (chat) | Juanjo | Leer el enunciado y las guías 06–12, resumir convenciones y diseñar la arquitectura | `docs/` y `CLAUDE.md` |
| 2026-11-10 | Claude Code | Juanjo | T1: limpieza del proyecto Mix, dependencia `jason`, carpeta `data/` y escribir `Trivia.Util` (`leer`/`imprimir`) | `mix.exs`, `lib/trivia/util.ex`, `data/` |
| 2026-11-10 | Claude Code | Juanjo | T2: consultar la guía 11 (archivos) y escribir `Trivia.Persistencia` (carga/guarda usuarios, preguntas e historial) con sus 16 pruebas | `lib/trivia/persistencia.ex`, `test/trivia/persistencia_test.exs` |
| 2026-11-10 | Claude Code | Juanjo | T3: escribir `GestorJugadores` y `Servidor` (sesiones, vigilancia de clientes con monitores), sus 25 pruebas y una prueba manual con nodos reales | `lib/trivia/gestor_jugadores.ex`, `lib/trivia/servidor.ex`, `test/trivia/gestor_jugadores_test.exs`, `test/trivia/servidor_test.exs` |
| 2026-11-10 | Claude Code | Juanjo | Revisión de T1–T3: detectar que los usuarios con `\|`, `,` o `:` rompen `results.log`, corregirlo con 2 pruebas y limpiar la documentación (sección 3 duplicada, orden de validación de `connect`, nota de formato) | `lib/trivia/gestor_jugadores.ex`, `test/trivia/gestor_jugadores_test.exs`, `docs/` |
