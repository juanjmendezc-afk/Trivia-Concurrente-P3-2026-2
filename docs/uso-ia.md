# Uso de inteligencia artificial

> Entregable 3 del enunciado: herramientas de IA usadas y su propósito.

| Fecha | Herramienta | Quién | Para qué | Parte del proyecto |
|---|---|---|---|---|
| 2026-11-08/09 | Claude (chat) | Juanjo | Leer el enunciado y las guías 06–12, resumir convenciones y diseñar la arquitectura | `docs/` y `CLAUDE.md` |
| 2026-11-10 | Claude Code | Juanjo | T1: limpieza del proyecto Mix, dependencia `jason`, carpeta `data/` y escribir `Trivia.Util` (`leer`/`imprimir`) | `mix.exs`, `lib/trivia/util.ex`, `data/` |
| 2026-11-10 | Claude Code | Juanjo | T2: consultar la guía 11 (archivos) y escribir `Trivia.Persistencia` (carga/guarda usuarios, preguntas e historial) con sus 16 pruebas | `lib/trivia/persistencia.ex`, `test/trivia/persistencia_test.exs` |
| 2026-11-10 | Claude Code | Juanjo | T3: escribir `GestorJugadores` y `Servidor` (sesiones, vigilancia de clientes con monitores), sus 25 pruebas y una prueba manual con nodos reales | `lib/trivia/gestor_jugadores.ex`, `lib/trivia/servidor.ex`, `test/trivia/gestor_jugadores_test.exs`, `test/trivia/servidor_test.exs` |
| 2026-11-10 | Claude Code | Juanjo | Revisión de T1–T3: detectar que los usuarios con `\|`, `,` o `:` rompen `results.log`, corregirlo con 2 pruebas y limpiar la documentación (sección 3 duplicada, orden de validación de `connect`, nota de formato) | `lib/trivia/gestor_jugadores.ex`, `test/trivia/gestor_jugadores_test.exs`, `docs/` |
| 2026-11-10 | Claude Code | Daniel | P1: diseño e implementación del módulo `Trivia.Nivel`, con las funciones `calcular/1` y `reparto/2`, incluyendo validaciones y distribución de preguntas por dificultad. 
| 2026-11-10 | Claude Code | Daniel | P2: generación de las 96 preguntas del banco, distribuidas en Historia, Ciencia, Geografía y Programación, con 8 preguntas por nivel en cada tema. 
| 2026-11-10 | Claude Code | Daniel | P3: implementación de `Trivia.BancoPreguntas.sortear/3`, selección aleatoria de preguntas, validación de cantidades disponibles y ordenamiento por nivel. También se apoyó la creación de pruebas unitarias y la integración con Persistencia. | Se conservaron los contratos establecidos en el enunciado. P3 se adaptó para aceptar mapas con claves string provenientes de JSON y mapas con claves átomo provenientes de `Trivia.Persistencia.cargar_preguntas/0`. Se mantuvo la versión de Elixir 1.18 del proyecto base. | Ejecutar `mix compile` y `mix test` para validar la integración completa en el entorno local. |
