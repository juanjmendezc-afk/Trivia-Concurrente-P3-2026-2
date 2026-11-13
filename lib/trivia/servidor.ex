defmodule Trivia.Servidor do
  alias Trivia.GestorJugadores
  alias Trivia.GestorPartidas
  alias Trivia.Persistencia
  alias Trivia.SupervisorPartidas
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

    detener_gestores()
    :ok
  end

  # Detiene lo que haya en marcha, en orden inverso al arranque.
  # Las partidas mueren con su supervisor.
  defp detener_gestores do
    GestorPartidas.detener()
    SupervisorPartidas.detener()
    GestorJugadores.detener()
    Persistencia.detener()
  end

  defp arrancar(carpeta) do
    with {:ok, _pid} <- Persistencia.iniciar(carpeta) do
      case arrancar_servidor() do
        {:ok, pid} ->
          {:ok, pid}

        {:error, motivo} ->
          # Si algo falló a medias no se deja nada en marcha
          detener_gestores()
          {:error, motivo}
      end
    end
  end

  defp arrancar_servidor do
    with {:ok, usuarios} <- Persistencia.cargar_usuarios(),
         {:ok, _pid} <- GestorJugadores.iniciar(usuarios),
         {:ok, _pid} <- SupervisorPartidas.iniciar(),
         {:ok, _pid} <- GestorPartidas.iniciar() do
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

      # Peticiones de partida: exigen sesión y se pasan a GestorPartidas con el usuario
      {:create_game, pid_cliente, tema, preguntas, tiempo, receptor} when is_pid(pid_cliente) ->
        atender(pid_cliente, fn usuario ->
          GestorPartidas.crear_partida(usuario, tema, preguntas, tiempo, receptor)
        end)

        loop(monitores)

      {:add_bot, pid_cliente, dificultad} when is_pid(pid_cliente) ->
        atender(pid_cliente, fn usuario -> GestorPartidas.agregar_bot(usuario, dificultad) end)
        loop(monitores)

      {:leave_game, pid_cliente} when is_pid(pid_cliente) ->
        atender(pid_cliente, &GestorPartidas.abandonar/1)
        loop(monitores)

      {:start_game, pid_cliente} when is_pid(pid_cliente) ->
        atender(pid_cliente, &GestorPartidas.iniciar_partida/1)
        loop(monitores)

      {:answer, pid_cliente, letra} when is_pid(pid_cliente) ->
        atender(pid_cliente, fn usuario -> GestorPartidas.responder(usuario, letra) end)
        loop(monitores)

      {:score, pid_cliente} when is_pid(pid_cliente) ->
        atender(pid_cliente, &GestorJugadores.score/1)
        loop(monitores)

      {:ranking, pid_cliente, tema} when is_pid(pid_cliente) ->
        atender(pid_cliente, fn _usuario -> GestorJugadores.ranking(tema) end)
        loop(monitores)

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

  # Identifica al usuario por el pid del cliente y ejecuta la acción con su nombre
  defp atender(pid_cliente, accion) do
    respuesta =
      with {:ok, usuario} <- GestorJugadores.usuario_de(pid_cliente) do
        accion.(usuario)
      end

    responder(pid_cliente, respuesta)
  end

  # Punto único para cerrar una sesión (disconnect o cliente caído).
  # Si el usuario está en una partida, primero se aplica la regla de abandono.
  defp cerrar_sesion(pid_cliente) do
    with {:ok, usuario} <- GestorJugadores.usuario_de(pid_cliente) do
      # Sin partida (o con cualquier otro error) la sesión se cierra igual
      _resultado = GestorPartidas.abandonar(usuario)
    end

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

  # Petición que el servidor no conoce: exige sesión y luego se rechaza
  defp rechazar(pid_cliente) do
    with {:ok, _usuario} <- GestorJugadores.usuario_de(pid_cliente) do
      {:error, :comando_invalido}
    end
  end
end
