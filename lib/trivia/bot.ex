defmodule Trivia.Bot do
  @letras ["A", "B", "C", "D"]

  def decidir(dificultad, nivel_pregunta, respuesta_correcta, tiempo_pregunta)
      when dificultad in [:facil, :dificil] and
             nivel_pregunta in [:basico, :intermedio, :avanzado] and
             respuesta_correcta in @letras and
             is_integer(tiempo_pregunta) and tiempo_pregunta > 0 do
    probabilidad = probabilidad_acierto(dificultad, nivel_pregunta)

    letra =
      if Enum.random(1..100) <= probabilidad do
        respuesta_correcta
      else
        @letras
        |> Enum.reject(fn letra -> letra == respuesta_correcta end)
        |> Enum.random()
      end

    {porcentaje_minimo, porcentaje_maximo} = rango_retardo(dificultad)

    tiempo_ms = tiempo_pregunta * 1000
    minimo_ms = div(tiempo_ms * porcentaje_minimo, 100)
    maximo_ms = div(tiempo_ms * porcentaje_maximo, 100)

    retardo_ms = Enum.random(minimo_ms..maximo_ms)

    {letra, retardo_ms}
  end

  def decidir(_dificultad, _nivel_pregunta, _respuesta_correcta, _tiempo_pregunta) do
    {:error, :argumentos_invalidos}
  end

  defp probabilidad_acierto(:facil, :basico), do: 40
  defp probabilidad_acierto(:facil, :intermedio), do: 30
  defp probabilidad_acierto(:facil, :avanzado), do: 20

  defp probabilidad_acierto(:dificil, :basico), do: 80
  defp probabilidad_acierto(:dificil, :intermedio), do: 70
  defp probabilidad_acierto(:dificil, :avanzado), do: 60

  defp rango_retardo(:facil), do: {40, 90}
  defp rango_retardo(:dificil), do: {10, 40}
end
