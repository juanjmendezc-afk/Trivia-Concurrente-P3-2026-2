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
end
