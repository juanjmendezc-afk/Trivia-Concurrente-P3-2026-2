defmodule Trivia.Partida do
  # Cada partida es un GenServer. Si termina mal, el supervisor la reinicia (:transient)
  use GenServer, restart: :transient

  @gestor :gestor_partidas
  @max_jugadores 4
  @niveles [:basico, :intermedio, :avanzado]
  @dificultades [:facil, :dificil]

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
    bots: []
  ]

  # ---------- Lógica pura: cada operación devuelve la partida nueva ----------

  # Constructor con validación: la partida nace en espera, con solo el creador
  def nueva(%{
        id: id,
        creador: creador,
        tema: tema,
        nivel: nivel,
        total_preguntas: total_preguntas,
        tiempo: tiempo,
        preguntas_tema: preguntas_tema,
        receptor: receptor
      })
      when is_binary(id) and is_binary(creador) and is_binary(tema) and nivel in @niveles and
             is_integer(total_preguntas) and total_preguntas > 0 and
             is_integer(tiempo) and tiempo > 0 and
             is_list(preguntas_tema) and is_pid(receptor) do
    {:ok,
     %__MODULE__{
       id: id,
       creador: creador,
       tema: tema,
       nivel: nivel,
       total_preguntas: total_preguntas,
       tiempo: tiempo,
       preguntas_tema: preguntas_tema,
       receptor: receptor
     }}
  end

  def nueva(_argumentos), do: {:error, :parametros_invalidos}

  # El creador más los bots
  def cantidad_jugadores(partida), do: 1 + length(partida.bots)

  # Agrega un bot (por ahora solo nombre y dificultad; el proceso Bot llega en T6)
  def agregar_bot(%__MODULE__{estado: estado}, _dificultad) when estado != :esperando do
    {:error, :partida_iniciada}
  end

  def agregar_bot(partida, dificultad) when dificultad in @dificultades do
    if cantidad_jugadores(partida) >= @max_jugadores do
      {:error, :partida_llena}
    else
      nombre = "bot_#{length(partida.bots) + 1}"
      bot = %{nombre: nombre, dificultad: dificultad}
      {:ok, %{partida | bots: [bot | partida.bots]}, nombre}
    end
  end

  def agregar_bot(_partida, _dificultad), do: {:error, :parametros_invalidos}

  # Un jugador abandona. Esperando: si es el creador, la partida se cancela.
  def abandonar(%__MODULE__{estado: :esperando, creador: creador}, creador) do
    {:ok, :cancelada}
  end

  def abandonar(%__MODULE__{estado: :esperando}, _otro_usuario), do: {:error, :sin_partida}

  # Con la partida en curso el abandono se resuelve en T7
  def abandonar(_partida, _usuario), do: {:error, :partida_iniciada}

  # ---------- Funciones cliente: solo envían mensajes ----------

  def start_link(argumentos), do: GenServer.start_link(__MODULE__, argumentos)

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

      {:error, motivo} ->
        {:reply, {:error, motivo}, partida}
    end
  end

  def handle_call(_otro, _desde, partida), do: {:reply, {:error, :comando_invalido}, partida}

  # Mensajes sueltos: se descartan para no acumularlos
  def handle_info(_mensaje, partida), do: {:noreply, partida}

  # Sin gestor en marcha no hay a quién avisar (send a un nombre sin registrar falla)
  defp avisar_gestor(mensaje) do
    case Process.whereis(@gestor) do
      nil -> :ok
      pid -> send(pid, mensaje)
    end
  end
end
