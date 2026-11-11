defmodule Trivia.PartidaTest do
  # No es async: la prueba se registra como :gestor_partidas, un nombre global
  use ExUnit.Case, async: false

  alias Trivia.AyudaPruebas
  alias Trivia.Partida

  defp argumentos(cambios \\ %{}) do
    Map.merge(
      %{
        id: "P-1001",
        creador: "pedro",
        tema: "historia",
        nivel: :basico,
        total_preguntas: 5,
        tiempo: 15,
        preguntas_tema: AyudaPruebas.banco_de_prueba(),
        receptor: self()
      },
      cambios
    )
  end

  defp partida_nueva(cambios \\ %{}) do
    {:ok, partida} = Partida.nueva(argumentos(cambios))
    partida
  end

  # Agrega n bots seguidos y devuelve la partida resultante
  defp con_bots(partida, 0), do: partida

  defp con_bots(partida, n) do
    {:ok, partida, _nombre} = Partida.agregar_bot(partida, :facil)
    con_bots(partida, n - 1)
  end

  describe "nueva/1" do
    test "nace en espera, con solo el creador y sin bots" do
      partida = partida_nueva()

      assert partida.estado == :esperando
      assert partida.bots == []
      assert Partida.cantidad_jugadores(partida) == 1
    end

    test "guarda los datos de la partida" do
      receptor = spawn(fn -> :ok end)
      partida = partida_nueva(%{receptor: receptor, nivel: :intermedio, tiempo: 20})

      assert partida.id == "P-1001"
      assert partida.creador == "pedro"
      assert partida.tema == "historia"
      assert partida.nivel == :intermedio
      assert partida.total_preguntas == 5
      assert partida.tiempo == 20
      assert length(partida.preguntas_tema) == 49
      assert partida.receptor == receptor
    end

    test "rechaza datos inválidos" do
      malos = [
        %{nivel: :experto},
        %{total_preguntas: 0},
        %{tiempo: 0},
        %{tiempo: "15"},
        %{receptor: :no_es_un_pid},
        %{id: 1001},
        %{preguntas_tema: nil}
      ]

      for cambios <- malos do
        assert {:error, :parametros_invalidos} = Partida.nueva(argumentos(cambios)),
               "debió rechazar: #{inspect(cambios)}"
      end

      assert {:error, :parametros_invalidos} = Partida.nueva(%{})
    end
  end

  describe "agregar_bot/2" do
    test "los bots se llaman bot_1, bot_2... y guardan su dificultad" do
      partida = partida_nueva()

      assert {:ok, partida, "bot_1"} = Partida.agregar_bot(partida, :facil)
      assert {:ok, partida, "bot_2"} = Partida.agregar_bot(partida, :dificil)

      assert Partida.cantidad_jugadores(partida) == 3
      # El proceso del bot arranca en start_game: hasta entonces no hay pid
      assert %{nombre: "bot_1", dificultad: :facil, pid: nil} in partida.bots
      assert %{nombre: "bot_2", dificultad: :dificil, pid: nil} in partida.bots
      assert Partida.jugadores(partida) == ["pedro", "bot_1", "bot_2"]
    end

    test "el creador y tres bots son los cuatro jugadores; el cuarto bot no cabe" do
      partida = con_bots(partida_nueva(), 3)

      assert Partida.cantidad_jugadores(partida) == 4
      assert {:error, :partida_llena} = Partida.agregar_bot(partida, :facil)
    end

    test "con la partida iniciada se rechaza, aunque también esté llena" do
      partida = %{partida_nueva() | estado: :en_curso}
      assert {:error, :partida_iniciada} = Partida.agregar_bot(partida, :facil)

      llena = %{con_bots(partida_nueva(), 3) | estado: :en_curso}
      assert {:error, :partida_iniciada} = Partida.agregar_bot(llena, :facil)
    end

    test "una dificultad desconocida se rechaza" do
      assert {:error, :parametros_invalidos} = Partida.agregar_bot(partida_nueva(), :medio)
      assert {:error, :parametros_invalidos} = Partida.agregar_bot(partida_nueva(), "facil")
    end
  end

  describe "abandonar/2" do
    test "si sale el creador estando en espera, la partida se cancela" do
      assert {:ok, :cancelada} = Partida.abandonar(partida_nueva(), "pedro")
    end

    test "alguien que no está en la partida no la cancela" do
      assert {:error, :sin_partida} = Partida.abandonar(partida_nueva(), "carlos")
    end
  end

  # ---------- Rondas (lógica pura; el reloj entra como argumento) ----------

  # Pregunta hecha a mano: se sabe su nivel y su respuesta
  defp pregunta(nivel, respuesta) do
    %{
      tema: "historia",
      nivel: nivel,
      enunciado: "Pregunta #{nivel}",
      opciones: %{"A" => "uno", "B" => "dos", "C" => "tres", "D" => "cuatro"},
      respuesta: respuesta
    }
  end

  # Partida en curso con 2 bots, tiempo 15 s y las preguntas indicadas
  defp en_curso(preguntas, bots \\ 2) do
    # El total nunca es 0: una lista vacía simula que ya se jugaron todas
    total = max(length(preguntas), 1)
    partida = con_bots(partida_nueva(%{total_preguntas: total}), bots)
    {:ok, partida} = Partida.iniciar(partida, preguntas)
    partida
  end

  # Partida con la ronda 1 abierta en el instante 0
  defp con_ronda(preguntas \\ [pregunta(:basico, "B")]) do
    {:ok, partida, _datos} = Partida.abrir_ronda(en_curso(preguntas), 0)
    partida
  end

  defp responde(partida, jugador, letra, ahora_ms) do
    {:ok, partida} = Partida.responder(partida, jugador, letra, ahora_ms)
    partida
  end

  describe "nueva/1 con pausa" do
    test "la pausa es de 3 s si no se indica y se puede cambiar" do
      assert partida_nueva().pausa_ms == 3000
      assert partida_nueva(%{pausa_ms: 20}).pausa_ms == 20
      assert {:error, :parametros_invalidos} = Partida.nueva(argumentos(%{pausa_ms: -1}))
      assert {:error, :parametros_invalidos} = Partida.nueva(argumentos(%{pausa_ms: "3"}))
    end
  end

  describe "validar_inicio/2 e iniciar/2" do
    test "con menos de 2 bots no se puede iniciar" do
      assert {:error, :bots_insuficientes} = Partida.validar_inicio(partida_nueva(), "pedro")

      assert {:error, :bots_insuficientes} =
               Partida.validar_inicio(con_bots(partida_nueva(), 1), "pedro")
    end

    test "con 2 o 3 bots el creador puede iniciar" do
      assert :ok = Partida.validar_inicio(con_bots(partida_nueva(), 2), "pedro")
      assert :ok = Partida.validar_inicio(con_bots(partida_nueva(), 3), "pedro")
    end

    test "una partida ya iniciada no se inicia otra vez" do
      partida = en_curso([pregunta(:basico, "A")])
      assert {:error, :partida_iniciada} = Partida.validar_inicio(partida, "pedro")
      assert {:error, :partida_iniciada} = Partida.iniciar(partida, [])
    end

    test "solo el creador puede iniciar" do
      assert {:error, :sin_partida} =
               Partida.validar_inicio(con_bots(partida_nueva(), 2), "carlos")
    end

    test "iniciar pasa a en curso con todos en 0 y sin ronda abierta" do
      preguntas = [pregunta(:basico, "A"), pregunta(:avanzado, "C")]
      partida = en_curso(preguntas)

      assert partida.estado == :en_curso
      assert partida.preguntas == preguntas
      assert partida.puntajes == %{"pedro" => 0, "bot_1" => 0, "bot_2" => 0}
      assert partida.ronda == nil
    end

    test "con la partida iniciada no entran más bots" do
      partida = en_curso([pregunta(:basico, "A")])
      assert {:error, :partida_iniciada} = Partida.agregar_bot(partida, :facil)
    end
  end

  describe "abrir_ronda/2" do
    test "entrega numero, total, enunciado, opciones y tiempo, sin respuesta ni nivel" do
      partida = en_curso([pregunta(:basico, "B"), pregunta(:intermedio, "C")])

      assert {:ok, partida, datos} = Partida.abrir_ronda(partida, 1000)

      assert datos == %{
               numero: 1,
               total: 2,
               enunciado: "Pregunta basico",
               opciones: %{"A" => "uno", "B" => "dos", "C" => "tres", "D" => "cuatro"},
               tiempo: 15
             }

      assert partida.ronda.numero == 1
      assert partida.ronda.inicio == 1000
      refute Partida.ultima_ronda?(partida)
    end

    test "las rondas se numeran en orden y la última se reconoce" do
      partida = con_ronda([pregunta(:basico, "B"), pregunta(:intermedio, "C")])
      {:ok, partida, _cierre} = Partida.cerrar_ronda(partida)

      assert {:ok, partida, %{numero: 2, enunciado: "Pregunta intermedio"}} =
               Partida.abrir_ronda(partida, 5000)

      assert Partida.ultima_ronda?(partida)
    end

    test "no se abre con otra ronda abierta, sin preguntas ni en espera" do
      assert {:error, :sin_preguntas} = Partida.abrir_ronda(con_ronda(), 10)
      assert {:error, :sin_preguntas} = Partida.abrir_ronda(en_curso([]), 10)
      assert {:error, :sin_preguntas} = Partida.abrir_ronda(partida_nueva(), 10)
    end
  end

  describe "responder/4" do
    test "una respuesta válida guarda la letra y los ms que quedaban al llegar" do
      partida = responde(con_ronda(), "pedro", "B", 4000)

      assert partida.ronda.respuestas == %{"pedro" => {"B", 11_000}}
    end

    test "solo cuenta la primera respuesta de cada jugador" do
      partida = responde(con_ronda(), "pedro", "A", 1000)

      assert {:error, :respuesta_repetida} = Partida.responder(partida, "pedro", "B", 2000)
      assert partida.ronda.respuestas == %{"pedro" => {"A", 14_000}}
    end

    test "una letra inválida se rechaza y no consume la respuesta" do
      partida = con_ronda()

      for letra <- ["E", "a", "AB", "", nil, 1] do
        assert {:error, :letra_invalida} = Partida.responder(partida, "pedro", letra, 1000),
               "debió rechazar: #{inspect(letra)}"
      end

      # Después de equivocarse con la letra todavía puede responder
      assert {:ok, _partida} = Partida.responder(partida, "pedro", "D", 2000)
    end

    test "fuera de ronda se rechaza: en espera, antes de abrir y durante la pausa" do
      assert {:error, :sin_ronda_abierta} = Partida.responder(partida_nueva(), "pedro", "A", 0)

      en_curso = en_curso([pregunta(:basico, "A"), pregunta(:basico, "A")])
      assert {:error, :sin_ronda_abierta} = Partida.responder(en_curso, "pedro", "A", 0)

      {:ok, abierta, _datos} = Partida.abrir_ronda(en_curso, 0)
      {:ok, en_pausa, _cierre} = Partida.cerrar_ronda(abierta)
      assert {:error, :sin_ronda_abierta} = Partida.responder(en_pausa, "pedro", "A", 100)
      # Fuera de ronda manda ese error aunque la letra también sea inválida
      assert {:error, :sin_ronda_abierta} = Partida.responder(en_pausa, "pedro", "Z", 100)
    end

    test "quien no está en la partida no puede responder" do
      assert {:error, :sin_partida} = Partida.responder(con_ronda(), "carlos", "A", 0)
    end

    test "una respuesta que llega con el tiempo vencido queda con 0 ms restantes" do
      partida = responde(con_ronda(), "pedro", "B", 15_300)

      assert partida.ronda.respuestas == %{"pedro" => {"B", 0}}
    end

    test "todos_respondieron? solo cuando respondió cada jugador" do
      partida = con_ronda()
      refute Partida.todos_respondieron?(partida)

      partida = partida |> responde("pedro", "A", 10) |> responde("bot_1", "B", 20)
      refute Partida.todos_respondieron?(partida)

      assert Partida.todos_respondieron?(responde(partida, "bot_2", "C", 30))
      refute Partida.todos_respondieron?(partida_nueva())
    end
  end

  describe "cerrar_ronda/1" do
    test "puntúa correcta con bonificación, incorrecta y sin responder" do
      # Básica con respuesta B y 15 s: pedro acierta en el segundo 1 (+10 +4),
      # bot_1 falla (-5) y bot_2 no responde (0)
      partida = con_ronda() |> responde("pedro", "B", 1000) |> responde("bot_1", "C", 2000)

      assert {:ok, partida, datos} = Partida.cerrar_ronda(partida)

      assert datos == %{
               numero: 1,
               respuesta_correcta: "B",
               resultados: [
                 %{jugador: "pedro", puntos_ronda: 14, acumulado: 14},
                 %{jugador: "bot_1", puntos_ronda: -5, acumulado: -5},
                 %{jugador: "bot_2", puntos_ronda: 0, acumulado: 0}
               ]
             }

      assert partida.ronda == nil
      assert partida.puntajes == %{"pedro" => 14, "bot_1" => -5, "bot_2" => 0}
    end

    test "usa el nivel de la pregunta, no el del jugador, y acumula entre rondas" do
      # La partida es de nivel básico pero la segunda pregunta es avanzada
      partida = con_ronda([pregunta(:basico, "B"), pregunta(:avanzado, "D")])
      {:ok, partida, _cierre} = partida |> responde("pedro", "B", 15_000) |> Partida.cerrar_ronda()

      {:ok, partida, _datos} = Partida.abrir_ronda(partida, 20_000)

      partida =
        partida |> responde("pedro", "D", 35_000) |> responde("bot_1", "A", 21_000)

      assert {:ok, partida, datos} = Partida.cerrar_ronda(partida)

      assert datos.numero == 2
      assert datos.respuesta_correcta == "D"

      assert datos.resultados == [
               %{jugador: "pedro", puntos_ronda: 20, acumulado: 30},
               %{jugador: "bot_1", puntos_ronda: -10, acumulado: -10},
               %{jugador: "bot_2", puntos_ronda: 0, acumulado: 0}
             ]

      assert partida.puntajes["pedro"] == 30
    end

    test "sin ronda abierta no hay nada que cerrar" do
      assert {:error, :sin_ronda_abierta} = Partida.cerrar_ronda(en_curso([]))
    end
  end

  describe "datos_para_bot/1" do
    test "entrega numero, nivel y respuesta de la ronda abierta" do
      assert {:ok, %{numero: 1, nivel: :basico, respuesta: "B"}} =
               Partida.datos_para_bot(con_ronda())
    end

    test "sin ronda abierta no entrega nada" do
      assert {:error, :sin_ronda_abierta} = Partida.datos_para_bot(en_curso([]))
    end
  end

  describe "fin de la partida" do
    defp con_puntajes(puntajes) do
      %{en_curso([]) | puntajes: puntajes}
    end

    test "ranking de mayor a menor con su posición" do
      partida = con_puntajes(%{"pedro" => 30, "bot_1" => 45, "bot_2" => -5})

      assert Partida.ranking(partida) == [{1, "bot_1", 45}, {2, "pedro", 30}, {3, "bot_2", -5}]
      assert Partida.ganadores(partida) == ["bot_1"]
    end

    test "el empate comparte posición y victoria" do
      partida = con_puntajes(%{"pedro" => 45, "bot_1" => 45, "bot_2" => -5})

      assert Partida.ranking(partida) == [{1, "pedro", 45}, {1, "bot_1", 45}, {3, "bot_2", -5}]
      assert Partida.ganadores(partida) == ["pedro", "bot_1"]
    end

    test "línea del historial sin fecha, con todos los jugadores en orden de entrada" do
      partida = con_puntajes(%{"pedro" => 45, "bot_1" => 45, "bot_2" => -5})

      assert Partida.linea_historial(partida) ==
               "P-1001|historia|basico|pedro,bot_1|pedro:45,bot_1:45,bot_2:-5"
    end

    test "línea del historial con un solo ganador que es un bot" do
      partida = con_puntajes(%{"pedro" => 20, "bot_1" => 15, "bot_2" => 38})

      assert Partida.linea_historial(partida) ==
               "P-1001|historia|basico|bot_2|pedro:20,bot_1:15,bot_2:38"
    end

    test "datos_fin reúne id, tema, nivel, ranking y ganadores" do
      partida = con_puntajes(%{"pedro" => 10, "bot_1" => 0, "bot_2" => 0})

      assert Partida.datos_fin(partida) == %{
               id: "P-1001",
               tema: "historia",
               nivel: :basico,
               ranking: [{1, "pedro", 10}, {2, "bot_1", 0}, {2, "bot_2", 0}],
               ganadores: ["pedro"]
             }
    end
  end

  describe "como proceso" do
    setup do
      # La prueba hace de gestor: recibe los avisos que la Partida le manda
      Process.register(self(), :gestor_partidas)
      :ok
    end

    test "al arrancar avisa al gestor con su id y su pid" do
      pid = start_supervised!({Partida, argumentos()})

      assert_receive {:partida_iniciada, "P-1001", ^pid}
    end

    test "arrancar sin gestor en marcha no la tumba" do
      Process.unregister(:gestor_partidas)

      pid = start_supervised!({Partida, argumentos()})

      assert Process.alive?(pid)
    end

    @tag capture_log: true
    test "con datos inválidos no arranca" do
      Process.flag(:trap_exit, true)

      assert {:error, :parametros_invalidos} = Partida.start_link(%{})
    end

    test "add_bot responde el nombre del bot y respeta el límite" do
      pid = start_supervised!({Partida, argumentos()})

      assert {:ok, "bot_1"} = GenServer.call(pid, {:add_bot, :facil})
      assert {:ok, "bot_2"} = GenServer.call(pid, {:add_bot, :dificil})
      assert {:ok, "bot_3"} = GenServer.call(pid, {:add_bot, :facil})
      assert {:error, :partida_llena} = GenServer.call(pid, {:add_bot, :facil})
      assert {:error, :parametros_invalidos} = GenServer.call(pid, {:add_bot, :medio})
      assert Process.alive?(pid)
    end

    test "si el creador abandona, termina con :normal y avisa que terminó" do
      pid = start_supervised!({Partida, argumentos()})
      referencia = Process.monitor(pid)

      assert {:ok, :cancelada} = GenServer.call(pid, {:abandonar, "pedro"})

      assert_receive {:partida_terminada, "P-1001"}
      assert_receive {:DOWN, ^referencia, :process, ^pid, :normal}
    end

    test "si abandona alguien que no está, la partida sigue" do
      pid = start_supervised!({Partida, argumentos()})

      assert {:error, :sin_partida} = GenServer.call(pid, {:abandonar, "carlos"})

      assert Process.alive?(pid)
      refute_received {:partida_terminada, _}
    end

    test "un mensaje desconocido no la tumba" do
      pid = start_supervised!({Partida, argumentos()})

      send(pid, :basura)

      assert {:error, :comando_invalido} = GenServer.call(pid, :cosa_rara)
      assert {:ok, "bot_1"} = GenServer.call(pid, {:add_bot, :facil})
    end
  end

  # ---------- Rondas como proceso ----------

  # Arranca una partida con bots ya agregados (sin iniciarla)
  defp partida_con_bots(cambios, dificultades) do
    pid = start_supervised!({Partida, argumentos(cambios)})
    for dificultad <- dificultades, do: {:ok, _} = GenServer.call(pid, {:add_bot, dificultad})
    pid
  end

  describe "start_game y respuestas como proceso" do
    setup do
      Process.register(self(), :gestor_partidas)
      :ok
    end

    test "start_game con menos de 2 bots se rechaza y la partida sigue en espera" do
      pid = partida_con_bots(%{}, [:facil])

      assert {:error, :bots_insuficientes} = GenServer.call(pid, {:start_game, "pedro"})
      assert %Partida{estado: :esperando} = :sys.get_state(pid)
      refute_received {:pregunta, _}
    end

    test "solo el creador puede iniciarla" do
      pid = partida_con_bots(%{}, [:facil, :facil])

      assert {:error, :sin_partida} = GenServer.call(pid, {:start_game, "carlos"})
    end

    test "si el sorteo falla, responde su error y sigue en espera" do
      pid = partida_con_bots(%{preguntas_tema: []}, [:facil, :facil])

      assert {:error, :preguntas_insuficientes} = GenServer.call(pid, {:start_game, "pedro"})
      assert %Partida{estado: :esperando} = :sys.get_state(pid)
    end

    test "start_game responde id y total, arranca los bots y abre la ronda 1" do
      pid = partida_con_bots(%{total_preguntas: 3}, [:facil, :dificil])

      assert {:ok, %{id: "P-1001", total: 3}} = GenServer.call(pid, {:start_game, "pedro"})

      assert_receive {:pregunta, datos}
      assert %{numero: 1, total: 3, tiempo: 15} = datos
      assert Enum.sort(Map.keys(datos)) == [:enunciado, :numero, :opciones, :tiempo, :total]

      partida = :sys.get_state(pid)
      assert partida.estado == :en_curso

      # Cada bot tiene su proceso vivo, enlazado a la partida, en orden de creación
      assert [%{nombre: "bot_1", dificultad: :facil}, %{nombre: "bot_2", dificultad: :dificil}] =
               Enum.reverse(partida.bots)

      {:links, enlaces} = Process.info(pid, :links)

      for bot <- partida.bots do
        assert Process.alive?(bot.pid)
        assert bot.pid in enlaces
      end

      assert {:error, :partida_iniciada} = GenServer.call(pid, {:start_game, "pedro"})
      assert {:error, :partida_iniciada} = GenServer.call(pid, {:add_bot, :facil})
    end

    test "validación de respuestas: fuera de ronda, letra inválida y solo la primera" do
      pid = partida_con_bots(%{}, [:facil, :facil])

      assert {:error, :sin_ronda_abierta} = GenServer.call(pid, {:responder, "pedro", "A"})

      {:ok, _} = GenServer.call(pid, {:start_game, "pedro"})

      assert {:error, :letra_invalida} = GenServer.call(pid, {:responder, "pedro", "E"})
      assert {:ok, :recibida} = GenServer.call(pid, {:responder, "pedro", "B"})
      assert {:error, :respuesta_repetida} = GenServer.call(pid, {:responder, "pedro", "A"})
      assert {:error, :sin_partida} = GenServer.call(pid, {:responder, "carlos", "A"})

      assert %{"pedro" => {"B", ms_restantes}} = :sys.get_state(pid).ronda.respuestas
      assert ms_restantes in 0..15_000
    end

    test "datos_pregunta entrega nivel y respuesta solo con ronda abierta" do
      pid = partida_con_bots(%{}, [:facil, :facil])

      assert {:error, :sin_ronda_abierta} = Partida.datos_pregunta(pid)

      {:ok, _} = GenServer.call(pid, {:start_game, "pedro"})

      assert {:ok, %{numero: 1, nivel: :basico, respuesta: "A"}} = Partida.datos_pregunta(pid)
    end

    test "un fin_tiempo de otra ronda se descarta" do
      pid = partida_con_bots(%{}, [:facil, :facil])
      {:ok, _} = GenServer.call(pid, {:start_game, "pedro"})

      send(pid, {:fin_tiempo, 0})
      send(pid, {:fin_tiempo, 7})
      send(pid, {:abrir_ronda, 1})

      # La llamada pasa después de esos mensajes: la ronda 1 sigue abierta
      assert {:ok, %{numero: 1}} = Partida.datos_pregunta(pid)
      refute_received {:cierre_ronda, _}
    end
  end

  describe "partida completa contra 2 bots" do
    @describetag :tmp_dir

    setup %{tmp_dir: carpeta} do
      # Historial en una carpeta temporal: nunca se toca data/
      {:ok, _pid} = Trivia.Persistencia.iniciar(carpeta)
      on_exit(fn -> Trivia.Persistencia.detener() end)
      Process.register(self(), :gestor_partidas)
      :ok
    end

    # Juega hasta el fin respondiendo "A" (la correcta en el banco de prueba) a cada pregunta.
    # Devuelve las notificaciones en el orden en que llegaron.
    defp jugar(pid, recibidas \\ []) do
      receive do
        {:pregunta, _datos} = notificacion ->
          {:ok, :recibida} = GenServer.call(pid, {:responder, "pedro", "A"})
          jugar(pid, [notificacion | recibidas])

        {:cierre_ronda, _datos} = notificacion ->
          jugar(pid, [notificacion | recibidas])

        {:fin_partida, _datos} = notificacion ->
          Enum.reverse([notificacion | recibidas])
      after
        3000 -> flunk("la partida no terminó; recibidas: #{inspect(Enum.reverse(recibidas))}")
      end
    end

    test "tres rondas, ranking final, historial y bots detenidos" do
      pid =
        partida_con_bots(%{total_preguntas: 3, tiempo: 1, pausa_ms: 10}, [:dificil, :dificil])

      referencia = Process.monitor(pid)
      assert_receive {:partida_iniciada, "P-1001", ^pid}

      {:ok, %{id: "P-1001", total: 3}} = GenServer.call(pid, {:start_game, "pedro"})
      bots = Enum.map(:sys.get_state(pid).bots, fn bot -> bot.pid end)
      monitores = Enum.map(bots, &Process.monitor/1)

      recibidas = jugar(pid)

      # Pregunta y cierre de cada ronda, en orden, y al final el ranking
      assert [
               {:pregunta, %{numero: 1}},
               {:cierre_ronda, cierre_1},
               {:pregunta, %{numero: 2}},
               {:cierre_ronda, cierre_2},
               {:pregunta, %{numero: 3}},
               {:cierre_ronda, cierre_3},
               {:fin_partida, fin}
             ] = recibidas

      # Ninguna pregunta lleva la respuesta ni el nivel
      for {:pregunta, datos} <- recibidas do
        assert Enum.sort(Map.keys(datos)) == [:enunciado, :numero, :opciones, :tiempo, :total]
      end

      # Pedro acertó las tres básicas: 10 puntos más la bonificación (respondió al instante)
      for cierre <- [cierre_1, cierre_2, cierre_3] do
        assert cierre.respuesta_correcta == "A"
        assert ["pedro", "bot_1", "bot_2"] == Enum.map(cierre.resultados, & &1.jugador)
        assert hd(cierre.resultados).puntos_ronda in 14..15

        # Un bot acierta (10 más bonificación) o falla (-5); nunca queda sin responder
        for %{jugador: "bot_" <> _, puntos_ronda: puntos} <- cierre.resultados do
          assert puntos == -5 or puntos in 10..15
        end
      end

      # El acumulado del último cierre es la suma de las rondas y coincide con el ranking
      finales = Map.new(cierre_3.resultados, fn r -> {r.jugador, r.acumulado} end)

      for jugador <- ["pedro", "bot_1", "bot_2"] do
        suma =
          [cierre_1, cierre_2, cierre_3]
          |> Enum.flat_map(& &1.resultados)
          |> Enum.filter(&(&1.jugador == jugador))
          |> Enum.map(& &1.puntos_ronda)
          |> Enum.sum()

        assert finales[jugador] == suma
      end

      assert %{id: "P-1001", tema: "historia", nivel: :basico} = fin
      assert Map.new(fin.ranking, fn {_pos, jugador, puntaje} -> {jugador, puntaje} end) == finales
      puntajes = Enum.map(fin.ranking, fn {_pos, _jugador, puntaje} -> puntaje end)
      assert puntajes == Enum.sort(puntajes, :desc)
      assert [{1, primero, maximo} | _] = fin.ranking
      assert primero in fin.ganadores
      assert Enum.all?(fin.ganadores, fn ganador -> finales[ganador] == maximo end)

      # Avisa al gestor y termina con :normal (el supervisor no la reinicia)
      assert_receive {:partida_terminada, "P-1001"}
      assert_receive {:DOWN, ^referencia, :process, ^pid, :normal}

      # Los bots dejan su bucle solos
      for {bot, monitor} <- Enum.zip(bots, monitores) do
        assert_receive {:DOWN, ^monitor, :process, ^bot, :normal}, 1000
      end

      # La línea quedó en el historial, con fecha y todos los jugadores
      assert {:ok, [linea]} = Trivia.Persistencia.leer_historial()

      esperado =
        "|P-1001|historia|basico|#{Enum.join(fin.ganadores, ",")}|" <>
          "pedro:#{finales["pedro"]},bot_1:#{finales["bot_1"]},bot_2:#{finales["bot_2"]}"

      assert String.ends_with?(linea, esperado)
      assert linea =~ ~r/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\|/
    end

    test "si el humano no responde, el temporizador cierra la ronda y él queda en 0" do
      pid =
        partida_con_bots(%{total_preguntas: 1, tiempo: 1, pausa_ms: 10}, [:dificil, :dificil])

      referencia = Process.monitor(pid)
      {:ok, _} = GenServer.call(pid, {:start_game, "pedro"})
      inicio = System.monotonic_time(:millisecond)

      assert_receive {:pregunta, %{numero: 1}}
      assert_receive {:cierre_ronda, cierre}, 2000
      assert System.monotonic_time(:millisecond) - inicio >= 900

      assert %{jugador: "pedro", puntos_ronda: 0, acumulado: 0} = hd(cierre.resultados)

      assert_receive {:fin_partida, %{ranking: ranking}}
      assert {_posicion, "pedro", 0} = List.keyfind(ranking, "pedro", 1)
      assert_receive {:DOWN, ^referencia, :process, ^pid, :normal}
      assert {:ok, [_linea]} = Trivia.Persistencia.leer_historial()
    end

    test "durante la pausa entre rondas no se aceptan respuestas" do
      pid =
        partida_con_bots(%{total_preguntas: 2, tiempo: 1, pausa_ms: 5000}, [:dificil, :dificil])

      {:ok, _} = GenServer.call(pid, {:start_game, "pedro"})
      assert_receive {:pregunta, %{numero: 1}}
      {:ok, :recibida} = GenServer.call(pid, {:responder, "pedro", "A"})
      assert_receive {:cierre_ronda, %{numero: 1}}, 1000

      assert {:error, :sin_ronda_abierta} = GenServer.call(pid, {:responder, "pedro", "A"})
      assert {:error, :sin_ronda_abierta} = Partida.datos_pregunta(pid)
      refute_received {:pregunta, %{numero: 2}}
    end

    test "si no se puede guardar el historial, avisa y termina igual" do
      :ok = Trivia.Persistencia.detener()

      errores =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          pid =
            partida_con_bots(%{total_preguntas: 1, tiempo: 1, pausa_ms: 10}, [:dificil, :dificil])

          referencia = Process.monitor(pid)
          {:ok, _} = GenServer.call(pid, {:start_game, "pedro"})

          assert [{:pregunta, _}, {:cierre_ronda, _}, {:fin_partida, _}] = jugar(pid)
          assert_receive {:partida_terminada, "P-1001"}
          assert_receive {:DOWN, ^referencia, :process, ^pid, :normal}
        end)

      assert errores =~ "No se pudo guardar el resultado de P-1001"
    end
  end
end
