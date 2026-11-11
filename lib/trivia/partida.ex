defmodule Trivia.Partida do
  # Cada partida es un GenServer. Si termina mal, el supervisor la reinicia (:transient)
  use GenServer, restart: :transient

  alias Trivia.BancoPreguntas
  alias Trivia.Bot
  alias Trivia.Persistencia
  alias Trivia.Puntaje
  alias Trivia.Util

  @gestor :gestor_partidas
  @max_jugadores 4
  @min_bots 2
  @niveles [:basico, :intermedio, :avanzado]
  @dificultades [:facil, :dificil]
  @letras ["A", "B", "C", "D"]
  # Pausa entre rondas; las pruebas la acortan con el argumento pausa_ms
  @pausa_ms 3000

  # Las claves sin valor por defecto son obligatorias
  @enforce_keys [
    :id,
    :creador,
    :tema,
    :nivel,
    :total_preguntas,
    :tiempo,
    :preguntas_tema,
    :receptor
  ]
  defstruct [
    :id,
    :creador,
    :tema,
    :nivel,
    :total_preguntas,
    :tiempo,
    :preguntas_tema,
    :receptor,
    estado: :esperando,
    # Bots como %{nombre:, dificultad:, pid:}, el más nuevo primero
    bots: [],
    pausa_ms: @pausa_ms,
    # Preguntas sorteadas que faltan por jugar (la primera es la siguiente)
    preguntas: [],
    # Cuántas rondas se han abierto
    numero_ronda: 0,
    # Ronda abierta: %{numero:, pregunta:, inicio:, respuestas: %{jugador => {letra, ms_restantes}}}
    ronda: nil,
    # Acumulado de cada jugador: %{jugador => puntos}
    puntajes: %{}
  ]

  # ---------- Lógica pura: cada operación devuelve la partida nueva ----------

  # Constructor con validación: la partida nace en espera, con solo el creador
  def nueva(
        %{
          id: id,
          creador: creador,
          tema: tema,
          nivel: nivel,
          total_preguntas: total_preguntas,
          tiempo: tiempo,
          preguntas_tema: preguntas_tema,
          receptor: receptor
        } = argumentos
      )
      when is_binary(id) and is_binary(creador) and is_binary(tema) and nivel in @niveles and
             is_integer(total_preguntas) and total_preguntas > 0 and
             is_integer(tiempo) and tiempo > 0 and
             is_list(preguntas_tema) and is_pid(receptor) do
    # La pausa es opcional: si no viene, son los 3 segundos del enunciado
    pausa_ms = Map.get(argumentos, :pausa_ms, @pausa_ms)

    if is_integer(pausa_ms) and pausa_ms >= 0 do
      {:ok,
       %__MODULE__{
         id: id,
         creador: creador,
         tema: tema,
         nivel: nivel,
         total_preguntas: total_preguntas,
         tiempo: tiempo,
         preguntas_tema: preguntas_tema,
         receptor: receptor,
         pausa_ms: pausa_ms
       }}
    else
      {:error, :parametros_invalidos}
    end
  end

  def nueva(_argumentos), do: {:error, :parametros_invalidos}

  # El creador más los bots
  def cantidad_jugadores(partida), do: 1 + length(partida.bots)

  # Nombres en orden de entrada: el creador y luego bot_1, bot_2...
  def jugadores(partida) do
    [partida.creador | partida.bots |> Enum.reverse() |> Enum.map(fn bot -> bot.nombre end)]
  end

  # Agrega un bot. Su proceso arranca en start_game; hasta entonces el pid es nil.
  def agregar_bot(%__MODULE__{estado: estado}, _dificultad) when estado != :esperando do
    {:error, :partida_iniciada}
  end

  def agregar_bot(partida, dificultad) when dificultad in @dificultades do
    if cantidad_jugadores(partida) >= @max_jugadores do
      {:error, :partida_llena}
    else
      nombre = "bot_#{length(partida.bots) + 1}"
      bot = %{nombre: nombre, dificultad: dificultad, pid: nil}
      {:ok, %{partida | bots: [bot | partida.bots]}, nombre}
    end
  end

  def agregar_bot(_partida, _dificultad), do: {:error, :parametros_invalidos}

  # ¿Puede este usuario iniciar la partida? Solo el creador, en espera y con 2 bots o más
  def validar_inicio(%__MODULE__{creador: creador} = partida, creador) do
    cond do
      partida.estado != :esperando -> {:error, :partida_iniciada}
      length(partida.bots) < @min_bots -> {:error, :bots_insuficientes}
      true -> :ok
    end
  end

  def validar_inicio(_partida, _otro_usuario), do: {:error, :sin_partida}

  # Pasa a en curso con las preguntas ya sorteadas y todos los jugadores en 0
  def iniciar(%__MODULE__{estado: :esperando} = partida, preguntas) when is_list(preguntas) do
    puntajes = Map.new(jugadores(partida), fn jugador -> {jugador, 0} end)
    {:ok, %{partida | estado: :en_curso, preguntas: preguntas, puntajes: puntajes}}
  end

  def iniciar(_partida, _preguntas), do: {:error, :partida_iniciada}

  # Abre la ronda siguiente y devuelve lo que se envía a los jugadores.
  # `ahora_ms` es la hora de inicio; entra como argumento para que la función sea pura.
  def abrir_ronda(
        %__MODULE__{estado: :en_curso, ronda: nil, preguntas: [pregunta | resto]} = partida,
        ahora_ms
      )
      when is_integer(ahora_ms) do
    numero = partida.numero_ronda + 1
    ronda = %{numero: numero, pregunta: pregunta, inicio: ahora_ms, respuestas: %{}}

    # Nunca van la respuesta correcta ni el nivel de la pregunta
    datos = %{
      numero: numero,
      total: partida.total_preguntas,
      enunciado: pregunta.enunciado,
      opciones: pregunta.opciones,
      tiempo: partida.tiempo
    }

    {:ok, %{partida | preguntas: resto, numero_ronda: numero, ronda: ronda}, datos}
  end

  def abrir_ronda(_partida, _ahora_ms), do: {:error, :sin_preguntas}

  # Registra la respuesta de un jugador con los ms que quedaban cuando llegó a la partida
  def responder(%__MODULE__{ronda: nil}, _jugador, _letra, _ahora_ms) do
    {:error, :sin_ronda_abierta}
  end

  def responder(partida, jugador, letra, ahora_ms)
      when letra in @letras and is_integer(ahora_ms) do
    ronda = partida.ronda

    cond do
      jugador not in jugadores(partida) ->
        {:error, :sin_partida}

      # Solo cuenta la primera respuesta
      Map.has_key?(ronda.respuestas, jugador) ->
        {:error, :respuesta_repetida}

      true ->
        respuesta = {letra, ms_restantes(partida, ahora_ms)}
        respuestas = Map.put(ronda.respuestas, jugador, respuesta)
        {:ok, %{partida | ronda: %{ronda | respuestas: respuestas}}}
    end
  end

  # Letra fuera de A–D: se rechaza sin consumir la respuesta
  def responder(_partida, _jugador, _letra, _ahora_ms), do: {:error, :letra_invalida}

  def todos_respondieron?(%__MODULE__{ronda: nil}), do: false

  def todos_respondieron?(partida) do
    map_size(partida.ronda.respuestas) == cantidad_jugadores(partida)
  end

  # No quedan preguntas por abrir
  def ultima_ronda?(partida), do: partida.preguntas == []

  # Cierra la ronda abierta: calcula los puntos de cada jugador y los acumula
  def cerrar_ronda(%__MODULE__{ronda: nil}), do: {:error, :sin_ronda_abierta}

  def cerrar_ronda(partida) do
    ronda = partida.ronda

    resultados =
      Enum.map(jugadores(partida), fn jugador ->
        puntos = puntos_de(partida, Map.get(ronda.respuestas, jugador))
        acumulado = Map.get(partida.puntajes, jugador, 0) + puntos
        %{jugador: jugador, puntos_ronda: puntos, acumulado: acumulado}
      end)

    puntajes = Map.new(resultados, fn resultado -> {resultado.jugador, resultado.acumulado} end)

    datos = %{
      numero: ronda.numero,
      respuesta_correcta: ronda.pregunta.respuesta,
      resultados: resultados
    }

    {:ok, %{partida | ronda: nil, puntajes: puntajes}, datos}
  end

  # Lo que necesita un bot de la ronda abierta. Estos datos nunca van a los clientes.
  def datos_para_bot(%__MODULE__{ronda: nil}), do: {:error, :sin_ronda_abierta}

  def datos_para_bot(%__MODULE__{ronda: ronda}) do
    {:ok,
     %{numero: ronda.numero, nivel: ronda.pregunta.nivel, respuesta: ronda.pregunta.respuesta}}
  end

  # Ranking de mayor a menor: [{posicion, jugador, puntaje}]. El empate comparte posición.
  def ranking(partida) do
    puntajes = puntajes_en_orden(partida)

    puntajes
    |> Enum.sort_by(fn {_jugador, puntaje} -> puntaje end, :desc)
    |> Enum.map(fn {jugador, puntaje} -> {posicion(puntajes, puntaje), jugador, puntaje} end)
  end

  # Quienes tienen el puntaje más alto; el empate comparte la victoria
  def ganadores(partida) do
    puntajes = puntajes_en_orden(partida)
    {_jugador, maximo} = Enum.max_by(puntajes, fn {_jugador, puntaje} -> puntaje end)

    puntajes
    |> Enum.filter(fn {_jugador, puntaje} -> puntaje == maximo end)
    |> Enum.map(fn {jugador, _puntaje} -> jugador end)
  end

  # Línea del historial sin fecha (la fecha la pone Persistencia):
  # P-1001|historia|basico|pedro,bot_1|pedro:45,bot_1:45,bot_2:-5
  def linea_historial(partida) do
    puntajes =
      partida
      |> puntajes_en_orden()
      |> Enum.map_join(",", fn {jugador, puntaje} -> "#{jugador}:#{puntaje}" end)

    ganadores = partida |> ganadores() |> Enum.join(",")

    Enum.join([partida.id, partida.tema, partida.nivel, ganadores, puntajes], "|")
  end

  # Contenido de la notificación de fin de partida
  def datos_fin(partida) do
    %{
      id: partida.id,
      tema: partida.tema,
      nivel: partida.nivel,
      ranking: ranking(partida),
      ganadores: ganadores(partida)
    }
  end

  # [{jugador, puntaje}] en orden de entrada (creador, bot_1, bot_2...)
  defp puntajes_en_orden(partida) do
    Enum.map(jugadores(partida), fn jugador ->
      {jugador, Map.get(partida.puntajes, jugador, 0)}
    end)
  end

  # Posición = 1 + cuántos tienen más puntos (45, 45, -5 → 1, 1, 3)
  defp posicion(puntajes, puntaje) do
    1 + Enum.count(puntajes, fn {_jugador, otro} -> otro > puntaje end)
  end

  # Milisegundos que faltaban para cerrar la ronda, nunca menos de 0
  defp ms_restantes(partida, ahora_ms) do
    max(partida.tiempo * 1000 - (ahora_ms - partida.ronda.inicio), 0)
  end

  # El nivel que cuenta es el de la pregunta, no el del jugador
  defp puntos_de(partida, nil) do
    Puntaje.calcular(partida.ronda.pregunta.nivel, :sin_responder, 0, partida.tiempo)
  end

  defp puntos_de(partida, {letra, ms_restantes}) do
    pregunta = partida.ronda.pregunta
    resultado = if letra == pregunta.respuesta, do: :correcta, else: :incorrecta
    Puntaje.calcular(pregunta.nivel, resultado, ms_restantes, partida.tiempo)
  end

  # Un jugador abandona. Solo el creador puede hacerlo (los bots no son usuarios).
  # Esperando: la partida se cancela. En curso: queda abandonada y se registra.
  def abandonar(%__MODULE__{estado: :esperando, creador: creador}, creador) do
    {:ok, :cancelada}
  end

  def abandonar(%__MODULE__{estado: :en_curso, creador: creador}, creador) do
    {:ok, :abandonada}
  end

  def abandonar(_partida, _otro_usuario), do: {:error, :sin_partida}

  # ---------- Funciones cliente: solo envían mensajes ----------

  def start_link(argumentos), do: GenServer.start_link(__MODULE__, argumentos)

  # Nivel y respuesta de la ronda abierta. Solo lo usan los bots.
  def datos_pregunta(pid), do: GenServer.call(pid, :datos_pregunta)

  # ---------- Callbacks del GenServer ----------

  def init(argumentos) do
    case nueva(argumentos) do
      {:ok, partida} ->
        # Al arrancar (y al reiniciarse) la partida se reporta al gestor
        avisar_gestor({:partida_iniciada, partida.id, self()})
        {:ok, partida}

      {:error, motivo} ->
        {:stop, motivo}
    end
  end

  def handle_call({:add_bot, dificultad}, _desde, partida) do
    case agregar_bot(partida, dificultad) do
      {:ok, nueva_partida, nombre} -> {:reply, {:ok, nombre}, nueva_partida}
      {:error, motivo} -> {:reply, {:error, motivo}, partida}
    end
  end

  def handle_call({:abandonar, usuario}, _desde, partida) do
    case abandonar(partida, usuario) do
      {:ok, :cancelada} ->
        # Cancelada: no se registra nada y termina con :normal (no se reinicia)
        avisar_gestor({:partida_terminada, partida.id})
        {:stop, :normal, {:ok, :cancelada}, partida}

      {:ok, :abandonada} ->
        # En curso: termina ya con los puntajes de las rondas cerradas (la abierta no cuenta).
        # terminar/1 guarda el historial, avisa a todos y al gestor.
        partida = terminar(partida)
        {:stop, :normal, {:ok, :abandonada}, partida}

      {:error, motivo} ->
        {:reply, {:error, motivo}, partida}
    end
  end

  def handle_call({:start_game, usuario}, _desde, partida) do
    with :ok <- validar_inicio(partida, usuario),
         {:ok, preguntas} <-
           BancoPreguntas.sortear(partida.preguntas_tema, partida.nivel, partida.total_preguntas),
         {:ok, partida} <- iniciar(partida, preguntas) do
      partida = arrancar_bots(partida)
      # La ronda 1 se abre después de responder: el mensaje queda en la cola de la partida
      send(self(), {:abrir_ronda, 1})
      {:reply, {:ok, %{id: partida.id, total: partida.total_preguntas}}, partida}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, partida}
    end
  end

  # Mismo mensaje para humanos y bots. La hora se toma cuando la respuesta llega aquí.
  def handle_call({:responder, jugador, letra}, _desde, partida) do
    case responder(partida, jugador, letra, ahora()) do
      {:ok, partida} ->
        if todos_respondieron?(partida) do
          despues_de_cerrar(cerrar(partida), {:ok, :recibida})
        else
          {:reply, {:ok, :recibida}, partida}
        end

      {:error, motivo} ->
        {:reply, {:error, motivo}, partida}
    end
  end

  def handle_call(:datos_pregunta, _desde, partida) do
    {:reply, datos_para_bot(partida), partida}
  end

  def handle_call(_otro, _desde, partida), do: {:reply, {:error, :comando_invalido}, partida}

  # Abre la ronda que toca; un aviso repetido o viejo no coincide con el pin y se descarta
  def handle_info({:abrir_ronda, numero}, partida) do
    siguiente = partida.numero_ronda + 1

    case numero do
      ^siguiente -> {:noreply, abrir(partida)}
      _viejo -> {:noreply, partida}
    end
  end

  # Venció el tiempo. Si esa ronda ya cerró (todos respondieron antes), no coincide y se descarta.
  def handle_info({:fin_tiempo, numero}, partida) do
    case partida.ronda do
      %{numero: ^numero} -> despues_de_cerrar(cerrar(partida))
      _otra -> {:noreply, partida}
    end
  end

  # Mensajes sueltos: se descartan para no acumularlos
  def handle_info(_mensaje, partida), do: {:noreply, partida}

  # ---------- Efectos de la partida: mensajes y temporizadores ----------

  defp ahora, do: System.monotonic_time(:millisecond)

  # Un proceso por bot, enlazado a la partida (Bot.iniciar usa spawn_link)
  defp arrancar_bots(partida) do
    bots =
      Enum.map(partida.bots, fn bot ->
        %{bot | pid: Bot.iniciar(bot.nombre, bot.dificultad, self())}
      end)

    %{partida | bots: bots}
  end

  # Envía la pregunta a todos a la vez y programa el fin del tiempo
  defp abrir(partida) do
    case abrir_ronda(partida, ahora()) do
      {:ok, partida, datos} ->
        notificar(partida, {:pregunta, datos})
        Process.send_after(self(), {:fin_tiempo, datos.numero}, partida.tiempo * 1000)
        partida

      {:error, :sin_preguntas} ->
        partida
    end
  end

  # Cierra la ronda y anuncia el resultado. Si quedan preguntas programa la siguiente
  # tras la pausa (sin sleep); si era la última, la partida termina.
  defp cerrar(partida) do
    {:ok, partida, datos} = cerrar_ronda(partida)
    notificar(partida, {:cierre_ronda, datos})

    if ultima_ronda?(partida) do
      {:fin, terminar(partida)}
    else
      Process.send_after(self(), {:abrir_ronda, partida.numero_ronda + 1}, partida.pausa_ms)
      {:seguir, partida}
    end
  end

  # Traduce el resultado de cerrar/1 a la respuesta del GenServer (con o sin `reply`)
  defp despues_de_cerrar({:seguir, partida}), do: {:noreply, partida}
  defp despues_de_cerrar({:fin, partida}), do: {:stop, :normal, partida}

  defp despues_de_cerrar({:seguir, partida}, respuesta), do: {:reply, respuesta, partida}
  defp despues_de_cerrar({:fin, partida}, respuesta), do: {:stop, :normal, respuesta, partida}

  # Fin de la partida: historial, ranking a todos y aviso al gestor (solo send, nunca call)
  defp terminar(partida) do
    partida = %{partida | estado: :finalizada}
    guardar_historial(partida)
    notificar(partida, {:fin_partida, datos_fin(partida)})
    avisar_gestor({:partida_terminada, partida.id})
    partida
  end

  # Si falla el historial se informa y la partida termina igual
  defp guardar_historial(partida) do
    case Persistencia.guardar_resultado(linea_historial(partida)) do
      :ok ->
        :ok

      {:error, motivo} ->
        Util.imprimir(
          "No se pudo guardar el resultado de #{partida.id}: #{inspect(motivo)}",
          :error
        )
    end
  end

  # La misma notificación para el Receptor del creador y para cada bot
  defp notificar(partida, mensaje) do
    send(partida.receptor, mensaje)

    Enum.each(partida.bots, fn bot ->
      if is_pid(bot.pid), do: send(bot.pid, mensaje)
    end)
  end

  # Sin gestor en marcha no hay a quién avisar (send a un nombre sin registrar falla)
  defp avisar_gestor(mensaje) do
    case Process.whereis(@gestor) do
      nil -> :ok
      pid -> send(pid, mensaje)
    end
  end
end
