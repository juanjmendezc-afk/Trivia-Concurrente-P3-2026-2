defmodule Trivia.Estadisticas do
  alias Trivia.Nivel

  @prefijo_bot "bot_"

  # Lógica pura: todo se calcula a partir de las líneas del historial (results.log).
  # Formato de una línea: fecha|id|tema|nivel|ganadores|puntajes
  #   2026-11-12 20:15:03|P-1001|historia|basico|pedro|pedro:45,bot_1:30,bot_2:-5

  # ---------- Leer una línea ----------

  # Convierte una línea en un mapa; quita el \r y los espacios del final
  def parsear_linea(linea) when is_binary(linea) do
    case linea |> String.trim_trailing() |> String.split("|") do
      [fecha, id, tema, nivel, ganadores, puntajes] ->
        with :ok <- verificar_textos([fecha, id, tema]),
             {:ok, nivel} <- leer_nivel(nivel),
             {:ok, ganadores} <- leer_ganadores(ganadores),
             {:ok, puntajes} <- leer_puntajes(puntajes) do
          {:ok,
           %{
             fecha: fecha,
             id: id,
             tema: tema,
             nivel: nivel,
             ganadores: ganadores,
             puntajes: puntajes
           }}
        end

      _otra_cantidad ->
        {:error, :linea_invalida}
    end
  end

  def parsear_linea(_otro), do: {:error, :linea_invalida}

  # ---------- Cálculos (las líneas inválidas se saltan y los bots se ignoran) ----------

  # Suma de los puntajes del usuario en las partidas de un tema; 0 si nunca lo jugó
  def puntaje_en_tema(lineas, usuario, tema) do
    lineas
    |> partidas_validas()
    |> Stream.filter(fn partida -> partida.tema == tema end)
    |> Enum.reduce(0, fn partida, total -> total + puntaje_de(partida, usuario) end)
  end

  # Puntaje total, partidas jugadas y, por tema, puntaje y nivel del usuario
  def resumen(lineas, usuario) do
    vacio = %{puntaje: 0, partidas: 0, por_tema: %{}}

    resumen =
      lineas
      |> partidas_validas()
      |> Enum.reduce(vacio, fn partida, acumulado ->
        case buscar_puntaje(partida, usuario) do
          {:ok, puntos} -> sumar_partida(acumulado, partida.tema, puntos)
          :error -> acumulado
        end
      end)

    {:ok, %{resumen | por_tema: agregar_niveles(resumen.por_tema)}}
  end

  # Ranking histórico [{usuario, puntaje}] de mayor a menor; en empate, alfabético.
  # Con tema nil es el ranking global.
  def ranking(lineas, tema) when is_nil(tema) or is_binary(tema) do
    lineas
    |> partidas_validas()
    |> Stream.filter(fn partida -> tema == nil or partida.tema == tema end)
    |> Enum.reduce(%{}, &sumar_humanos/2)
    |> Enum.sort_by(fn {usuario, puntaje} -> {-puntaje, usuario} end)
  end

  # ---------- Ayudas de los cálculos ----------

  # Solo las líneas que se pudieron leer, ya convertidas en mapas
  defp partidas_validas(lineas) do
    Stream.flat_map(lineas, fn linea ->
      case parsear_linea(linea) do
        {:ok, partida} -> [partida]
        {:error, :linea_invalida} -> []
      end
    end)
  end

  defp es_bot?(nombre), do: String.starts_with?(nombre, @prefijo_bot)

  # Puntaje del usuario en una partida; :error si no jugó o si es un bot
  defp buscar_puntaje(partida, usuario) do
    if es_bot?(usuario) do
      :error
    else
      case Enum.find(partida.puntajes, fn {nombre, _puntos} -> nombre == usuario end) do
        {_nombre, puntos} -> {:ok, puntos}
        nil -> :error
      end
    end
  end

  defp puntaje_de(partida, usuario) do
    case buscar_puntaje(partida, usuario) do
      {:ok, puntos} -> puntos
      :error -> 0
    end
  end

  # Agrega una partida al resumen: total, contador y puntaje del tema
  defp sumar_partida(resumen, tema, puntos) do
    %{
      resumen
      | puntaje: resumen.puntaje + puntos,
        partidas: resumen.partidas + 1,
        por_tema: Map.update(resumen.por_tema, tema, puntos, &(&1 + puntos))
    }
  end

  # %{"historia" => 75} -> %{"historia" => %{puntaje: 75, nivel: :intermedio}}
  defp agregar_niveles(por_tema) do
    Map.new(por_tema, fn {tema, puntaje} ->
      {tema, %{puntaje: puntaje, nivel: Nivel.calcular(puntaje)}}
    end)
  end

  # Suma al ranking los puntajes de los jugadores humanos de una partida
  defp sumar_humanos(partida, ranking) do
    partida.puntajes
    |> Enum.reject(fn {nombre, _puntos} -> es_bot?(nombre) end)
    |> Enum.reduce(ranking, fn {nombre, puntos}, acumulado ->
      Map.update(acumulado, nombre, puntos, &(&1 + puntos))
    end)
  end

  # ---------- Ayudas para leer una línea ----------

  # Ningún campo de texto puede venir vacío
  defp verificar_textos(textos) do
    if Enum.any?(textos, &(&1 == "")) do
      {:error, :linea_invalida}
    else
      :ok
    end
  end

  defp leer_nivel("basico"), do: {:ok, :basico}
  defp leer_nivel("intermedio"), do: {:ok, :intermedio}
  defp leer_nivel("avanzado"), do: {:ok, :avanzado}
  defp leer_nivel(_otro), do: {:error, :linea_invalida}

  # "pedro,bot_1" -> {:ok, ["pedro", "bot_1"]}
  defp leer_ganadores(texto) do
    ganadores = String.split(texto, ",")

    case verificar_textos(ganadores) do
      :ok -> {:ok, ganadores}
      error -> error
    end
  end

  # "pedro:45,bot_1:-5" -> {:ok, [{"pedro", 45}, {"bot_1", -5}]}
  defp leer_puntajes(texto) do
    puntajes =
      texto
      |> String.split(",")
      |> Enum.map(&leer_puntaje/1)

    if :error in puntajes do
      {:error, :linea_invalida}
    else
      {:ok, puntajes}
    end
  end

  # "pedro:45" -> {"pedro", 45}; cualquier otra forma -> :error
  defp leer_puntaje(texto) do
    case String.split(texto, ":") do
      [nombre, puntos] when nombre != "" -> a_puntaje(nombre, Integer.parse(puntos))
      _otra_forma -> :error
    end
  end

  defp a_puntaje(nombre, {puntos, ""}), do: {nombre, puntos}
  defp a_puntaje(_nombre, _no_es_entero), do: :error
end
