defmodule Trivia.Nivel do
  @puntaje_intermedio 60
  @puntaje_avanzado 180
  @niveles [:basico, :intermedio, :avanzado]

  # Determina el nivel a partir del puntaje acumulado en un tema.
  def calcular(puntaje) when is_integer(puntaje) and puntaje < @puntaje_intermedio,
    do: :basico

  def calcular(puntaje)
      when is_integer(puntaje) and puntaje < @puntaje_avanzado,
      do: :intermedio

  def calcular(puntaje) when is_integer(puntaje), do: :avanzado
  def calcular(_puntaje), do: {:error, :puntaje_invalido}

  # Calcula cuántas preguntas corresponden a cada nivel.
  def reparto(nivel, total)
      when nivel in @niveles and is_integer(total) and total > 0 do
    porcentajes =
      case nivel do
        :basico -> %{basico: 70, intermedio: 30, avanzado: 0}
        :intermedio -> %{basico: 20, intermedio: 60, avanzado: 20}
        :avanzado -> %{basico: 0, intermedio: 30, avanzado: 70}
      end

    cantidades =
      Map.new(@niveles, fn nivel_pregunta ->
        porcentaje = Map.fetch!(porcentajes, nivel_pregunta)
        {nivel_pregunta, div(total * porcentaje, 100)}
      end)

    sobrantes = total - Enum.sum(Map.values(cantidades))
    Map.update!(cantidades, nivel, &(&1 + sobrantes))
  end

  def reparto(_nivel, _total), do: {:error, :parametros_invalidos}
end
