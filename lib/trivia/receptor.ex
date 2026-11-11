defmodule Trivia.Receptor do
  alias Trivia.Util

  @espera 5000

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

  # Convierte una notificación del servidor en el texto que se muestra.
  # El contenido de pregunta, cierre y fin se define en T6; por ahora se imprime tal cual.
  def formatear({:aviso, texto}) when is_binary(texto), do: {:ok, texto}
  def formatear({:pregunta, datos}), do: {:ok, "[Pregunta] " <> inspect(datos)}
  def formatear({:cierre_ronda, datos}), do: {:ok, "[Cierre de ronda] " <> inspect(datos)}
  def formatear({:fin_partida, datos}), do: {:ok, "[Fin de la partida] " <> inspect(datos)}
  def formatear(_otro), do: {:error, :notificacion_desconocida}

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
