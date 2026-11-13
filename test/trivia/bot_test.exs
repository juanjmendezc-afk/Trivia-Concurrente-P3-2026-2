defmodule Trivia.BotTest do
  use ExUnit.Case, async: true

  alias Trivia.Bot

  test "el bot devuelve una letra válida y un retardo permitido" do
    dificultades = [
      {:facil, 40, 90},
      {:dificil, 10, 40}
    ]

    niveles = [:basico, :intermedio, :avanzado]
    letras = ["A", "B", "C", "D"]

    for {dificultad, porcentaje_minimo, porcentaje_maximo} <- dificultades,
        nivel <- niveles,
        correcta <- letras,
        tiempo <- [1, 15, 30] do
      minimo_ms = div(tiempo * 1000 * porcentaje_minimo, 100)
      maximo_ms = div(tiempo * 1000 * porcentaje_maximo, 100)

      Enum.each(1..200, fn _intento ->
        {letra, retardo_ms} =
          Bot.decidir(dificultad, nivel, correcta, tiempo)

        assert letra in letras
        assert is_integer(retardo_ms)
        assert retardo_ms >= minimo_ms
        assert retardo_ms <= maximo_ms
      end)
    end
  end

  test "rechaza argumentos inválidos" do
    assert {:error, _} = Bot.decidir(:normal, :basico, "A", 15)
    assert {:error, _} = Bot.decidir(:facil, :experto, "A", 15)
    assert {:error, _} = Bot.decidir(:facil, :basico, "E", 15)
    assert {:error, _} = Bot.decidir(:facil, :basico, "A", 0)
    assert {:error, _} = Bot.decidir(:facil, :basico, "A", -5)
    assert {:error, _} = Bot.decidir(:facil, :basico, "A", 15.5)
  end

  # ---------- Proceso del bot ----------
  # La prueba hace de partida: recibe las llamadas del bot y las contesta a mano.

  describe "proceso" do
    @letras ["A", "B", "C", "D"]

    defp pregunta(numero) do
      {:pregunta,
       %{
         numero: numero,
         total: 3,
         enunciado: "¿...?",
         opciones: %{"A" => "uno", "B" => "dos", "C" => "tres", "D" => "cuatro"},
         tiempo: 1
       }}
    end

    # Contesta la consulta del bot por los datos de la pregunta
    defp entregar_datos(numero) do
      assert_receive {:"$gen_call", desde, :datos_pregunta}, 1000
      GenServer.reply(desde, {:ok, %{numero: numero, nivel: :basico, respuesta: "A"}})
    end

    test "al recibir la pregunta consulta a la partida y responde dentro de su rango" do
      bot = Bot.iniciar("bot_1", :dificil, self())
      inicio = System.monotonic_time(:millisecond)

      send(bot, pregunta(1))
      entregar_datos(1)

      # Responde por el mismo mensaje que un humano
      assert_receive {:"$gen_call", desde, {:responder, "bot_1", letra}}, 1000
      GenServer.reply(desde, {:ok, :recibida})
      demora = System.monotonic_time(:millisecond) - inicio

      assert letra in @letras
      # Difícil con 1 s: entre 100 y 400 ms (con margen por la carga de la máquina)
      assert demora >= 100
      assert demora < 900

      send(bot, {:fin_partida, %{}})
    end

    test "una respuesta programada para una ronda vieja no se envía" do
      bot = Bot.iniciar("bot_1", :dificil, self())

      # Llega la pregunta 2 antes de que venza el retardo de la 1
      send(bot, pregunta(1))
      entregar_datos(1)
      send(bot, pregunta(2))
      entregar_datos(2)

      assert_receive {:"$gen_call", desde, {:responder, "bot_1", _letra}}, 1000
      GenServer.reply(desde, {:ok, :recibida})

      # Termina el bot: para entonces ya procesó todo lo que tenía pendiente
      referencia = Process.monitor(bot)
      send(bot, {:fin_partida, %{}})
      assert_receive {:DOWN, ^referencia, :process, ^bot, :normal}, 1000

      refute_received {:"$gen_call", _desde, {:responder, _nombre, _letra}}
    end

    test "si la partida no tiene ronda abierta, no programa nada y sigue vivo" do
      bot = Bot.iniciar("bot_1", :facil, self())

      send(bot, pregunta(1))
      assert_receive {:"$gen_call", desde, :datos_pregunta}, 1000
      GenServer.reply(desde, {:error, :sin_ronda_abierta})

      send(bot, {:cierre_ronda, %{}})
      send(bot, :basura)

      assert Process.alive?(bot)
      send(bot, {:fin_partida, %{}})
    end

    test "termina solo al recibir el fin de la partida" do
      bot = Bot.iniciar("bot_2", :facil, self())
      referencia = Process.monitor(bot)

      send(bot, {:fin_partida, %{}})

      assert_receive {:DOWN, ^referencia, :process, ^bot, :normal}, 1000
    end
  end
end
