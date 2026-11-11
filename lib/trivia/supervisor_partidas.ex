defmodule Trivia.SupervisorPartidas do
  # DynamicSupervisor: arranca partidas cuando se piden, no al iniciar
  @nombre :supervisor_partidas

  # Arranca el supervisor y lo registra con nombre
  def iniciar do
    case Process.whereis(@nombre) do
      nil ->
        with {:ok, pid} <- DynamicSupervisor.start_link(strategy: :one_for_one, name: @nombre) do
          # start_link lo enlaza a quien lo arrancó; se suelta para que viva
          # por su cuenta, igual que los demás procesos del servidor
          Process.unlink(pid)
          {:ok, pid}
        end

      _pid ->
        {:error, :ya_iniciado}
    end
  end

  # Arranca una Partida bajo supervisión (su child_spec ya dice restart: :transient)
  def crear_partida(argumentos) do
    case Process.whereis(@nombre) do
      nil ->
        {:error, :servidor_no_disponible}

      _pid ->
        case DynamicSupervisor.start_child(@nombre, {Trivia.Partida, argumentos}) do
          {:ok, pid} -> {:ok, pid}
          {:error, motivo} -> {:error, motivo}
          _otro -> {:error, :partida_no_creada}
        end
    end
  end

  # Detiene el supervisor y, con él, todas las partidas
  def detener do
    case Process.whereis(@nombre) do
      nil -> :ok
      pid -> DynamicSupervisor.stop(pid)
    end
  end
end
