defmodule Trivia.PuntajeTest do
  use ExUnit.Case, async: true

  alias Trivia.Puntaje

  describe "puntos por nivel" do
    test "correcta sin tiempo restante: +10, +15 y +20" do
      assert Puntaje.calcular(:basico, :correcta, 0, 15) == 10
      assert Puntaje.calcular(:intermedio, :correcta, 0, 15) == 15
      assert Puntaje.calcular(:avanzado, :correcta, 0, 15) == 20
    end

    test "incorrecta: -5, -8 y -10" do
      assert Puntaje.calcular(:basico, :incorrecta, 0, 15) == -5
      assert Puntaje.calcular(:intermedio, :incorrecta, 0, 15) == -8
      assert Puntaje.calcular(:avanzado, :incorrecta, 0, 15) == -10
    end

    test "sin responder: 0 en los tres niveles" do
      assert Puntaje.calcular(:basico, :sin_responder, 0, 15) == 0
      assert Puntaje.calcular(:intermedio, :sin_responder, 0, 15) == 0
      assert Puntaje.calcular(:avanzado, :sin_responder, 0, 15) == 0
    end
  end

  describe "bonificación por rapidez" do
    # Responder en el segundo s deja (tiempo - s) segundos restantes
    test "con 15 s: segundo 1 → +4, 4 → +3, 9 → +2, 14 → +0" do
      assert Puntaje.calcular(:basico, :correcta, 14_000, 15) == 10 + 4
      assert Puntaje.calcular(:basico, :correcta, 11_000, 15) == 10 + 3
      assert Puntaje.calcular(:basico, :correcta, 6_000, 15) == 10 + 2
      assert Puntaje.calcular(:basico, :correcta, 1_000, 15) == 10 + 0
    end

    test "con 10 s: segundo 1 → +4, 4 → +3, 5 → +2, 9 → +0" do
      assert Puntaje.calcular(:intermedio, :correcta, 9_000, 10) == 15 + 4
      assert Puntaje.calcular(:intermedio, :correcta, 6_000, 10) == 15 + 3
      assert Puntaje.calcular(:intermedio, :correcta, 5_000, 10) == 15 + 2
      assert Puntaje.calcular(:intermedio, :correcta, 1_000, 10) == 15 + 0
    end

    test "se suma al puntaje de cada nivel" do
      assert Puntaje.calcular(:basico, :correcta, 14_000, 15) == 14
      assert Puntaje.calcular(:intermedio, :correcta, 14_000, 15) == 19
      assert Puntaje.calcular(:avanzado, :correcta, 14_000, 15) == 24
    end

    test "respuesta instantánea da el máximo, +5" do
      assert Puntaje.calcular(:basico, :correcta, 15_000, 15) == 15
      assert Puntaje.calcular(:avanzado, :correcta, 10_000, 10) == 25
    end

    test "los milisegundos restantes se limitan a 0..tiempo" do
      assert Puntaje.calcular(:basico, :correcta, -200, 15) == 10
      assert Puntaje.calcular(:basico, :correcta, 99_000, 15) == 15
    end

    test "incorrecta y sin responder no reciben bonificación" do
      assert Puntaje.calcular(:basico, :incorrecta, 14_000, 15) == -5
      assert Puntaje.calcular(:avanzado, :incorrecta, 10_000, 10) == -10
      assert Puntaje.calcular(:intermedio, :sin_responder, 14_000, 15) == 0
    end
  end

  describe "argumentos inválidos" do
    test "devuelve {:error, :argumentos_invalidos}" do
      malos = [
        {:experto, :correcta, 0, 15},
        {:basico, :acertada, 0, 15},
        {:basico, :correcta, 1.5, 15},
        {:basico, :correcta, nil, 15},
        {:basico, :correcta, 0, 0},
        {:basico, :correcta, 0, -3},
        {:basico, :correcta, 0, "15"},
        {"basico", :correcta, 0, 15}
      ]

      for {nivel, resultado, ms, tiempo} <- malos do
        assert {:error, :argumentos_invalidos} = Puntaje.calcular(nivel, resultado, ms, tiempo),
               "debió rechazar: #{inspect({nivel, resultado, ms, tiempo})}"
      end
    end
  end
end
