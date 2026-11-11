defmodule Trivia.SupervisorPartidasTest do
  # No es async: el supervisor y :gestor_partidas son nombres globales
  use ExUnit.Case, async: false

  alias Trivia.AyudaPruebas
  alias Trivia.Partida
  alias Trivia.SupervisorPartidas

  setup do
    {:ok, _pid} = SupervisorPartidas.iniciar()
    # La prueba hace de gestor: recibe los avisos {:partida_iniciada, ...}
    Process.register(self(), :gestor_partidas)
    on_exit(fn -> SupervisorPartidas.detener() end)
    :ok
  end

  defp argumentos(id) do
    %{
      id: id,
      creador: "pedro",
      tema: "historia",
      nivel: :basico,
      total_preguntas: 5,
      tiempo: 15,
      preguntas_tema: AyudaPruebas.banco_de_prueba(),
      receptor: self()
    }
  end

  # Crea una partida y consume su aviso de arranque
  defp crear(id) do
    {:ok, pid} = SupervisorPartidas.crear_partida(argumentos(id))
    assert_receive {:partida_iniciada, ^id, ^pid}
    pid
  end

  test "no se puede iniciar dos veces" do
    assert {:error, :ya_iniciado} = SupervisorPartidas.iniciar()
  end

  test "las partidas se declaran :transient" do
    assert %{restart: :transient} = Partida.child_spec(argumentos("P-1001"))
  end

  test "crear_partida arranca una Partida supervisada" do
    pid = crear("P-1001")

    assert [{:undefined, ^pid, :worker, [Partida]}] =
             DynamicSupervisor.which_children(:supervisor_partidas)

    assert {:ok, "bot_1"} = GenServer.call(pid, {:add_bot, :facil})
  end

  test "varias partidas conviven sin interferirse" do
    uno = crear("P-1001")
    otro = crear("P-1002")

    assert {:ok, "bot_1"} = GenServer.call(uno, {:add_bot, :facil})
    assert {:ok, "bot_2"} = GenServer.call(uno, {:add_bot, :facil})
    assert {:ok, "bot_1"} = GenServer.call(otro, {:add_bot, :dificil})
  end

  test "una partida que termina normal no se reinicia; una que cae, sí" do
    cancelada = crear("P-1001")
    caida = crear("P-1002")

    # P-1001 termina bien (el creador la cancela)
    referencia = Process.monitor(cancelada)
    assert {:ok, :cancelada} = GenServer.call(cancelada, {:abandonar, "pedro"})
    assert_receive {:DOWN, ^referencia, :process, ^cancelada, :normal}

    # P-1002 muere de golpe y el supervisor la arranca de nuevo con el mismo id
    {:ok, "bot_1"} = GenServer.call(caida, {:add_bot, :facil})
    Process.exit(caida, :kill)
    assert_receive {:partida_iniciada, "P-1002", nueva}
    assert nueva != caida
    assert Process.alive?(nueva)

    # La que terminó bien no volvió a arrancar (su aviso habría llegado antes)
    refute_received {:partida_iniciada, "P-1001", _}
    assert %{active: 1} = DynamicSupervisor.count_children(:supervisor_partidas)
  end

  test "la partida reiniciada vuelve a esperando, solo con el creador y sin bots" do
    pid = crear("P-1001")
    {:ok, "bot_1"} = GenServer.call(pid, {:add_bot, :facil})
    {:ok, "bot_2"} = GenServer.call(pid, {:add_bot, :facil})

    Process.exit(pid, :kill)
    assert_receive {:partida_iniciada, "P-1001", nueva}

    assert {:ok, "bot_1"} = GenServer.call(nueva, {:add_bot, :dificil})
  end

  test "detener termina también las partidas" do
    pid = crear("P-1001")
    referencia = Process.monitor(pid)

    assert :ok = SupervisorPartidas.detener()

    assert_receive {:DOWN, ^referencia, :process, ^pid, _razon}
    assert Process.whereis(:supervisor_partidas) == nil
  end

  test "sin supervisor en marcha, crear_partida informa el error" do
    :ok = SupervisorPartidas.detener()

    assert {:error, :servidor_no_disponible} =
             SupervisorPartidas.crear_partida(argumentos("P-1001"))
  end

  @tag capture_log: true
  test "argumentos inválidos no dejan una partida a medias" do
    assert {:error, :parametros_invalidos} = SupervisorPartidas.crear_partida(%{})
    assert [] = DynamicSupervisor.which_children(:supervisor_partidas)
  end
end
