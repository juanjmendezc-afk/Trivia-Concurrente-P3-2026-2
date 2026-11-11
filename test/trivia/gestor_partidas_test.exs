defmodule Trivia.GestorPartidasTest do
  # No es async: los procesos del gestor tienen nombres globales
  use ExUnit.Case, async: false

  alias Trivia.AyudaPruebas
  alias Trivia.GestorPartidas
  alias Trivia.Persistencia
  alias Trivia.SupervisorPartidas

  # Un receptor cualquiera (la lógica pura solo pide que sea un pid)
  defp receptor, do: self()

  defp estado_con_banco, do: GestorPartidas.nuevo(AyudaPruebas.banco_de_prueba())

  describe "lógica pura: validar_pedido/6" do
    test "con todo en orden devuelve las preguntas del tema" do
      assert {:ok, preguntas} =
               GestorPartidas.validar_pedido(
                 estado_con_banco(),
                 "pedro",
                 "historia",
                 5,
                 15,
                 receptor()
               )

      assert length(preguntas) == 24
      assert Enum.all?(preguntas, &(&1.tema == "historia"))
    end

    test "un tema que no está en el banco no existe" do
      assert {:error, :tema_inexistente} =
               GestorPartidas.validar_pedido(
                 estado_con_banco(),
                 "pedro",
                 "cocina",
                 5,
                 15,
                 receptor()
               )

      assert {:error, :tema_inexistente} =
               GestorPartidas.validar_pedido(
                 GestorPartidas.nuevo([]),
                 "pedro",
                 "historia",
                 5,
                 15,
                 receptor()
               )
    end

    test "preguntas fuera de 1 a 10, tiempo no positivo o datos de otro tipo" do
      estado = estado_con_banco()

      malos = [
        {"historia", 0, 15},
        {"historia", 11, 15},
        {"historia", 5, 0},
        {"historia", 5, -3},
        {"historia", 5.0, 15},
        {"historia", "5", 15},
        {"historia", 5, "15"},
        {:historia, 5, 15}
      ]

      for {tema, preguntas, tiempo} <- malos do
        assert {:error, :parametros_invalidos} =
                 GestorPartidas.validar_pedido(
                   estado,
                   "pedro",
                   tema,
                   preguntas,
                   tiempo,
                   receptor()
                 ),
               "debió rechazar: #{inspect({tema, preguntas, tiempo})}"
      end

      assert {:error, :parametros_invalidos} =
               GestorPartidas.validar_pedido(estado, "pedro", "historia", 5, 15, :no_es_pid)
    end

    test "los límites 1 y 10 preguntas sí se aceptan" do
      estado = estado_con_banco()

      assert {:ok, _} =
               GestorPartidas.validar_pedido(estado, "pedro", "historia", 1, 1, receptor())

      assert {:ok, _} =
               GestorPartidas.validar_pedido(estado, "pedro", "historia", 10, 1, receptor())
    end

    test "el orden de los errores: ya en partida, parámetros, tema" do
      estado = GestorPartidas.registrar_partida(estado_con_banco(), "P-1001", self(), "pedro", self())

      # Ya en partida gana a todo lo demás
      assert {:error, :ya_en_partida} =
               GestorPartidas.validar_pedido(estado, "pedro", "cocina", 0, 0, receptor())

      # Los parámetros se revisan antes que el tema
      assert {:error, :parametros_invalidos} =
               GestorPartidas.validar_pedido(estado, "carlos", "cocina", 0, 15, receptor())
    end
  end

  describe "lógica pura: verificar_preguntas/3" do
    test "alcanzan las preguntas de cada nivel" do
      historia = Enum.filter(AyudaPruebas.banco_de_prueba(), &(&1.tema == "historia"))

      assert :ok = GestorPartidas.verificar_preguntas(historia, :basico, 5)
      assert :ok = GestorPartidas.verificar_preguntas(historia, :intermedio, 10)
      assert :ok = GestorPartidas.verificar_preguntas(historia, :avanzado, 10)
    end

    test "un tema con pocas preguntas no alcanza" do
      escaso = Enum.filter(AyudaPruebas.banco_de_prueba(), &(&1.tema == "escaso"))

      assert {:error, :preguntas_insuficientes} =
               GestorPartidas.verificar_preguntas(escaso, :basico, 5)
    end

    test "falta un nivel que el reparto necesita" do
      # Solo básicas: 5 preguntas de nivel básico piden 1 intermedia
      basicas =
        AyudaPruebas.banco_de_prueba()
        |> Enum.filter(&(&1.tema == "historia" and &1.nivel == :basico))

      assert {:error, :preguntas_insuficientes} =
               GestorPartidas.verificar_preguntas(basicas, :basico, 5)

      # Con 1 pregunta el reparto no pide intermedias
      assert :ok = GestorPartidas.verificar_preguntas(basicas, :basico, 1)
    end
  end

  describe "lógica pura: registro de partidas" do
    test "los ids son P-1001, P-1002... y no se repiten" do
      estado = estado_con_banco()
      assert GestorPartidas.id_siguiente(estado) == "P-1001"

      estado = GestorPartidas.registrar_partida(estado, "P-1001", self(), "pedro", self())
      assert GestorPartidas.id_siguiente(estado) == "P-1002"

      estado = GestorPartidas.liberar(estado, "P-1001")
      assert GestorPartidas.id_siguiente(estado) == "P-1002"
    end

    test "registrar_partida anota al creador y su partida" do
      pid = self()
      receptor = spawn(fn -> :ok end)

      estado =
        GestorPartidas.registrar_partida(estado_con_banco(), "P-1001", pid, "pedro", receptor)

      assert estado.jugadores == %{"pedro" => "P-1001"}

      assert estado.partidas == %{
               "P-1001" => %{pid: pid, creador: "pedro", receptor: receptor}
             }

      assert GestorPartidas.receptor_de(estado, "P-1001") == receptor
      assert GestorPartidas.receptor_de(estado, "P-9999") == nil
      assert {:ok, "P-1001", ^pid} = GestorPartidas.partida_de(estado, "pedro")
    end

    test "partida_de sin partida" do
      assert {:error, :sin_partida} = GestorPartidas.partida_de(estado_con_banco(), "pedro")
    end

    test "registrar_pid con otro pid actualiza el pid, deja al creador y avisa del reinicio" do
      viejo = self()
      nuevo = spawn(fn -> :ok end)
      receptor = spawn(fn -> :ok end)

      estado =
        GestorPartidas.registrar_partida(estado_con_banco(), "P-1001", viejo, "pedro", receptor)

      assert {estado, :reinicio} = GestorPartidas.registrar_pid(estado, "P-1001", nuevo)

      assert estado.partidas["P-1001"] == %{pid: nuevo, creador: "pedro", receptor: receptor}
      assert estado.jugadores == %{"pedro" => "P-1001"}
      assert {:ok, "P-1001", ^nuevo} = GestorPartidas.partida_de(estado, "pedro")
      assert GestorPartidas.receptor_de(estado, "P-1001") == receptor
    end

    test "registrar_pid con el mismo pid (primer arranque) no cambia nada" do
      pid = self()
      estado = GestorPartidas.registrar_partida(estado_con_banco(), "P-1001", pid, "pedro", pid)

      assert {^estado, :sin_cambio} = GestorPartidas.registrar_pid(estado, "P-1001", pid)
    end

    test "registrar_pid de un id desconocido lo registra sin creador ni aviso" do
      pid = self()

      assert {estado, :sin_cambio} =
               GestorPartidas.registrar_pid(estado_con_banco(), "P-1009", pid)

      assert estado.partidas == %{"P-1009" => %{pid: pid, creador: nil, receptor: nil}}
      assert estado.jugadores == %{}
    end

    test "liberar suelta a los jugadores de esa partida y no toca las otras" do
      estado =
        estado_con_banco()
        |> GestorPartidas.registrar_partida("P-1001", self(), "pedro", self())
        |> GestorPartidas.registrar_partida("P-1002", self(), "carlos", self())
        |> GestorPartidas.liberar("P-1001")

      assert estado.jugadores == %{"carlos" => "P-1002"}
      assert Map.keys(estado.partidas) == ["P-1002"]
    end

    test "liberar una partida desconocida no cambia nada" do
      estado = GestorPartidas.registrar_partida(estado_con_banco(), "P-1001", self(), "pedro", self())

      assert GestorPartidas.liberar(estado, "P-9999") == estado
    end
  end

  describe "como proceso" do
    @describetag :tmp_dir

    setup %{tmp_dir: carpeta} do
      AyudaPruebas.escribir_preguntas(carpeta)
      {:ok, _pid} = Persistencia.iniciar(carpeta)
      {:ok, _pid} = SupervisorPartidas.iniciar()
      {:ok, _pid} = GestorPartidas.iniciar()

      on_exit(fn ->
        GestorPartidas.detener()
        SupervisorPartidas.detener()
        Persistencia.detener()
      end)

      :ok
    end

    # Espera (consultando por mensajes, sin dormir) a que el gestor conozca un pid vivo
    defp esperar_bot(usuario, dificultad, limite \\ System.monotonic_time(:millisecond) + 2000) do
      case GestorPartidas.agregar_bot(usuario, dificultad) do
        {:error, :sin_partida} ->
          if System.monotonic_time(:millisecond) < limite do
            esperar_bot(usuario, dificultad, limite)
          else
            :tiempo_agotado
          end

        otra_respuesta ->
          otra_respuesta
      end
    end

    test "no se puede iniciar dos veces" do
      assert {:error, :ya_iniciado} = GestorPartidas.iniciar()
    end

    test "crear una partida responde su id y el nivel del creador" do
      assert {:ok, %{id: "P-1001", nivel: :basico}} =
               GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())

      assert {:ok, %{id: "P-1002", nivel: :basico}} =
               GestorPartidas.crear_partida("carlos", "ciencia", 10, 20, receptor())
    end

    test "una partida creada queda supervisada y esperando" do
      {:ok, %{id: "P-1001"}} =
        GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())

      assert [{:undefined, pid, :worker, _}] =
               DynamicSupervisor.which_children(:supervisor_partidas)

      assert %Trivia.Partida{estado: :esperando, creador: "pedro", bots: []} = :sys.get_state(pid)
    end

    test "no se puede crear otra partida estando en una" do
      {:ok, _} = GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())

      assert {:error, :ya_en_partida} =
               GestorPartidas.crear_partida("pedro", "ciencia", 5, 15, receptor())
    end

    test "errores de creación, en orden" do
      assert {:error, :parametros_invalidos} =
               GestorPartidas.crear_partida("pedro", "historia", 11, 15, receptor())

      assert {:error, :parametros_invalidos} =
               GestorPartidas.crear_partida("pedro", "historia", 5, 0, receptor())

      assert {:error, :tema_inexistente} =
               GestorPartidas.crear_partida("pedro", "cocina", 5, 15, receptor())

      assert {:error, :preguntas_insuficientes} =
               GestorPartidas.crear_partida("pedro", "escaso", 5, 15, receptor())

      # Ninguno dejó al jugador atrapado en una partida a medias
      assert {:ok, %{id: "P-1001"}} =
               GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())
    end

    test "add_bot agrega hasta tres bots y el cuarto da partida llena" do
      {:ok, _} = GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())

      assert {:ok, "bot_1"} = GestorPartidas.agregar_bot("pedro", :facil)
      assert {:ok, "bot_2"} = GestorPartidas.agregar_bot("pedro", :dificil)
      assert {:ok, "bot_3"} = GestorPartidas.agregar_bot("pedro", :facil)
      assert {:error, :partida_llena} = GestorPartidas.agregar_bot("pedro", :facil)
    end

    test "add_bot con una dificultad desconocida se rechaza" do
      {:ok, _} = GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())

      assert {:error, :parametros_invalidos} = GestorPartidas.agregar_bot("pedro", :medio)
    end

    test "add_bot y abandonar sin partida" do
      assert {:error, :sin_partida} = GestorPartidas.agregar_bot("pedro", :facil)
      assert {:error, :sin_partida} = GestorPartidas.abandonar("pedro")
    end

    test "abandonar cancela la partida, no se registra y el jugador queda libre" do
      {:ok, %{id: "P-1001"}} =
        GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())

      {:ok, "bot_1"} = GestorPartidas.agregar_bot("pedro", :facil)

      assert {:ok, %{id: "P-1001", resultado: :cancelada}} = GestorPartidas.abandonar("pedro")
      assert {:error, :sin_partida} = GestorPartidas.agregar_bot("pedro", :facil)
      assert {:error, :sin_partida} = GestorPartidas.abandonar("pedro")
      assert {:ok, []} = Persistencia.leer_historial()

      # Puede crear otra enseguida, con un id nuevo
      assert {:ok, %{id: "P-1002"}} =
               GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())
    end

    test "iniciar_partida y responder sin partida" do
      assert {:error, :sin_partida} = GestorPartidas.iniciar_partida("pedro")
      assert {:error, :sin_partida} = GestorPartidas.responder("pedro", "A")
    end

    test "iniciar_partida exige 2 bots y responder exige una ronda abierta" do
      # La prueba es el receptor de la partida
      {:ok, _} = GestorPartidas.crear_partida("pedro", "historia", 5, 15, self())
      {:ok, "bot_1"} = GestorPartidas.agregar_bot("pedro", :facil)

      assert {:error, :bots_insuficientes} = GestorPartidas.iniciar_partida("pedro")
      assert {:error, :sin_ronda_abierta} = GestorPartidas.responder("pedro", "A")

      {:ok, "bot_2"} = GestorPartidas.agregar_bot("pedro", :facil)
      assert {:ok, %{id: "P-1001", total: 5}} = GestorPartidas.iniciar_partida("pedro")
      assert_receive {:pregunta, %{numero: 1}}, 1000

      assert {:error, :partida_iniciada} = GestorPartidas.iniciar_partida("pedro")
      assert {:error, :partida_iniciada} = GestorPartidas.agregar_bot("pedro", :facil)
      assert {:error, :letra_invalida} = GestorPartidas.responder("pedro", "E")
      assert {:ok, :recibida} = GestorPartidas.responder("pedro", "D")
      assert {:error, :respuesta_repetida} = GestorPartidas.responder("pedro", "A")
    end

    test "abandonar en curso responde :abandonada, registra la partida y libera al jugador" do
      {:ok, %{id: "P-1001"}} =
        GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())

      {:ok, "bot_1"} = GestorPartidas.agregar_bot("pedro", :facil)
      {:ok, "bot_2"} = GestorPartidas.agregar_bot("pedro", :facil)
      {:ok, %{id: "P-1001"}} = GestorPartidas.iniciar_partida("pedro")
      assert_receive {:pregunta, %{numero: 1}}, 1000

      assert {:ok, %{id: "P-1001", resultado: :abandonada}} = GestorPartidas.abandonar("pedro")

      assert_receive {:fin_partida, %{id: "P-1001", ranking: ranking}}
      assert length(ranking) == 3
      assert {:ok, [linea]} = Persistencia.leer_historial()
      assert linea =~ "|P-1001|historia|basico|"
      assert linea =~ "pedro:0,bot_1:0,bot_2:0"

      assert {:error, :sin_partida} = GestorPartidas.agregar_bot("pedro", :facil)
      assert {:error, :sin_partida} = GestorPartidas.abandonar("pedro")

      assert {:ok, %{id: "P-1002"}} =
               GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())
    end

    test "dos jugadores con partidas distintas no se interfieren" do
      {:ok, %{id: "P-1001"}} =
        GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())

      {:ok, %{id: "P-1002"}} =
        GestorPartidas.crear_partida("carlos", "ciencia", 10, 30, receptor())

      assert {:ok, "bot_1"} = GestorPartidas.agregar_bot("pedro", :facil)
      assert {:ok, "bot_2"} = GestorPartidas.agregar_bot("pedro", :facil)
      assert {:ok, "bot_1"} = GestorPartidas.agregar_bot("carlos", :dificil)

      assert {:ok, %{id: "P-1001"}} = GestorPartidas.abandonar("pedro")

      # La de carlos sigue intacta
      assert {:ok, "bot_2"} = GestorPartidas.agregar_bot("carlos", :facil)
    end

    test "si la partida cae y se reinicia, el gestor sigue su nuevo proceso" do
      {:ok, _} = GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())
      {:ok, "bot_1"} = GestorPartidas.agregar_bot("pedro", :facil)

      [{:undefined, pid, :worker, _}] = DynamicSupervisor.which_children(:supervisor_partidas)
      referencia = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^referencia, :process, ^pid, :killed}

      # Mientras no llega el aviso del reinicio, el pid viejo no vive y se responde
      # :sin_partida sin caerse. Cuando llega, la partida nueva empieza sin bots.
      assert {:ok, "bot_1"} = esperar_bot("pedro", :dificil)

      assert {:error, :ya_en_partida} =
               GestorPartidas.crear_partida("pedro", "ciencia", 5, 15, receptor())
    end

    test "al crear una partida no hay aviso de reinicio (el pid es el mismo)" do
      {:ok, _} = GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())

      # Esta petición vuelve después de que el gestor atendió el {:partida_iniciada, ...}
      {:ok, "bot_1"} = GestorPartidas.agregar_bot("pedro", :facil)

      refute_received {:aviso, _}
    end

    test "matar una partida en curso: reinicia en espera, avisa al creador y todo sigue" do
      {:ok, %{id: "P-1001"}} =
        GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())

      {:ok, "bot_1"} = GestorPartidas.agregar_bot("pedro", :facil)
      {:ok, "bot_2"} = GestorPartidas.agregar_bot("pedro", :dificil)
      {:ok, _} = GestorPartidas.iniciar_partida("pedro")
      assert_receive {:pregunta, %{numero: 1}}, 1000

      [{:undefined, viejo, :worker, _}] = DynamicSupervisor.which_children(:supervisor_partidas)
      bots = Enum.map(:sys.get_state(viejo).bots, fn bot -> bot.pid end)
      monitores = Enum.map([viejo | bots], &Process.monitor/1)

      Process.exit(viejo, :kill)

      # El creador recibe el aviso, y los bots mueren con la partida (estaban enlazados)
      assert_receive {:aviso, "Tu partida falló y se reinició sin progreso." <> _ = aviso}, 1000
      assert aviso =~ "Agrega bots y ejecuta start_game."

      for monitor <- monitores do
        assert_receive {:DOWN, ^monitor, :process, _pid, _motivo}, 1000
      end

      # La partida nueva: otro pid, en espera, solo el creador, sin bots ni puntajes
      [{:undefined, nuevo, :worker, _}] = DynamicSupervisor.which_children(:supervisor_partidas)
      assert nuevo != viejo

      assert %Trivia.Partida{
               id: "P-1001",
               creador: "pedro",
               estado: :esperando,
               bots: [],
               puntajes: %{},
               ronda: nil,
               preguntas: []
             } = :sys.get_state(nuevo)

      # No se escribió nada en el historial y el creador sigue «en partida»
      assert {:ok, []} = Persistencia.leer_historial()

      assert {:error, :ya_en_partida} =
               GestorPartidas.crear_partida("pedro", "ciencia", 5, 15, receptor())

      # Puede agregar bots y empezar de nuevo
      assert {:error, :bots_insuficientes} = GestorPartidas.iniciar_partida("pedro")
      assert {:ok, "bot_1"} = GestorPartidas.agregar_bot("pedro", :facil)
      assert {:ok, "bot_2"} = GestorPartidas.agregar_bot("pedro", :facil)
      assert {:ok, %{id: "P-1001", total: 5}} = GestorPartidas.iniciar_partida("pedro")
      assert_receive {:pregunta, %{numero: 1}}, 1000
    end

    test "matar la partida de uno no toca la de otro" do
      {:ok, %{id: "P-1001"}} =
        GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())

      {:ok, %{id: "P-1002"}} =
        GestorPartidas.crear_partida("carlos", "ciencia", 5, 15, receptor())

      {:ok, "bot_1"} = GestorPartidas.agregar_bot("carlos", :facil)

      [{_, p1, _, _}, {_, p2, _, _}] = DynamicSupervisor.which_children(:supervisor_partidas)

      de_pedro =
        Enum.find([p1, p2], fn pid -> :sys.get_state(pid).creador == "pedro" end)

      de_carlos = if de_pedro == p1, do: p2, else: p1

      Process.exit(de_pedro, :kill)
      assert_receive {:aviso, _}, 1000

      # La de carlos conserva su bot
      assert Process.alive?(de_carlos)
      assert [%{nombre: "bot_1"}] = :sys.get_state(de_carlos).bots
    end

    test "un mensaje desconocido no tumba al gestor" do
      gestor = Process.whereis(:gestor_partidas)

      send(:gestor_partidas, :basura)
      send(:gestor_partidas, {:partida_terminada, "P-9999"})

      assert {:ok, %{id: "P-1001"}} =
               GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())

      assert Process.whereis(:gestor_partidas) == gestor
    end

    test "sin questions.json el banco está vacío y todo tema es inexistente", %{tmp_dir: carpeta} do
      :ok = GestorPartidas.detener()
      File.rm!(Path.join(carpeta, "questions.json"))
      {:ok, _pid} = GestorPartidas.iniciar()

      assert {:error, :tema_inexistente} =
               GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())
    end

    test "con questions.json dañado no arranca y no deja nada registrado", %{tmp_dir: carpeta} do
      :ok = GestorPartidas.detener()
      File.write!(Path.join(carpeta, "questions.json"), "esto no es json")

      assert {:error, :json_invalido} = GestorPartidas.iniciar()
      assert Process.whereis(:gestor_partidas) == nil
    end

    test "sin el gestor en marcha todas las funciones informan el error" do
      :ok = GestorPartidas.detener()

      assert {:error, :servidor_no_disponible} =
               GestorPartidas.crear_partida("pedro", "historia", 5, 15, receptor())

      assert {:error, :servidor_no_disponible} = GestorPartidas.agregar_bot("pedro", :facil)
      assert {:error, :servidor_no_disponible} = GestorPartidas.abandonar("pedro")
      assert {:error, :servidor_no_disponible} = GestorPartidas.iniciar_partida("pedro")
      assert {:error, :servidor_no_disponible} = GestorPartidas.responder("pedro", "A")
    end
  end
end
