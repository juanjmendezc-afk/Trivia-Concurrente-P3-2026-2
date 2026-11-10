defmodule Trivia.BancoPreguntas do
  alias Trivia.Nivel

  @orden_niveles %{basico: 1, intermedio: 2, avanzado: 3}
  @niveles [:basico, :intermedio, :avanzado]

  # Sortea preguntas suficientes y las devuelve ordenadas por dificultad.
  def sortear(preguntas_del_tema, nivel, total)
      when is_list(preguntas_del_tema) and nivel in @niveles and
             is_integer(total) and total > 0 do
    reparto = Nivel.reparto(nivel, total)

    case reparto do
      {:error, _motivo} ->
        {:error, :preguntas_insuficientes}

      cantidades ->
        sortear_por_nivel(preguntas_del_tema, cantidades)
    end
  end

  def sortear(_preguntas_del_tema, _nivel, _total),
    do: {:error, :preguntas_insuficientes}

  defp sortear_por_nivel(preguntas, cantidades) do
    disponibles =
      Enum.group_by(preguntas, fn pregunta ->
        pregunta
        |> obtener(:nivel)
        |> normalizar_nivel()
      end)

    if Enum.all?(@niveles, fn nivel ->
         length(Map.get(disponibles, nivel, [])) >= Map.fetch!(cantidades, nivel)
       end) do
      seleccionadas =
        Enum.flat_map(@niveles, fn nivel ->
          cantidad = Map.fetch!(cantidades, nivel)

          disponibles
          |> Map.get(nivel, [])
          |> Enum.take_random(cantidad)
        end)

      lista_ordenada =
        Enum.sort_by(seleccionadas, fn pregunta ->
          Map.fetch!(@orden_niveles, normalizar_nivel(obtener(pregunta, :nivel)))
        end)

      {:ok, lista_ordenada}
    else
      {:error, :preguntas_insuficientes}
    end
  end

  # Acepta mapas decodificados desde JSON (claves string) y mapas con átomos.
  defp obtener(mapa, clave) do
    Map.get(mapa, Atom.to_string(clave), Map.get(mapa, clave))
  end

  defp normalizar_nivel(nivel) when is_atom(nivel), do: nivel

  defp normalizar_nivel(nivel) when is_binary(nivel) do
    case nivel do
      "basico" -> :basico
      "intermedio" -> :intermedio
      "avanzado" -> :avanzado
      _ -> nil
    end
  end

  defp normalizar_nivel(_nivel), do: nil
end
