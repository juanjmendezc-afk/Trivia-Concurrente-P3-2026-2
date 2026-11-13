defmodule Trivia.Cliente do
  alias Trivia.Receptor
  alias Trivia.Util

  @servidor :servidor
  @espera 5000

  # Comandos del enunciado; si llegan con parámetros mal escritos se avisa de eso
  @comandos ~w(connect disconnect create_game add_bot start_game answer leave_game score ranking)

  # ---------- Arranque ----------

  # Arranque desde la consola del cliente: iex --sname pedro -S mix
  # El servidor se busca en el mismo equipo, con el nombre "servidor"
  def iniciar do
    iniciar(nodo_servidor(node()))
  end

  # Arranque indicando el nodo del servidor (por ejemplo :"servidor@mipc")
  def iniciar(nodo) do
    case conectar(nodo) do
      :ok ->
        receptor = Receptor.iniciar()
        mostrar_comandos()
        bucle(%{nodo: nodo, receptor: receptor, usuario: nil})
        Receptor.detener(receptor)
        :ok

      {:error, motivo} ->
        Util.imprimir(mensaje_de_error(motivo), :error)
        {:error, motivo}
    end
  end

  # Nodo del servidor a partir del nombre del nodo propio: pedro@mipc -> servidor@mipc
  def nodo_servidor(nodo_propio) do
    [_nombre, equipo] = nodo_propio |> Atom.to_string() |> String.split("@", parts: 2)
    String.to_atom("servidor@" <> equipo)
  end

  defp conectar(nodo) do
    if node() == :nonode@nohost do
      {:error, :nodo_sin_nombre}
    else
      case Node.connect(nodo) do
        true -> :ok
        _ -> {:error, :servidor_no_disponible}
      end
    end
  end

  defp mostrar_comandos do
    Util.imprimir("Comandos:")
    Util.imprimir("  connect <usuario> <clave>        disconnect")
    Util.imprimir("  create_game tema=<t> preguntas=<n> tiempo=<s>")
    Util.imprimir("  add_bot <facil|dificil>          start_game")
    Util.imprimir("  answer <letra>                   leave_game")
    Util.imprimir("  score                            ranking [tema]")
    Util.imprimir("  salir (cierra este cliente)")
  end

  # ---------- Bucle de comandos ----------

  # `estado` guarda el nodo del servidor, el pid del Receptor y el usuario con sesión
  defp bucle(estado) do
    linea = Util.leer(prompt(estado), :string)

    case procesar(linea, estado) do
      {:continuar, nuevo_estado} -> bucle(nuevo_estado)
      :salir -> :ok
    end
  end

  defp prompt(%{usuario: nil}), do: "trivia> "
  defp prompt(%{usuario: usuario}), do: usuario <> "> "

  # Ejecuta una línea escrita por el jugador y devuelve el estado nuevo, o :salir
  def procesar(linea, estado) do
    case String.split(linea) do
      [] -> {:continuar, estado}
      ["salir"] -> salir(estado)
      _ -> {:continuar, ejecutar(linea, estado)}
    end
  end

  # Cierra la sesión (si hay una) para no dejarla abierta en el servidor
  defp salir(%{usuario: nil}), do: :salir

  defp salir(estado) do
    mensaje = {:disconnect, self()}
    mostrar(mensaje, pedir(estado.nodo, mensaje), estado)
    :salir
  end

  defp ejecutar(linea, estado) do
    case interpretar(linea, self(), estado.receptor) do
      {:ok, mensaje} ->
        mostrar(mensaje, pedir(estado.nodo, mensaje), estado)

      {:error, motivo} ->
        Util.imprimir(mensaje_de_error(motivo), :error)
        estado
    end
  end

  # ---------- Comunicación con el servidor ----------

  # Envía la petición al servidor y espera su respuesta; sin respuesta, servidor no disponible
  def pedir(nodo, mensaje, espera \\ @espera) do
    descartar_respuestas_viejas()
    send({@servidor, nodo}, mensaje)

    receive do
      {:respuesta, respuesta} -> respuesta
    after
      espera -> {:error, :servidor_no_disponible}
    end
  end

  # Una respuesta que llegó tarde (tras un timeout) no debe confundirse con la siguiente
  defp descartar_respuestas_viejas do
    receive do
      {:respuesta, _vieja} -> descartar_respuestas_viejas()
    after
      0 -> :ok
    end
  end

  # ---------- Mostrar resultados ----------

  # Muestra la respuesta del servidor y devuelve el estado actualizado
  defp mostrar(_mensaje, {:error, :sin_sesion}, estado) do
    Util.imprimir(mensaje_de_error(:sin_sesion), :error)
    %{estado | usuario: nil}
  end

  defp mostrar(_mensaje, {:error, motivo}, estado) do
    Util.imprimir(mensaje_de_error(motivo), :error)
    estado
  end

  defp mostrar({:connect, _, _, _}, {:ok, %{usuario: usuario, registrado: true}}, estado) do
    Util.imprimir("Usuario nuevo registrado. Bienvenido, #{usuario}")
    %{estado | usuario: usuario}
  end

  defp mostrar({:connect, _, _, _}, {:ok, %{usuario: usuario, registrado: false}}, estado) do
    Util.imprimir("Bienvenido de nuevo, #{usuario}")
    %{estado | usuario: usuario}
  end

  defp mostrar({:disconnect, _}, {:ok, %{usuario: usuario}}, estado) do
    Util.imprimir("Sesión cerrada. Hasta pronto, #{usuario}")
    %{estado | usuario: nil}
  end

  defp mostrar(
         {:create_game, _, tema, preguntas, tiempo, _},
         {:ok, %{id: id, nivel: nivel}},
         estado
       ) do
    Util.imprimir(
      "Partida #{id} creada: tema #{tema}, #{preguntas} preguntas, #{tiempo} s por pregunta"
    )

    Util.imprimir("Tu nivel en #{tema}: #{nombre_nivel(nivel)}")
    Util.imprimir("Agrega al menos 2 bots con add_bot <facil|dificil> y luego usa start_game")
    estado
  end

  defp mostrar({:add_bot, _, dificultad}, {:ok, nombre}, estado) when is_binary(nombre) do
    Util.imprimir("Bot agregado: #{nombre} (#{dificultad})")
    estado
  end

  defp mostrar({:leave_game, _}, {:ok, %{id: id, resultado: :cancelada}}, estado) do
    Util.imprimir("Saliste de la partida #{id}: quedó cancelada y no se registra en el historial")
    estado
  end

  defp mostrar({:start_game, _}, {:ok, %{id: id, total: total}}, estado) do
    Util.imprimir("Partida #{id} iniciada: #{total} preguntas. Responde con answer <letra>")
    estado
  end

  defp mostrar({:answer, _, letra}, {:ok, :recibida}, estado) do
    Util.imprimir("Respuesta #{letra} recibida")
    estado
  end

  defp mostrar({:leave_game, _}, {:ok, %{id: id, resultado: :abandonada}}, estado) do
    Util.imprimir(
      "Abandonaste la partida #{id}: terminó y quedó registrada con los puntajes actuales"
    )

    estado
  end

  defp mostrar({:score, _}, {:ok, datos}, estado) do
    Util.imprimir(formatear_score(datos))
    estado
  end

  defp mostrar({:ranking, _, tema}, {:ok, lista}, estado) when is_list(lista) do
    Util.imprimir(formatear_ranking(tema, lista))
    estado
  end

  # Respuesta correcta sin formato propio: se muestra tal cual
  defp mostrar(_mensaje, {:ok, datos}, estado) do
    Util.imprimir(inspect(datos))
    estado
  end

  # ---------- Lógica pura: de texto a mensaje ----------

  # Convierte la línea escrita en el mensaje de la sección 4 de la arquitectura
  def interpretar(linea, pid_cliente, pid_receptor) do
    linea
    |> String.split()
    |> comando(pid_cliente, pid_receptor)
  end

  defp comando(["connect", usuario, clave], pid, _receptor) do
    {:ok, {:connect, pid, usuario, clave}}
  end

  defp comando(["disconnect"], pid, _receptor), do: {:ok, {:disconnect, pid}}

  defp comando(["create_game" | argumentos], pid, receptor) do
    with {:ok, tema, preguntas, tiempo} <- leer_partida(argumentos) do
      {:ok, {:create_game, pid, tema, preguntas, tiempo, receptor}}
    end
  end

  defp comando(["add_bot", "facil"], pid, _receptor), do: {:ok, {:add_bot, pid, :facil}}
  defp comando(["add_bot", "dificil"], pid, _receptor), do: {:ok, {:add_bot, pid, :dificil}}
  defp comando(["start_game"], pid, _receptor), do: {:ok, {:start_game, pid}}

  # La letra se pasa a mayúscula; el servidor decide si es A, B, C o D
  defp comando(["answer", letra], pid, _receptor) do
    {:ok, {:answer, pid, String.upcase(letra)}}
  end

  defp comando(["leave_game"], pid, _receptor), do: {:ok, {:leave_game, pid}}
  defp comando(["score"], pid, _receptor), do: {:ok, {:score, pid}}
  defp comando(["ranking"], pid, _receptor), do: {:ok, {:ranking, pid, nil}}
  defp comando(["ranking", tema], pid, _receptor), do: {:ok, {:ranking, pid, tema}}

  # Comando conocido con parámetros mal escritos
  defp comando([nombre | _], _pid, _receptor) when nombre in @comandos do
    {:error, :parametros_invalidos}
  end

  defp comando(_otro, _pid, _receptor), do: {:error, :comando_invalido}

  # Lee tema=<t> preguntas=<n> tiempo=<s> en cualquier orden.
  # Solo revisa la forma (los rangos los valida el servidor).
  defp leer_partida([_, _, _] = argumentos) do
    with {:ok, %{"tema" => tema, "preguntas" => preguntas, "tiempo" => tiempo}} <-
           separar_parametros(argumentos),
         {:ok, preguntas} <- a_entero(preguntas),
         {:ok, tiempo} <- a_entero(tiempo) do
      {:ok, tema, preguntas, tiempo}
    else
      _ -> {:error, :parametros_invalidos}
    end
  end

  defp leer_partida(_argumentos), do: {:error, :parametros_invalidos}

  # ["tema=historia", "tiempo=15"] -> {:ok, %{"tema" => "historia", "tiempo" => "15"}}
  defp separar_parametros(argumentos) do
    pares = Enum.map(argumentos, &String.split(&1, "=", parts: 2))

    if Enum.all?(pares, &match?([_, _], &1)) do
      {:ok, Map.new(pares, fn [clave, valor] -> {clave, valor} end)}
    else
      {:error, :parametros_invalidos}
    end
  end

  defp a_entero(texto) do
    case Integer.parse(texto) do
      {numero, ""} -> {:ok, numero}
      _ -> {:error, :parametros_invalidos}
    end
  end

  # Nombre del nivel para mostrarlo al jugador
  defp nombre_nivel(:basico), do: "básico"
  defp nombre_nivel(:intermedio), do: "intermedio"
  defp nombre_nivel(:avanzado), do: "avanzado"

  # ---------- Lógica pura: texto de score y ranking ----------

  # Puntaje total, partidas y una línea por tema (en orden alfabético)
  def formatear_score(%{puntaje: puntaje, partidas: partidas, por_tema: por_tema}) do
    if partidas == 0 do
      "Puntaje total: 0 en 0 partidas\nAún no has jugado"
    else
      temas =
        por_tema
        |> Enum.sort()
        |> Enum.map(fn {tema, %{puntaje: puntos, nivel: nivel}} ->
          "  #{tema}: #{puntos} (#{nombre_nivel(nivel)})"
        end)

      Enum.join(["Puntaje total: #{puntaje} en #{partidas} partidas" | temas], "\n")
    end
  end

  # Título y una línea por jugador: "posición. usuario — puntaje"
  def formatear_ranking(tema, []), do: titulo_ranking(tema) <> "\nAún no hay partidas registradas"

  def formatear_ranking(tema, lista) do
    lineas =
      lista
      |> Enum.with_index(1)
      |> Enum.map(fn {{usuario, puntaje}, posicion} ->
        "  #{posicion}. #{usuario} — #{puntaje}"
      end)

    Enum.join([titulo_ranking(tema) | lineas], "\n")
  end

  defp titulo_ranking(nil), do: "Ranking global"
  defp titulo_ranking(tema), do: "Ranking de #{String.downcase(tema)}"

  # ---------- Lógica pura: mensajes de error (sección 6) ----------

  def mensaje_de_error(:sin_sesion), do: "Primero inicia sesión: connect <usuario> <clave>"
  def mensaje_de_error(:clave_incorrecta), do: "Clave incorrecta"
  def mensaje_de_error(:ya_conectado), do: "Ese usuario ya tiene sesión abierta en otro cliente"

  def mensaje_de_error(:usuario_reservado),
    do: "Los usuarios que empiezan por bot_ están reservados"

  def mensaje_de_error(:servidor_no_disponible), do: "No se pudo conectar con el servidor"
  def mensaje_de_error(:ya_en_partida), do: "Ya estás en una partida"
  def mensaje_de_error(:tema_inexistente), do: "Ese tema no existe"

  def mensaje_de_error(:preguntas_insuficientes),
    do: "No hay preguntas suficientes para esa partida"

  def mensaje_de_error(:sin_partida), do: "No estás en ninguna partida"
  def mensaje_de_error(:partida_llena), do: "La partida está llena"
  def mensaje_de_error(:partida_iniciada), do: "La partida ya empezó"
  def mensaje_de_error(:bots_insuficientes), do: "Se necesitan al menos 2 bots para iniciar"
  def mensaje_de_error(:letra_invalida), do: "Responde A, B, C o D"
  def mensaje_de_error(:sin_ronda_abierta), do: "No hay una pregunta abierta"

  def mensaje_de_error(:respuesta_repetida) do
    "Ya respondiste esta pregunta (solo cuenta la primera)"
  end

  def mensaje_de_error(:sesion_abierta) do
    "Ya tienes una sesión abierta; usa disconnect antes de conectar otro usuario"
  end

  def mensaje_de_error(:comando_invalido), do: "Comando no reconocido"

  # score y ranking: el servidor no pudo leer el historial
  def mensaje_de_error(:persistencia_no_disponible) do
    "No se pudo leer el historial; intenta más tarde"
  end

  def mensaje_de_error(:parametros_invalidos) do
    "Revisa los parámetros del comando (por ejemplo, usuario sin espacios, barras verticales, " <>
      "comas ni dos puntos; preguntas de 1 a 10 o tiempo mayor a 0)"
  end

  # Solo del cliente: sin nombre de nodo no se puede hablar con el servidor
  def mensaje_de_error(:nodo_sin_nombre) do
    "Este nodo no tiene nombre. Arranca con: iex --sname <nombre> -S mix"
  end

  def mensaje_de_error(motivo), do: "Error: #{inspect(motivo)}"
end
