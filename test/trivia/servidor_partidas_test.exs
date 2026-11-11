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
