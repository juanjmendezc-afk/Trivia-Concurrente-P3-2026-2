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
      assert %{nombre: "bot_1", dificultad: :facil} in partida.bots
      assert %{nombre: "bot_2", dificultad: :dificil} in partida.bots
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
end
