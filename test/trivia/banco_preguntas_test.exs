defmodule Trivia.BancoPreguntasTest do
  use ExUnit.Case, async: true

  alias Trivia.BancoPreguntas

  defp preguntas_string do
    for nivel <- ["basico", "intermedio", "avanzado"],
        numero <- 1..8 do
      %{
        "tema" => "historia",
        "nivel" => nivel,
        "enunciado" => "Pregunta #{nivel} #{numero}",
        "opciones" => %{"A" => "a", "B" => "b", "C" => "c", "D" => "d"},
        "respuesta" => "A"
      }
    end
  end

  # Es exactamente la estructura que entrega Trivia.Persistencia.cargar_preguntas/0.
  defp preguntas_atom do
    Enum.map(preguntas_string(), fn pregunta ->
      %{
        tema: pregunta["tema"],
        nivel: String.to_atom(pregunta["nivel"]),
        enunciado: pregunta["enunciado"],
        opciones: pregunta["opciones"],
        respuesta: pregunta["respuesta"]
      }
    end)
  end

  test "selecciona la cantidad solicitada y respeta el reparto" do
    assert {:ok, resultado} = BancoPreguntas.sortear(preguntas_string(), :intermedio, 10)
    assert length(resultado) == 10

    cantidades = Enum.frequencies_by(resultado, & &1["nivel"])
    assert cantidades == %{"basico" => 2, "intermedio" => 6, "avanzado" => 2}
  end

  test "acepta las preguntas normalizadas por Persistencia" do
    assert {:ok, resultado} = BancoPreguntas.sortear(preguntas_atom(), :intermedio, 10)
    assert length(resultado) == 10
    assert Enum.all?(resultado, &(&1.nivel in [:basico, :intermedio, :avanzado]))
  end

  test "ordena las preguntas de básico a avanzado" do
    assert {:ok, resultado} = BancoPreguntas.sortear(preguntas_atom(), :intermedio, 10)
    niveles = Enum.map(resultado, & &1.nivel)

    assert niveles ==
             Enum.sort_by(niveles, fn
               :basico -> 1
               :intermedio -> 2
               :avanzado -> 3
             end)
  end

  test "no repite preguntas en el mismo sorteo" do
    assert {:ok, resultado} = BancoPreguntas.sortear(preguntas_atom(), :basico, 10)
    enunciados = Enum.map(resultado, & &1.enunciado)
    assert length(enunciados) == length(Enum.uniq(enunciados))
  end

  test "todas las preguntas sorteadas son del tema recibido" do
    assert {:ok, resultado} = BancoPreguntas.sortear(preguntas_atom(), :avanzado, 10)
    assert Enum.all?(resultado, fn pregunta -> pregunta.tema == "historia" end)
  end

  test "el reparto del sorteo coincide con el de cada nivel del jugador" do
    for nivel <- [:basico, :intermedio, :avanzado] do
      assert {:ok, resultado} = BancoPreguntas.sortear(preguntas_atom(), nivel, 10)
      cantidades = Enum.frequencies_by(resultado, fn pregunta -> pregunta.nivel end)

      for {nivel_pregunta, esperadas} <- Trivia.Nivel.reparto(nivel, 10) do
        assert Map.get(cantidades, nivel_pregunta, 0) == esperadas
      end
    end
  end

  test "ejemplos del enunciado: 5 en básico y 10 en avanzado" do
    assert {:ok, cinco} = BancoPreguntas.sortear(preguntas_atom(), :basico, 5)
    assert Enum.map(cinco, & &1.nivel) == [:basico, :basico, :basico, :basico, :intermedio]

    assert {:ok, diez} = BancoPreguntas.sortear(preguntas_atom(), :avanzado, 10)
    assert Enum.frequencies_by(diez, & &1.nivel) == %{intermedio: 3, avanzado: 7}
  end

  test "informa cuando no hay suficientes preguntas de algún nivel" do
    insuficientes = Enum.take(preguntas_string(), 5)

    assert BancoPreguntas.sortear(insuficientes, :avanzado, 10) ==
             {:error, :preguntas_insuficientes}
  end

  test "rechaza parámetros inválidos" do
    assert BancoPreguntas.sortear([], :experto, 5) ==
             {:error, :preguntas_insuficientes}

    assert BancoPreguntas.sortear([], :basico, 0) ==
             {:error, :preguntas_insuficientes}
  end
end
