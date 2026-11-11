defmodule Trivia.Receptor do
  alias Trivia.Util

  @espera 5000
  @letras ["A", "B", "C", "D"]

  # ---------- Funciones cliente ----------

  # Arranca el receptor enlazado a quien lo crea (si el cliente muere, él también)
  def iniciar do
    spawn_link(fn -> loop() end)
  end

  # Pide al receptor que termine y espera su confirmación
  def detener(pid) do
    if Process.alive?(pid) do
      send(pid, {:detener, self()})

      receive do
        {:receptor_detenido, ^pid} -> :ok
      after
        @espera -> :ok
      end
    else
      :ok
    end
  end

  # ---------- Lógica pura ----------

  # Convierte una notificación del servidor en el texto que se muestra
  def formatear({:aviso, texto}) when is_binary(texto), do: {:ok, texto}

  def formatear(
        {:pregunta,
         %{
           numero: numero,
           total: total,
           enunciado: enunciado,
           opciones: %{"A" => _, "B" => _, "C" => _, "D" => _} = opciones,
           tiempo: tiempo
         }}
      ) do
    lineas =
      ["", "--- Pregunta #{numero} de #{total} (#{tiempo} s) ---", enunciado] ++
        Enum.map(@letras, fn letra -> "  #{letra}) #{opciones[letra]}" end) ++
        ["Responde con: answer <letra>"]

    {:ok, Enum.join(lineas, "\n")}
  end

  def formatear(
        {:cierre_ronda,
         %{numero: numero, respuesta_correcta: correcta, resultados: resultados}}
      )
      when is_list(resultados) do
    lineas =
      ["", "--- Cierre de la ronda #{numero} ---", "Respuesta correcta: #{correcta}"] ++
        Enum.map(resultados, fn resultado ->
          "  #{resultado.jugador}: #{con_signo(resultado.puntos_ronda)} " <>
            "(acumulado #{resultado.acumulado})"
        end)

    {:ok, Enum.join(lineas, "\n")}
  end

  def formatear(
        {:fin_partida,
         %{id: id, tema: tema, nivel: nivel, ranking: ranking, ganadores: ganadores}}
      )
      when is_list(ranking) and is_list(ganadores) do
    lineas =
      [
        "",
        "=== Fin de la partida #{id} (tema #{tema}, nivel #{nombre_nivel(nivel)}) ===",
        "Ranking final:"
      ] ++
        Enum.map(ranking, fn {posicion, jugador, puntaje} ->
          "  #{posicion}. #{jugador}: #{puntaje}"
        end) ++
        [texto_ganadores(ganadores)]

    {:ok, Enum.join(lineas, "\n")}
  end

  def formatear(_otro), do: {:error, :notificacion_desconocida}

  # Los puntos de la ronda se muestran con signo: +14, -5, 0
  defp con_signo(puntos) when puntos > 0, do: "+#{puntos}"
  defp con_signo(puntos), do: "#{puntos}"

  # Nombre del nivel para mostrarlo al jugador
  defp nombre_nivel(:basico), do: "básico"
  defp nombre_nivel(nivel), do: "#{nivel}"

  defp texto_ganadores([ganador]), do: "Ganador: #{ganador}"
  defp texto_ganadores(ganadores), do: "Empate, ganadores: #{Enum.join(ganadores, ", ")}"

  # ---------- Bucle del proceso ----------

  defp loop do
    receive do
      {:detener, remitente} ->
        send(remitente, {:receptor_detenido, self()})

      notificacion ->
        mostrar(notificacion)
        loop()
    end
  end

  # Un mensaje que no es una notificación se descarta para no acumularlo
  defp mostrar(notificacion) do
    case formatear(notificacion) do
      {:ok, texto} -> Util.imprimir(texto)
      {:error, :notificacion_desconocida} -> :ok
    end
  end
end
