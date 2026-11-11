ExUnit.start()

# Ayudas compartidas por las pruebas que necesitan un banco de preguntas
defmodule Trivia.AyudaPruebas do
  # Tres temas: historia y ciencia con 8 preguntas por nivel, y "escaso" con una sola básica
  def banco_de_prueba do
    completos =
      for tema <- ["historia", "ciencia"],
          nivel <- [:basico, :intermedio, :avanzado],
          numero <- 1..8 do
        pregunta(tema, nivel, numero)
      end

    completos ++ [pregunta("escaso", :basico, 1)]
  end

  # Escribe el banco como questions.json en la carpeta indicada (nunca en data/)
  def escribir_preguntas(carpeta) do
    json =
      Enum.map(banco_de_prueba(), fn pregunta ->
        %{
          "tema" => pregunta.tema,
          "nivel" => Atom.to_string(pregunta.nivel),
          "enunciado" => pregunta.enunciado,
          "opciones" => pregunta.opciones,
          "respuesta" => pregunta.respuesta
        }
      end)

    File.write!(Path.join(carpeta, "questions.json"), Jason.encode!(json))
  end

  defp pregunta(tema, nivel, numero) do
    %{
      tema: tema,
      nivel: nivel,
      enunciado: "Pregunta #{numero} de #{tema} (#{nivel})",
      opciones: %{"A" => "uno", "B" => "dos", "C" => "tres", "D" => "cuatro"},
      respuesta: "A"
    }
  end
end
