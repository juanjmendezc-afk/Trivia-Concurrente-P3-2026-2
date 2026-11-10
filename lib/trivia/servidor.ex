defmodule Trivia.Servidor do
  alias Trivia.GestorJugadores
  alias Trivia.Persistencia
  alias Trivia.Util

  @nombre :servidor
  @espera 5000

  # ---------- Arranque y parada ----------

  # Arranque desde la consola del servidor: iex --sname servidor -S mix
  def iniciar do
    if node() == :nonode@nohost do
      Util.imprimir(
        "Aviso: este nodo no tiene nombre y los clientes no podrán conectarse. " <>
          "Arranca con: iex --sname servidor -S mix",
        :error
      )
    end

    with {:ok, pid} <- iniciar(Persistencia.carpeta_datos()) do
      Util.imprimir("Servidor listo en el nodo #{node()}. Esperando clientes...")
      {:ok, pid}
    end
  end

  # Arranca todo el lado servidor con los archivos en la carpeta indicada
  def iniciar(carpeta) do
    case Process.whereis(@nombre) do
      nil -> arrancar(carpeta)
      _pid -> {:error, :ya_iniciado}
    end
  end

  # Detiene lo que esté en marcha; sirve también para limpiar tras un fallo
  def detener do
    case Process.whereis(@nombre) do
      nil ->
        :ok

      pid ->
        send(pid, {:detener_servidor, self()})

        receive do
          {:detener_servidor, :ok} -> :ok
        after
          @espera -> :ok
        end
    end

    GestorJugadores.detener()
    Persistencia.detener()
    :ok
  end

  defp arrancar(carpeta) do
    with {:ok, _pid} <- Persistencia.iniciar(carpeta) do
      case arrancar_servidor() do
        {:ok, pid} ->
          {:ok, pid}

        {:error, motivo} ->
          Persistencia.detener()
          {:error, motivo}
      end
    end
  end

  defp arrancar_servidor do
    with {:ok, usuarios} <- Persistencia.cargar_usuarios(),
         {:ok, _pid} <- GestorJugadores.iniciar(usuarios) do
      pid = spawn(fn -> loop(%{}) end)
      Process.register(pid, @nombre)
      {:ok, pid}
    end
  end

  # ---------- Bucle del proceso ----------

  # `monitores` guarda la referencia con la que se vigila a cada cliente conectado
  defp loop(monitores) do
    receive do
      {:connect, pid_cliente, usuario, clave} when is_pid(pid_cliente) ->
        respuesta = GestorJugadores.conectar(pid_cliente, usuario, clave)
        responder(pid_cliente, respuesta)
        loop(vigilar(monitores, pid_cliente, respuesta))

      {:disconnect, pid_cliente} when is_pid(pid_cliente) ->
        responder(pid_cliente, cerrar_sesion(pid_cliente))
        loop(dejar_de_vigilar(monitores, pid_cliente))

      # Un cliente conectado desapareció (cerró la consola o se cayó el nodo)
      {:DOWN, _referencia, :process, pid_cliente, _razon} ->
        cerrar_sesion(pid_cliente)
        loop(Map.delete(monitores, pid_cliente))

      {:detener_servidor, remitente} ->
        Process.unregister(@nombre)
        send(remitente, {:detener_servidor, :ok})

      # Cualquier otra petición {accion, pid_cliente, ...}
      peticion when is_tuple(peticion) and tuple_size(peticion) >= 2 and is_pid(elem(peticion, 1)) ->
        pid_cliente = elem(peticion, 1)
        responder(pid_cliente, rechazar(pid_cliente))
        loop(monitores)

      _otro ->
        # Mensaje desconocido: se descarta para no acumularlo
        loop(monitores)
    end
  end

  defp responder(pid_cliente, respuesta) do
    send(pid_cliente, {:respuesta, respuesta})
  end

  # Punto único para cerrar una sesión; en T7 aquí se aplicará la regla de abandono
  defp cerrar_sesion(pid_cliente) do
    GestorJugadores.desconectar(pid_cliente)
  end

  # Si la conexión fue exitosa se vigila al cliente, una sola vez
  defp vigilar(monitores, pid_cliente, {:ok, _datos}) do
    if Map.has_key?(monitores, pid_cliente) do
      monitores
    else
      Map.put(monitores, pid_cliente, Process.monitor(pid_cliente))
    end
  end

  defp vigilar(monitores, _pid_cliente, {:error, _motivo}), do: monitores

  defp dejar_de_vigilar(monitores, pid_cliente) do
    case Map.pop(monitores, pid_cliente) do
      {nil, monitores} ->
        monitores

      {referencia, monitores} ->
        Process.demonitor(referencia, [:flush])
        monitores
    end
  end

  # Petición que aún no tiene implementación: exige sesión y luego se rechaza
  defp rechazar(pid_cliente) do
    with {:ok, _usuario} <- GestorJugadores.usuario_de(pid_cliente) do
      {:error, :comando_invalido}
    end
  end
end
