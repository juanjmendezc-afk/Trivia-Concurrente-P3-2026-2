defmodule Trivia.NivelTest do
  use ExUnit.Case, async: true

  alias Trivia.Nivel

  test "calcula los niveles en los límites definidos" do
    assert Nivel.calcular(-10) == :basico
    assert Nivel.calcular(59) == :basico
    assert Nivel.calcular(60) == :intermedio
    assert Nivel.calcular(179) == :intermedio
    assert Nivel.calcular(180) == :avanzado
  end

  test "rechaza puntajes que no son enteros" do
    assert Nivel.calcular(10.5) == {:error, :puntaje_invalido}
  end

  test "reparte preguntas para cada nivel y conserva el total" do
    assert Nivel.reparto(:basico, 10) ==
             %{basico: 7, intermedio: 3, avanzado: 0}

    assert Nivel.reparto(:intermedio, 10) ==
             %{basico: 2, intermedio: 6, avanzado: 2}

    assert Nivel.reparto(:avanzado, 10) ==
             %{basico: 0, intermedio: 3, avanzado: 7}

    assert Nivel.reparto(:basico, 5) ==
             %{basico: 4, intermedio: 1, avanzado: 0}
  end

  test "el reparto devuelve el total solicitado incluso con redondeos" do
    for nivel <- [:basico, :intermedio, :avanzado], total <- 1..30 do
      cantidades = Nivel.reparto(nivel, total)
      assert Enum.sum(Map.values(cantidades)) == total
    end
  end
end
