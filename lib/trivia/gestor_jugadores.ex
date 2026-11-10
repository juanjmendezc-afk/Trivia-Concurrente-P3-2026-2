defmodule Trivia.GestorJugadores do
  alias Trivia.Persistencia
  alias Trivia.Util

  @nombre :gestor_jugadores
  @espera 5000
  @prefijo_bot "bot_"

  # ---------- Lógica pura: cada operación devuelve el estado nuevo ----------

  # El estado guarda los usuarios registrados y las sesiones abiertas
  def nuevo(usuarios) when is_map(usuarios) do
    %{usuarios: usuarios, sesiones: %{}}
  end

  # Abre la sesión de un cliente; si el usuario no existe, lo registra
  def abrir_sesion(estado, pid_cliente, usuario, clave) do
    cond do
      not parametros_validos?(usuario, clave) -> {:error, :parametros_invalidos}
      String.starts_with?(usuario, @prefijo_bot) -> {:error, :usuario_reservado}
      Map.has_key?(estado.sesiones, pid_cliente) -> {:error, :sesion_abierta}
      conectado?(estado, usuario) -> {:error, :ya_conectado}
      true -> verificar_clave(estado, pid_cliente, usuario, clave)
    end
  end

  # Cierra la sesión del cliente y devuelve el usuario que tenía
  def cerrar_sesion(estado, pid_cliente) do
    case Map.pop(estado.sesiones, pid_cliente) do
      {nil, _sesiones} -> {:error, :sin_sesion}
      {usuario, sesiones} -> {:ok, %{estado | sesiones: sesiones}, usuario}
    end
  end

  def buscar_usuario(estado, pid_cliente) do
    case Map.fetch(estado.sesiones, pid_cliente) do
      {:ok, usuario} -> {:ok, usuario}
      :error -> {:error, :sin_sesion}
    end
  end

  # Usuario sin espacios (dividir por espacios lo devuelve entero) y clave no vacía
  defp parametros_validos?(usuario, clave) when is_binary(usuario) and is_binary(clave) do
    String.split(usuario) == [usuario] and clave != ""
  end

  defp parametros_validos?(_usuario, _clave), do: false

  defp conectado?(estado, usuario) do
    Enum.any?(estado.sesiones, fn {_pid, conectado} -> conectado == usuario end)
  end

  defp verificar_clave(estado, pid_cliente, usuario, clave) do
    case Map.fetch(estado.usuarios, usuario) do
      {:ok, ^clave} ->
        {:ok, con_sesion(estado, pid_cliente, usuario), :existente}

      {:ok, _otra_clave} ->
        {:error, :clave_incorrecta}

      :error ->
        registrado = %{estado | usuarios: Map.put(estado.usuarios, usuario, clave)}
        {:ok, con_sesion(registrado, pid_cliente, usuario), :nuevo}
    end
  end

  defp con_sesion(estado, pid_cliente, usuario) do
    %{estado | sesiones: Map.put(estado.sesiones, pid_cliente, usuario)}
  end

  # ---------- Funciones cliente: solo envían mensajes ----------

  # Arranca el proceso con los usuarios ya cargados y lo registra con nombre
  def iniciar(usuarios) when is_map(usuarios) do
    case Process.whereis(@nombre) do
      nil ->
        pid = spawn(fn -> loop(nuevo(usuarios)) end)
        Process.register(pid, @nombre)
        {:ok, pid}

      _pid ->
        {:error, :ya_iniciado}
    end
  end

  def conectar(pid_cliente, usuario, clave) do
    pedir(:conectar, {pid_cliente, usuario, clave})
  end

  def desconectar(pid_cliente), do: pedir(:desconectar, pid_cliente)

  def usuario_de(pid_cliente), do: pedir(:usuario_de, pid_cliente)

  def detener, do: pedir(:detener, nil)

  # Envía la petición y espera la respuesta con la misma etiqueta
  defp pedir(accion, datos) do
    case Process.whereis(@nombre) do
      nil ->
        {:error, :servidor_no_disponible}

      pid ->
        send(pid, {accion, self(), datos})

        receive do
          {^accion, respuesta} -> respuesta
        after
          @espera -> {:error, :servidor_no_disponible}
        end
    end
  end

  # ---------- Bucle del proceso: único dueño del estado ----------

  defp loop(estado) do
    receive do
      {:conectar, remitente, {pid_cliente, usuario, clave}} ->
        {respuesta, estado} = conectar_en(estado, pid_cliente, usuario, clave)
        send(remitente, {:conectar, respuesta})
        loop(estado)

      {:desconectar, remitente, pid_cliente} ->
        {respuesta, estado} = desconectar_en(estado, pid_cliente)
        send(remitente, {:desconectar, respuesta})
        loop(estado)

      {:usuario_de, remitente, pid_cliente} ->
        send(remitente, {:usuario_de, buscar_usuario(estado, pid_cliente)})
        loop(estado)

      {:detener, remitente, _datos} ->
        # Libera el nombre antes de responder para poder reiniciar sin esperas
        Process.unregister(@nombre)
        send(remitente, {:detener, :ok})

      _otro ->
        # Mensaje desconocido: se descarta para no acumularlo
        loop(estado)
    end
  end

  # Devuelve la respuesta para el cliente y el estado resultante
  defp conectar_en(estado, pid_cliente, usuario, clave) do
    case abrir_sesion(estado, pid_cliente, usuario, clave) do
      {:ok, nuevo_estado, tipo} ->
        guardar_si_es_nuevo(tipo, nuevo_estado.usuarios)
        {{:ok, %{usuario: usuario, registrado: tipo == :nuevo}}, nuevo_estado}

      {:error, motivo} ->
        {{:error, motivo}, estado}
    end
  end

  defp desconectar_en(estado, pid_cliente) do
    case cerrar_sesion(estado, pid_cliente) do
      {:ok, nuevo_estado, usuario} -> {{:ok, %{usuario: usuario}}, nuevo_estado}
      {:error, motivo} -> {{:error, motivo}, estado}
    end
  end

  # Un usuario nuevo se guarda en users.json; si falla se informa y se sigue
  defp guardar_si_es_nuevo(:nuevo, usuarios) do
    case Persistencia.guardar_usuarios(usuarios) do
      :ok ->
        :ok

      {:error, motivo} ->
        Util.imprimir("No se pudo guardar users.json: #{inspect(motivo)}", :error)
    end
  end

  defp guardar_si_es_nuevo(:existente, _usuarios), do: :ok
end
