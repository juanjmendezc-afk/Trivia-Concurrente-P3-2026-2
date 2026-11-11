defmodule Trivia.Puntaje do
  @niveles [:basico, :intermedio, :avanzado]
  @resultados [:correcta, :incorrecta, :sin_responder]
  @max_bonificacion 5

  # Puntos de un jugador en una ronda. `tiempo_pregunta` va en segundos y
  # `ms_restantes` es lo que faltaba para cerrar cuando llegó la respuesta.
  def calcular(nivel_pregunta, resultado, ms_restantes, tiempo_pregunta)
      when nivel_pregunta in @niveles and resultado in @resultados and
             is_integer(ms_restantes) and is_integer(tiempo_pregunta) and tiempo_pregunta > 0 do
    puntos(nivel_pregunta, resultado, ms_restantes, tiempo_pregunta)
  end

  def calcular(_nivel_pregunta, _resultado, _ms_restantes, _tiempo_pregunta) do
    {:error, :argumentos_invalidos}
  end

  # Solo las correctas reciben bonificación por rapidez
  defp puntos(nivel, :correcta, ms_restantes, tiempo) do
    puntos_correcta(nivel) + bonificacion(ms_restantes, tiempo)
  end

  defp puntos(nivel, :incorrecta, _ms_restantes, _tiempo), do: puntos_incorrecta(nivel)
  defp puntos(_nivel, :sin_responder, _ms_restantes, _tiempo), do: 0

  defp puntos_correcta(:basico), do: 10
  defp puntos_correcta(:intermedio), do: 15
  defp puntos_correcta(:avanzado), do: 20

  defp puntos_incorrecta(:basico), do: -5
  defp puntos_incorrecta(:intermedio), do: -8
  defp puntos_incorrecta(:avanzado), do: -10

  # De 0 a 5 según la fracción del tiempo que quedaba; se trunca con div
  defp bonificacion(ms_restantes, tiempo) do
    tiempo_ms = tiempo * 1000
    div(@max_bonificacion * limitar(ms_restantes, tiempo_ms), tiempo_ms)
  end

  # Deja el valor dentro de 0..maximo
  defp limitar(valor, _maximo) when valor < 0, do: 0
  defp limitar(valor, maximo) when valor > maximo, do: maximo
  defp limitar(valor, _maximo), do: valor
end
