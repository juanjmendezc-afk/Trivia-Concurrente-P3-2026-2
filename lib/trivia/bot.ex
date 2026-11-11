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

  # ---------- Proceso del bot (T6) ----------

  # Arranca el bot enlazado a quien lo crea (la partida) y devuelve su pid
  def iniciar(nombre, dificultad, pid_partida) do
    bot = %{nombre: nombre, dificultad: dificultad, partida: pid_partida}
    spawn_link(fn -> loop(bot, 0) end)
  end

  # `ronda` es el número de la última pregunta recibida
  defp loop(bot, ronda) do
    receive do
      # La misma notificación que recibe un cliente
      {:pregunta, datos} ->
        loop(bot, programar_respuesta(bot, datos, ronda))

      # El pin descarta una respuesta programada para una ronda que ya pasó
      {:responder, ^ronda, letra} ->
        responder(bot, letra)
        loop(bot, ronda)

      # La partida terminó: el bot deja su bucle
      {:fin_partida, _datos} ->
        :ok

      _otro ->
        loop(bot, ronda)
    end
  end

  # Pide a su partida el nivel y la respuesta, decide y programa el envío.
  # Devuelve el número de la ronda que quedó pendiente de responder.
  defp programar_respuesta(bot, datos, ronda) do
    with {:ok, %{numero: numero, nivel: nivel, respuesta: correcta}} <-
           Trivia.Partida.datos_pregunta(bot.partida),
         {letra, retardo_ms} <- decidir(bot.dificultad, nivel, correcta, datos.tiempo) do
      Process.send_after(self(), {:responder, numero, letra}, retardo_ms)
      numero
    else
      {:error, _motivo} -> ronda
    end
  end

  # Responde por el mismo mensaje que un humano, sin camino especial
  defp responder(bot, letra) do
    if Process.alive?(bot.partida) do
      GenServer.call(bot.partida, {:responder, bot.nombre, letra})
    end
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
