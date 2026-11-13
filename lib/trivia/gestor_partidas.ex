defmodule Trivia.GestorPartidas do
  alias Trivia.BancoPreguntas
  alias Trivia.Estadisticas
  alias Trivia.Nivel
  alias Trivia.Persistencia
  alias Trivia.SupervisorPartidas
  alias Trivia.Util

  @nombre :gestor_partidas
  @espera 5000
  @primer_id 1001
  @min_preguntas 1
  @max_preguntas 10

  # ---------- Lógica pura: cada operación devuelve el estado nuevo ----------

  # El estado guarda el banco de preguntas, el contador de ids y quién está en qué partida:
  #   jugadores: %{usuario => id}        partidas: %{id => %{pid:, creador:, receptor:}}
  def nuevo(banco) when is_list(banco) do
    %{banco: banco, siguiente: @primer_id, jugadores: %{}, partidas: %{}}
  end

  # Id de la próxima partida: P-1001, P-1002...
  def id_siguiente(estado), do: "P-#{estado.siguiente}"

  # Validaciones que no necesitan el historial, en este orden:
  # ya en partida, parámetros, tema. Devuelve las preguntas del tema.
  def validar_pedido(estado, usuario, tema, total, tiempo, receptor) do
    cond do
      Map.has_key?(estado.jugadores, usuario) ->
        {:error, :ya_en_partida}

      not parametros_validos?(tema, total, tiempo, receptor) ->
        {:error, :parametros_invalidos}

      true ->
        preguntas_del_tema(estado.banco, tema)
    end
  end

  # Los temas del banco van en minúscula: "Historia" e "historia" son el mismo tema.
  # Lo que no es texto se deja igual y lo rechaza validar_pedido/6.
  def normalizar_tema(tema) when is_binary(tema), do: String.downcase(tema)
  def normalizar_tema(tema), do: tema

  # Con el nivel ya calculado, verifica que el tema tenga preguntas de cada nivel.
  # Sortear usa Nivel.reparto/2; aquí el sorteo solo sirve para verificar.
  def verificar_preguntas(preguntas_del_tema, nivel, total) do
    case BancoPreguntas.sortear(preguntas_del_tema, nivel, total) do
      {:ok, _sorteo} -> :ok
      {:error, motivo} -> {:error, motivo}
    end
  end

  # Anota la partida nueva (con el receptor del creador, para avisarle si se reinicia)
  # y deja listo el id siguiente
  def registrar_partida(estado, id, pid, creador, receptor) do
    %{
      estado
      | siguiente: estado.siguiente + 1,
        jugadores: Map.put(estado.jugadores, creador, id),
        partidas: Map.put(estado.partidas, id, %{pid: pid, creador: creador, receptor: receptor})
    }
  end

  # Aviso {:partida_iniciada, id, pid}. Devuelve el estado y si hubo reinicio:
  #   :reinicio   el id ya existía con otro pid (el supervisor la levantó de nuevo)
  #   :sin_cambio primer arranque (mismo pid) o id desconocido
  def registrar_pid(estado, id, pid) do
    case Map.fetch(estado.partidas, id) do
      {:ok, %{pid: ^pid}} ->
        {estado, :sin_cambio}

      {:ok, partida} ->
        partidas = Map.put(estado.partidas, id, %{partida | pid: pid})
        {%{estado | partidas: partidas}, :reinicio}

      :error ->
        partidas = Map.put(estado.partidas, id, %{pid: pid, creador: nil, receptor: nil})
        {%{estado | partidas: partidas}, :sin_cambio}
    end
  end

  # Receptor del creador de una partida (nil si no se conoce)
  def receptor_de(estado, id) do
    case Map.fetch(estado.partidas, id) do
      {:ok, %{receptor: receptor}} -> receptor
      :error -> nil
    end
  end

  # La partida terminó: se olvida y sus jugadores quedan libres
  def liberar(estado, id) do
    %{
      estado
      | jugadores:
          Map.reject(estado.jugadores, fn {_usuario, id_jugador} -> id_jugador == id end),
        partidas: Map.delete(estado.partidas, id)
    }
  end

  # Partida en la que está el usuario
  def partida_de(estado, usuario) do
    with {:ok, id} <- Map.fetch(estado.jugadores, usuario),
         {:ok, %{pid: pid}} <- Map.fetch(estado.partidas, id) do
      {:ok, id, pid}
    else
      :error -> {:error, :sin_partida}
    end
  end

  # Preguntas entre 1 y 10, tiempo mayor a 0, tema en texto y receptor un pid
  defp parametros_validos?(tema, total, tiempo, receptor) do
    is_binary(tema) and is_integer(total) and total in @min_preguntas..@max_preguntas and
      is_integer(tiempo) and tiempo > 0 and is_pid(receptor)
  end

  defp preguntas_del_tema(banco, tema) do
    case Enum.filter(banco, fn pregunta -> pregunta.tema == tema end) do
      [] -> {:error, :tema_inexistente}
      preguntas -> {:ok, preguntas}
    end
  end

  # ---------- Funciones cliente: solo envían mensajes ----------

  # Carga el banco de preguntas y arranca el proceso con nombre
  def iniciar do
    case Process.whereis(@nombre) do
      nil ->
        with {:ok, banco} <- Persistencia.cargar_preguntas() do
          pid = spawn(fn -> loop(nuevo(banco)) end)
          Process.register(pid, @nombre)
          {:ok, pid}
        end

      _pid ->
        {:error, :ya_iniciado}
    end
  end

  def crear_partida(usuario, tema, total, tiempo, receptor) do
    pedir(:crear_partida, {usuario, tema, total, tiempo, receptor})
  end

  def agregar_bot(usuario, dificultad), do: pedir(:agregar_bot, {usuario, dificultad})

  def abandonar(usuario), do: pedir(:abandonar, usuario)

  def iniciar_partida(usuario), do: pedir(:iniciar_partida, usuario)

  def responder(usuario, letra), do: pedir(:responder, {usuario, letra})

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
      {:crear_partida, remitente, {usuario, tema, total, tiempo, receptor}} ->
        {respuesta, estado} = crear_en(estado, usuario, tema, total, tiempo, receptor)
        send(remitente, {:crear_partida, respuesta})
        loop(estado)

      {:agregar_bot, remitente, {usuario, dificultad}} ->
        send(remitente, {:agregar_bot, agregar_bot_en(estado, usuario, dificultad)})
        loop(estado)

      {:abandonar, remitente, usuario} ->
        # El estado no cambia aquí: la Partida avisa con :partida_terminada
        send(remitente, {:abandonar, abandonar_en(estado, usuario)})
        loop(estado)

      {:iniciar_partida, remitente, usuario} ->
        send(remitente, {:iniciar_partida, iniciar_en(estado, usuario)})
        loop(estado)

      {:responder, remitente, {usuario, letra}} ->
        send(remitente, {:responder, responder_en(estado, usuario, letra)})
        loop(estado)

      # La Partida avisa al arrancar (y al reiniciarse). Si es un reinicio, se avisa al creador.
      {:partida_iniciada, id, pid} ->
        {estado, que_paso} = registrar_pid(estado, id, pid)
        avisar_reinicio(que_paso, receptor_de(estado, id))
        loop(estado)

      {:partida_terminada, id} ->
        loop(liberar(estado, id))

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
  defp crear_en(estado, usuario, tema, total, tiempo, receptor) do
    tema = normalizar_tema(tema)

    with {:ok, preguntas_del_tema} <-
           validar_pedido(estado, usuario, tema, total, tiempo, receptor),
         nivel = nivel_del_creador(usuario, tema),
         :ok <- verificar_preguntas(preguntas_del_tema, nivel, total),
         id = id_siguiente(estado),
         argumentos = %{
           id: id,
           creador: usuario,
           tema: tema,
           nivel: nivel,
           total_preguntas: total,
           tiempo: tiempo,
           preguntas_tema: preguntas_del_tema,
           receptor: receptor
         },
         {:ok, pid} <- SupervisorPartidas.crear_partida(argumentos) do
      {{:ok, %{id: id, nivel: nivel}}, registrar_partida(estado, id, pid, usuario, receptor)}
    else
      {:error, motivo} -> {{:error, motivo}, estado}
    end
  end

  # Solo send: el gestor nunca espera al Receptor
  defp avisar_reinicio(:reinicio, receptor) when is_pid(receptor) do
    send(
      receptor,
      {:aviso, "Tu partida falló y se reinició sin progreso. Agrega bots y ejecuta start_game."}
    )
  end

  defp avisar_reinicio(_que_paso, _receptor), do: :ok

  # Nivel del jugador en el tema: puntaje acumulado en el historial -> nivel
  defp nivel_del_creador(usuario, tema) do
    historial()
    |> Estadisticas.puntaje_en_tema(usuario, tema)
    |> Nivel.calcular()
  end

  # Líneas del historial; si no se puede leer se informa y se sigue con 0 puntos
  defp historial do
    case Persistencia.leer_historial() do
      {:ok, lineas} ->
        lineas

      {:error, motivo} ->
        Util.imprimir("No se pudo leer el historial: #{inspect(motivo)}", :error)
        []
    end
  end

  defp agregar_bot_en(estado, usuario, dificultad) do
    with {:ok, _id, pid} <- partida_viva(estado, usuario) do
      llamar_partida(pid, {:add_bot, dificultad})
    end
  end

  defp abandonar_en(estado, usuario) do
    with {:ok, id, pid} <- partida_viva(estado, usuario),
         {:ok, resultado} <- llamar_partida(pid, {:abandonar, usuario}) do
      # resultado es :cancelada (en espera) o :abandonada (en curso)
      {:ok, %{id: id, resultado: resultado}}
    end
  end

  defp iniciar_en(estado, usuario) do
    with {:ok, _id, pid} <- partida_viva(estado, usuario) do
      llamar_partida(pid, {:start_game, usuario})
    end
  end

  defp responder_en(estado, usuario, letra) do
    with {:ok, _id, pid} <- partida_viva(estado, usuario) do
      llamar_partida(pid, {:responder, usuario, letra})
    end
  end

  # Llama a la Partida desde un proceso aparte que el gestor vigila. Si la partida termina
  # sin responder (por ejemplo, vence el tiempo de la última ronda justo cuando llega un
  # answer), el que cae es el auxiliar: el gestor recibe :DOWN y sigue atendiendo.
  defp llamar_partida(pid, peticion) do
    gestor = self()

    {auxiliar, referencia} =
      spawn_monitor(fn ->
        send(gestor, {:respuesta_partida, self(), GenServer.call(pid, peticion)})
      end)

    receive do
      {:respuesta_partida, ^auxiliar, respuesta} ->
        Process.demonitor(referencia, [:flush])
        respuesta

      {:DOWN, ^referencia, :process, ^auxiliar, _razon} ->
        {:error, :sin_partida}
    end
  end

  # Antes de llamar a una Partida se comprueba que siga viva
  defp partida_viva(estado, usuario) do
    with {:ok, id, pid} <- partida_de(estado, usuario) do
      if Process.alive?(pid) do
        {:ok, id, pid}
      else
        {:error, :sin_partida}
      end
    end
  end
end
