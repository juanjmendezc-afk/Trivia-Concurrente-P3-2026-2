defmodule Trivia.ServidorPartidasTest do
  # create_game, add_bot y leave_game pasando por el Servidor, como los envía un cliente.
  # No es async: los procesos del servidor tienen nombres globales.
  use ExUnit.Case, async: false

  alias Trivia.AyudaPruebas
  alias Trivia.Servidor

  # Cada prueba usa una carpeta temporal propia (nunca toca data/)
  @moduletag :tmp_dir

  setup %{tmp_dir: carpeta} do
    AyudaPruebas.escribir_preguntas(carpeta)
    {:ok, _pid} = Servidor.iniciar(carpeta)
    on_exit(fn -> Servidor.detener() end)
    :ok
  end

  # Un cliente falso: reenvía a la prueba todo lo que le llegue del servidor
  defp cliente_falso do
    prueba = self()
    spawn(fn -> reenviar(prueba) end)
  end

  defp reenviar(prueba) do
    receive do
      mensaje ->
        send(prueba, {:recibido, self(), mensaje})
        reenviar(prueba)
    end
  end

  defp peticion(cliente, mensaje) do
    send(:servidor, mensaje)

    receive do
      {:recibido, ^cliente, {:respuesta, respuesta}} -> respuesta
    after
      1000 -> :sin_respuesta
    end
  end

  defp conectar(usuario) do
    cliente = cliente_falso()
    {:ok, _} = peticion(cliente, {:connect, cliente, usuario, "1234"})
    cliente
  end

  defp crear(cliente, tema \\ "historia", preguntas \\ 5, tiempo \\ 15) do
    peticion(cliente, {:create_game, cliente, tema, preguntas, tiempo, cliente})
  end

  describe "sin sesión" do
    test "las peticiones de partida piden iniciar sesión" do
      cliente = cliente_falso()

      assert {:error, :sin_sesion} = crear(cliente)
      assert {:error, :sin_sesion} = peticion(cliente, {:add_bot, cliente, :facil})
      assert {:error, :sin_sesion} = peticion(cliente, {:leave_game, cliente})
      assert {:error, :sin_sesion} = peticion(cliente, {:start_game, cliente})
      assert {:error, :sin_sesion} = peticion(cliente, {:answer, cliente, "A"})
    end
  end

  describe "start_game y answer" do
    test "sin partida" do
      pedro = conectar("pedro")

      assert {:error, :sin_partida} = peticion(pedro, {:start_game, pedro})
      assert {:error, :sin_partida} = peticion(pedro, {:answer, pedro, "A"})
    end

    test "con menos de 2 bots no inicia y no hay ronda para responder" do
      pedro = conectar("pedro")
      {:ok, _} = crear(pedro)
      {:ok, "bot_1"} = peticion(pedro, {:add_bot, pedro, :facil})

      assert {:error, :bots_insuficientes} = peticion(pedro, {:start_game, pedro})
      assert {:error, :sin_ronda_abierta} = peticion(pedro, {:answer, pedro, "A"})
    end

    test "inicia, la pregunta llega sola al receptor y se valida la respuesta" do
      pedro = conectar("pedro")
      {:ok, _} = crear(pedro)
      {:ok, _} = peticion(pedro, {:add_bot, pedro, :facil})
      {:ok, _} = peticion(pedro, {:add_bot, pedro, :facil})

      assert {:ok, %{id: "P-1001", total: 5}} = peticion(pedro, {:start_game, pedro})

      # El cliente falso también es el receptor de la partida
      assert_receive {:recibido, ^pedro, {:pregunta, pregunta}}, 1000
      assert %{numero: 1, total: 5, tiempo: 15} = pregunta
      refute Map.has_key?(pregunta, :respuesta)
      refute Map.has_key?(pregunta, :nivel)

      assert {:error, :partida_iniciada} = peticion(pedro, {:start_game, pedro})
      assert {:error, :partida_iniciada} = peticion(pedro, {:add_bot, pedro, :facil})

      assert {:error, :letra_invalida} = peticion(pedro, {:answer, pedro, "Z"})
      assert {:error, :letra_invalida} = peticion(pedro, {:answer, pedro, :a})
      assert {:ok, :recibida} = peticion(pedro, {:answer, pedro, "C"})
      assert {:error, :respuesta_repetida} = peticion(pedro, {:answer, pedro, "A"})
    end

    test "dos partidas a la vez: cada receptor recibe solo su pregunta" do
      pedro = conectar("pedro")
      carlos = conectar("carlos")
      {:ok, _} = crear(pedro, "historia", 5, 15)
      {:ok, _} = crear(carlos, "ciencia", 3, 20)

      for cliente <- [pedro, carlos], _ <- 1..2 do
        {:ok, _} = peticion(cliente, {:add_bot, cliente, :facil})
      end

      assert {:ok, %{id: "P-1001", total: 5}} = peticion(pedro, {:start_game, pedro})
      assert {:ok, %{id: "P-1002", total: 3}} = peticion(carlos, {:start_game, carlos})

      assert_receive {:recibido, ^pedro, {:pregunta, %{total: 5, tiempo: 15} = de_pedro}}, 1000
      assert_receive {:recibido, ^carlos, {:pregunta, %{total: 3, tiempo: 20} = de_carlos}}, 1000
      assert de_pedro.enunciado =~ "historia"
      assert de_carlos.enunciado =~ "ciencia"

      # La respuesta de uno no cuenta en la partida del otro
      assert {:ok, :recibida} = peticion(pedro, {:answer, pedro, "A"})
      assert {:ok, :recibida} = peticion(carlos, {:answer, carlos, "B"})
    end
  end

  describe "con sesión" do
    test "create_game responde el id y el nivel" do
      pedro = conectar("pedro")

      assert {:ok, %{id: "P-1001", nivel: :basico}} = crear(pedro)
    end

    test "el servidor identifica al jugador por su cliente: no hace falta enviar el usuario" do
      pedro = conectar("pedro")
      carlos = conectar("carlos")

      assert {:ok, %{id: "P-1001"}} = crear(pedro)
      assert {:ok, %{id: "P-1002"}} = crear(carlos, "ciencia", 10, 30)

      assert {:ok, "bot_1"} = peticion(pedro, {:add_bot, pedro, :facil})
      assert {:ok, "bot_1"} = peticion(carlos, {:add_bot, carlos, :dificil})
      assert {:ok, "bot_2"} = peticion(carlos, {:add_bot, carlos, :dificil})
    end

    test "flujo completo: bots hasta llenarla, salir y crear otra" do
      pedro = conectar("pedro")
      {:ok, %{id: "P-1001"}} = crear(pedro)

      assert {:ok, "bot_1"} = peticion(pedro, {:add_bot, pedro, :facil})
      assert {:ok, "bot_2"} = peticion(pedro, {:add_bot, pedro, :facil})
      assert {:ok, "bot_3"} = peticion(pedro, {:add_bot, pedro, :facil})
      assert {:error, :partida_llena} = peticion(pedro, {:add_bot, pedro, :facil})

      assert {:ok, %{id: "P-1001", resultado: :cancelada}} =
               peticion(pedro, {:leave_game, pedro})

      assert {:ok, %{id: "P-1002"}} = crear(pedro)
    end

    test "errores de create_game" do
      pedro = conectar("pedro")

      assert {:error, :tema_inexistente} = crear(pedro, "cocina")
      assert {:error, :preguntas_insuficientes} = crear(pedro, "escaso")
      assert {:error, :parametros_invalidos} = crear(pedro, "historia", 11, 15)
      assert {:error, :parametros_invalidos} = crear(pedro, "historia", 5, 0)

      {:ok, _} = crear(pedro)
      assert {:error, :ya_en_partida} = crear(pedro)
    end

    test "add_bot y leave_game sin partida" do
      pedro = conectar("pedro")

      assert {:error, :sin_partida} = peticion(pedro, {:add_bot, pedro, :facil})
      assert {:error, :sin_partida} = peticion(pedro, {:leave_game, pedro})
    end

    test "una dificultad desconocida se rechaza sin tumbar nada" do
      pedro = conectar("pedro")
      {:ok, _} = crear(pedro)
      servidor = Process.whereis(:servidor)

      assert {:error, :parametros_invalidos} = peticion(pedro, {:add_bot, pedro, :loco})
      assert {:ok, "bot_1"} = peticion(pedro, {:add_bot, pedro, :facil})
      assert Process.whereis(:servidor) == servidor
    end

    test "una petición de partida mal formada se rechaza como comando inválido" do
      pedro = conectar("pedro")

      assert {:error, :comando_invalido} = peticion(pedro, {:create_game, pedro, "historia"})
      assert {:error, :comando_invalido} = peticion(pedro, {:add_bot, pedro})
    end

    test "los datos de una partida de otro jugador no se tocan" do
      pedro = conectar("pedro")
      carlos = conectar("carlos")
      {:ok, _} = crear(pedro)

      # Carlos no está en ninguna partida aunque pedro sí
      assert {:error, :sin_partida} = peticion(carlos, {:add_bot, carlos, :facil})
      assert {:error, :sin_partida} = peticion(carlos, {:leave_game, carlos})
      assert {:ok, "bot_1"} = peticion(pedro, {:add_bot, pedro, :facil})
    end
  end

  describe "abandono y desconexión" do
    alias Trivia.Persistencia

    # Crea la partida con 2 bots, la inicia y espera la primera pregunta
    defp en_curso(cliente, tema \\ "historia") do
      {:ok, %{id: id}} = crear(cliente, tema)
      {:ok, _} = peticion(cliente, {:add_bot, cliente, :facil})
      {:ok, _} = peticion(cliente, {:add_bot, cliente, :facil})
      {:ok, _} = peticion(cliente, {:start_game, cliente})
      assert_receive {:recibido, ^cliente, {:pregunta, %{numero: 1}}}, 1000
      id
    end

    defp lineas_del_historial do
      {:ok, lineas} = Persistencia.leer_historial()
      lineas
    end

    # Sin dormir: reintenta conectar hasta que el servidor ya cerró la sesión vieja
    defp conectar_cuando_libre(usuario, limite \\ System.monotonic_time(:millisecond) + 2000) do
      cliente = cliente_falso()

      case peticion(cliente, {:connect, cliente, usuario, "1234"}) do
        {:ok, _datos} ->
          cliente

        {:error, :ya_conectado} ->
          if System.monotonic_time(:millisecond) < limite do
            conectar_cuando_libre(usuario, limite)
          else
            flunk("la sesión de #{usuario} no se cerró")
          end
      end
    end

    test "leave_game en curso responde :abandonada, registra la partida y libera al jugador" do
      pedro = conectar("pedro")
      id = en_curso(pedro)

      assert {:ok, %{id: ^id, resultado: :abandonada}} = peticion(pedro, {:leave_game, pedro})

      assert_receive {:recibido, ^pedro, {:fin_partida, %{id: ^id, ranking: ranking}}}
      assert [_, _, _] = ranking
      assert [linea] = lineas_del_historial()
      assert linea =~ "|P-1001|historia|basico|"
      assert linea =~ "pedro:0,bot_1:0,bot_2:0"

      # Sigue conectado y puede crear otra partida
      assert {:error, :sin_partida} = peticion(pedro, {:leave_game, pedro})
      assert {:ok, %{id: "P-1002"}} = crear(pedro)
    end

    test "disconnect en curso termina la partida, la registra y libera al usuario" do
      pedro = conectar("pedro")
      en_curso(pedro)

      assert {:ok, %{usuario: "pedro"}} = peticion(pedro, {:disconnect, pedro})

      assert_receive {:recibido, ^pedro, {:fin_partida, %{id: "P-1001"}}}
      assert [linea] = lineas_del_historial()
      assert linea =~ "|P-1001|historia|basico|"

      # Al volver a conectar no queda atrapado en la partida vieja
      pedro_2 = conectar("pedro")
      assert {:error, :sin_partida} = peticion(pedro_2, {:add_bot, pedro_2, :facil})
      assert {:ok, %{id: "P-1002"}} = crear(pedro_2)
    end

    test "disconnect en espera cancela la partida y no registra nada" do
      pedro = conectar("pedro")
      {:ok, %{id: "P-1001"}} = crear(pedro)
      {:ok, _} = peticion(pedro, {:add_bot, pedro, :facil})

      assert {:ok, %{usuario: "pedro"}} = peticion(pedro, {:disconnect, pedro})

      assert [] = lineas_del_historial()
      refute_received {:recibido, ^pedro, {:fin_partida, _}}

      pedro_2 = conectar("pedro")
      assert {:ok, %{id: "P-1002"}} = crear(pedro_2)
    end

    test "disconnect sin partida sigue funcionando" do
      pedro = conectar("pedro")

      assert {:ok, %{usuario: "pedro"}} = peticion(pedro, {:disconnect, pedro})
      assert [] = lineas_del_historial()
    end

    test "si el cliente se cierra en plena partida, la partida termina y se registra" do
      pedro = conectar("pedro")
      en_curso(pedro)
      servidor = Process.whereis(:servidor)
      referencia = Process.monitor(pedro)

      Process.exit(pedro, :kill)
      assert_receive {:DOWN, ^referencia, :process, ^pedro, :killed}

      # El usuario queda libre: otro cliente puede entrar con ese nombre y crear partida
      pedro_2 = conectar_cuando_libre("pedro")
      assert {:ok, %{id: "P-1002"}} = crear(pedro_2)

      assert [linea] = lineas_del_historial()
      assert linea =~ "|P-1001|historia|basico|"
      assert Process.whereis(:servidor) == servidor
    end

    test "si el cliente se cierra con la partida en espera, se cancela sin registrar" do
      pedro = conectar("pedro")
      {:ok, %{id: "P-1001"}} = crear(pedro)
      referencia = Process.monitor(pedro)

      Process.exit(pedro, :kill)
      assert_receive {:DOWN, ^referencia, :process, ^pedro, :killed}

      pedro_2 = conectar_cuando_libre("pedro")
      assert {:ok, %{id: "P-1002"}} = crear(pedro_2)
      assert [] = lineas_del_historial()
    end

    test "si se mata la partida en curso, el cliente recibe el aviso y puede empezar de nuevo" do
      pedro = conectar("pedro")
      en_curso(pedro)
      [{:undefined, partida, :worker, _}] = DynamicSupervisor.which_children(:supervisor_partidas)

      Process.exit(partida, :kill)

      assert_receive {:recibido, ^pedro, {:aviso, "Tu partida falló y se reinició" <> _}}, 1000
      assert [] = lineas_del_historial()

      # Sigue en su partida (ya en espera): vuelve a agregar bots e iniciar
      assert {:error, :ya_en_partida} = crear(pedro)
      assert {:error, :bots_insuficientes} = peticion(pedro, {:start_game, pedro})
      assert {:ok, "bot_1"} = peticion(pedro, {:add_bot, pedro, :facil})
      assert {:ok, "bot_2"} = peticion(pedro, {:add_bot, pedro, :facil})
      assert {:ok, %{id: "P-1001"}} = peticion(pedro, {:start_game, pedro})
      assert_receive {:recibido, ^pedro, {:pregunta, %{numero: 1}}}, 1000
    end

    test "cerrar un cliente no afecta la partida de otro" do
      pedro = conectar("pedro")
      carlos = conectar("carlos")
      en_curso(pedro)
      en_curso(carlos, "ciencia")

      assert {:ok, %{usuario: "pedro"}} = peticion(pedro, {:disconnect, pedro})
      assert_receive {:recibido, ^pedro, {:fin_partida, %{id: "P-1001"}}}

      # La de carlos sigue: acepta su respuesta y no se registró
      assert {:ok, :recibida} = peticion(carlos, {:answer, carlos, "A"})
      refute_received {:recibido, ^carlos, {:fin_partida, _}}
      assert [linea] = lineas_del_historial()
      assert linea =~ "|P-1001|historia|"
    end
  end

  describe "score y ranking" do
    # Varias partidas: dos temas, pedro y carlos, bots y una línea dañada
    defp historial_previo(carpeta) do
      lineas = [
        "2026-11-10 20:15:03|P-0901|historia|basico|pedro|pedro:45,bot_1:30,bot_2:-5",
        "2026-11-10 20:31:47|P-0902|ciencia|basico|bot_2|carlos:20,bot_1:15,bot_2:38",
        "linea dañada",
        "2026-11-11 09:00:00|P-0903|historia|basico|bot_1|pedro:15,bot_1:40,bot_2:10",
        "2026-11-11 10:00:00|P-0904|historia|basico|bot_1|carlos:-8,bot_1:25,bot_2:5"
      ]

      File.write!(Path.join(carpeta, "results.log"), Enum.join(lineas, "\n") <> "\n")
    end

    test "sin sesión piden iniciar sesión" do
      cliente = cliente_falso()

      assert {:error, :sin_sesion} = peticion(cliente, {:score, cliente})
      assert {:error, :sin_sesion} = peticion(cliente, {:ranking, cliente, nil})
      assert {:error, :sin_sesion} = peticion(cliente, {:ranking, cliente, "historia"})
    end

    test "score de cada usuario sale del historial", %{tmp_dir: carpeta} do
      historial_previo(carpeta)
      pedro = conectar("pedro")
      carlos = conectar("carlos")

      assert {:ok,
              %{
                puntaje: 60,
                partidas: 2,
                por_tema: %{"historia" => %{puntaje: 60, nivel: :intermedio}}
              }} = peticion(pedro, {:score, pedro})

      assert {:ok, %{puntaje: 12, partidas: 2, por_tema: por_tema}} =
               peticion(carlos, {:score, carlos})

      assert por_tema == %{
               "ciencia" => %{puntaje: 20, nivel: :basico},
               "historia" => %{puntaje: -8, nivel: :basico}
             }
    end

    test "un jugador nuevo tiene todo en cero", %{tmp_dir: carpeta} do
      historial_previo(carpeta)
      maria = conectar("maria")

      assert {:ok, %{puntaje: 0, partidas: 0, por_tema: %{}}} = peticion(maria, {:score, maria})
    end

    test "ranking global y por tema, sin bots", %{tmp_dir: carpeta} do
      historial_previo(carpeta)
      pedro = conectar("pedro")

      assert {:ok, [{"pedro", 60}, {"carlos", 12}]} = peticion(pedro, {:ranking, pedro, nil})

      assert {:ok, [{"pedro", 60}, {"carlos", -8}]} =
               peticion(pedro, {:ranking, pedro, "historia"})

      assert {:ok, [{"carlos", 20}]} = peticion(pedro, {:ranking, pedro, "ciencia"})
      assert {:ok, [{"carlos", 20}]} = peticion(pedro, {:ranking, pedro, "CIENCIA"})
      assert {:ok, []} = peticion(pedro, {:ranking, pedro, "geografia"})
    end

    test "sin historial: ranking vacío y score en cero" do
      pedro = conectar("pedro")

      assert {:ok, []} = peticion(pedro, {:ranking, pedro, nil})
      assert {:ok, %{puntaje: 0, partidas: 0}} = peticion(pedro, {:score, pedro})
    end

    test "un tema que no es texto se rechaza y el servidor sigue" do
      pedro = conectar("pedro")

      assert {:error, :parametros_invalidos} = peticion(pedro, {:ranking, pedro, 123})
      assert {:ok, []} = peticion(pedro, {:ranking, pedro, nil})
    end

    test "si no se puede leer el historial devuelven el error y el gestor sigue vivo" do
      pedro = conectar("pedro")
      gestor = Process.whereis(:gestor_jugadores)
      :ok = Trivia.Persistencia.detener()

      assert {:error, :persistencia_no_disponible} = peticion(pedro, {:score, pedro})
      assert {:error, :persistencia_no_disponible} = peticion(pedro, {:ranking, pedro, nil})
      assert Process.alive?(gestor)
      assert {:ok, %{usuario: "pedro"}} = peticion(pedro, {:disconnect, pedro})
    end

    test "coinciden con una partida real terminada contra 2 bots (criterio 11)" do
      pedro = conectar("pedro")
      {:ok, %{id: id}} = crear(pedro, "historia", 1, 1)
      {:ok, _} = peticion(pedro, {:add_bot, pedro, :facil})
      {:ok, _} = peticion(pedro, {:add_bot, pedro, :dificil})
      {:ok, _} = peticion(pedro, {:start_game, pedro})
      {:ok, :recibida} = peticion(pedro, {:answer, pedro, "A"})

      # El temporizador (1 s) o los bots cierran la única ronda
      assert_receive {:recibido, ^pedro, {:fin_partida, %{id: ^id, ranking: ranking}}}, 3000
      [{_posicion, "pedro", puntos}] = Enum.filter(ranking, &match?({_, "pedro", _}, &1))

      assert {:ok, %{puntaje: ^puntos, partidas: 1, por_tema: por_tema}} =
               peticion(pedro, {:score, pedro})

      assert por_tema == %{"historia" => %{puntaje: puntos, nivel: Trivia.Nivel.calcular(puntos)}}

      # En el histórico solo aparece el humano, con el mismo puntaje
      assert {:ok, [{"pedro", ^puntos}]} = peticion(pedro, {:ranking, pedro, nil})
      assert {:ok, [{"pedro", ^puntos}]} = peticion(pedro, {:ranking, pedro, "historia"})
    end
  end

  describe "nivel del creador según el historial" do
    # Deja un historial previo en la carpeta temporal (se lee en cada create_game)
    defp escribir_historial(carpeta, lineas) do
      File.write!(Path.join(carpeta, "results.log"), Enum.join(lineas, "\n") <> "\n")
    end

    test "con 60 puntos en un tema la partida nueva sale intermedio; otro tema, básico",
         %{tmp_dir: carpeta} do
      escribir_historial(carpeta, [
        "2026-11-10 20:15:03|P-0901|historia|basico|pedro|pedro:45,bot_1:30,bot_2:-5",
        "2026-11-11 09:00:00|P-0902|historia|basico|bot_1|pedro:15,bot_1:40,bot_2:10"
      ])

      pedro = conectar("pedro")

      assert {:ok, %{nivel: :intermedio}} = crear(pedro, "historia")
      assert {:ok, %{resultado: :cancelada}} = peticion(pedro, {:leave_game, pedro})
      assert {:ok, %{nivel: :basico}} = crear(pedro, "ciencia")
    end

    test "el nivel es de cada jugador: 59 sigue en básico y 180 es avanzado",
         %{tmp_dir: carpeta} do
      escribir_historial(carpeta, [
        "2026-11-10 20:15:03|P-0901|historia|basico|carlos|carlos:59,bot_1:30,bot_2:-5",
        "2026-11-10 21:00:00|P-0902|historia|basico|ana|ana:100,bot_1:30,bot_2:-5",
        "2026-11-11 09:00:00|P-0903|historia|intermedio|ana|ana:80,bot_1:40,bot_2:10"
      ])

      carlos = conectar("carlos")
      ana = conectar("ana")
      nuevo = conectar("nuevo")

      assert {:ok, %{nivel: :basico}} = crear(carlos, "historia")
      assert {:ok, %{nivel: :avanzado}} = crear(ana, "historia")
      assert {:ok, %{nivel: :basico}} = crear(nuevo, "historia")
    end

    test "las líneas dañadas del historial se saltan", %{tmp_dir: carpeta} do
      escribir_historial(carpeta, [
        "esto no es una línea",
        "2026-11-10 20:15:03|P-0901|historia|basico|pedro|pedro:60,bot_1:30,bot_2:-5",
        "2026-11-10 20:20:00|P-0902|historia|basico|pedro|pedro:mil"
      ])

      pedro = conectar("pedro")

      assert {:ok, %{nivel: :intermedio}} = crear(pedro, "historia")
    end

    test "si no se puede leer el historial usa 0 puntos y avisa en el servidor",
         %{tmp_dir: carpeta} do
      escribir_historial(carpeta, [
        "2026-11-10 20:15:03|P-0901|historia|basico|pedro|pedro:200,bot_1:30,bot_2:-5"
      ])

      pedro = conectar("pedro")
      :ok = Trivia.Persistencia.detener()

      salida =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          assert {:ok, %{nivel: :basico}} = crear(pedro, "historia")
        end)

      assert salida =~ "No se pudo leer el historial"
    end
  end

  describe "arranque y parada" do
    test "arranca el supervisor y el gestor de partidas" do
      assert is_pid(Process.whereis(:supervisor_partidas))
      assert is_pid(Process.whereis(:gestor_partidas))
    end

    test "detener no deja nada en marcha" do
      :ok = Servidor.detener()

      for nombre <- [
            :servidor,
            :gestor_partidas,
            :supervisor_partidas,
            :gestor_jugadores,
            :persistencia
          ] do
        assert Process.whereis(nombre) == nil, "sigue en marcha: #{nombre}"
      end
    end

    test "detener termina las partidas en curso" do
      pedro = conectar("pedro")
      {:ok, _} = crear(pedro)
      [{:undefined, pid, :worker, _}] = DynamicSupervisor.which_children(:supervisor_partidas)
      referencia = Process.monitor(pid)

      :ok = Servidor.detener()

      assert_receive {:DOWN, ^referencia, :process, ^pid, _razon}
    end

    test "con questions.json dañado no arranca y no deja nada en marcha", %{tmp_dir: carpeta} do
      :ok = Servidor.detener()
      File.write!(Path.join(carpeta, "questions.json"), "esto no es json")

      assert {:error, :json_invalido} = Servidor.iniciar(carpeta)

      for nombre <- [
            :servidor,
            :gestor_partidas,
            :supervisor_partidas,
            :gestor_jugadores,
            :persistencia
          ] do
        assert Process.whereis(nombre) == nil, "sigue en marcha: #{nombre}"
      end
    end
  end
end
