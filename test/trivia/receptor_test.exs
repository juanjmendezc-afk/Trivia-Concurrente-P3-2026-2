defmodule Trivia.ReceptorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Trivia.Receptor

  describe "formatear/1" do
    test "un aviso se muestra tal cual" do
      assert {:ok, "Tu partida falló"} = Receptor.formatear({:aviso, "Tu partida falló"})
    end

    test "una pregunta muestra número, tiempo, enunciado y las opciones de la A a la D" do
      pregunta = %{
        numero: 2,
        total: 5,
        enunciado: "¿En qué año llegó Colón a América?",
        opciones: %{"D" => "1453", "B" => "1500", "A" => "1492", "C" => "1810"},
        tiempo: 15
      }

      assert {:ok, texto} = Receptor.formatear({:pregunta, pregunta})

      assert String.split(texto, "\n") == [
               "",
               "--- Pregunta 2 de 5 (15 s) ---",
               "¿En qué año llegó Colón a América?",
               "  A) 1492",
               "  B) 1500",
               "  C) 1810",
               "  D) 1453",
               "Responde con: answer <letra>"
             ]
    end

    test "el cierre de ronda muestra la respuesta correcta, los puntos y el acumulado" do
      cierre = %{
        numero: 1,
        respuesta_correcta: "B",
        resultados: [
          %{jugador: "pedro", puntos_ronda: 14, acumulado: 14},
          %{jugador: "bot_1", puntos_ronda: -5, acumulado: -5},
          %{jugador: "bot_2", puntos_ronda: 0, acumulado: 10}
        ]
      }

      assert {:ok, texto} = Receptor.formatear({:cierre_ronda, cierre})

      assert String.split(texto, "\n") == [
               "",
               "--- Cierre de la ronda 1 ---",
               "Respuesta correcta: B",
               "  pedro: +14 (acumulado 14)",
               "  bot_1: -5 (acumulado -5)",
               "  bot_2: 0 (acumulado 10)"
             ]
    end

    test "el fin de partida muestra el ranking y el ganador" do
      fin = %{
        id: "P-1001",
        tema: "historia",
        nivel: :basico,
        ranking: [{1, "bot_1", 45}, {2, "pedro", 30}, {3, "bot_2", -5}],
        ganadores: ["bot_1"]
      }

      assert {:ok, texto} = Receptor.formatear({:fin_partida, fin})

      assert String.split(texto, "\n") == [
               "",
               "=== Fin de la partida P-1001 (tema historia, nivel básico) ===",
               "Ranking final:",
               "  1. bot_1: 45",
               "  2. pedro: 30",
               "  3. bot_2: -5",
               "Ganador: bot_1"
             ]
    end

    test "con empate se nombran todos los ganadores" do
      fin = %{
        id: "P-1001",
        tema: "historia",
        nivel: :basico,
        ranking: [{1, "pedro", 45}, {1, "bot_1", 45}, {3, "bot_2", -5}],
        ganadores: ["pedro", "bot_1"]
      }

      assert {:ok, texto} = Receptor.formatear({:fin_partida, fin})
      assert texto =~ "  1. pedro: 45\n  1. bot_1: 45\n  3. bot_2: -5"
      assert texto =~ "Empate, ganadores: pedro, bot_1"
    end

    test "una notificación incompleta se rechaza en vez de romper el receptor" do
      assert {:error, :notificacion_desconocida} = Receptor.formatear({:pregunta, %{numero: 1}})
      assert {:error, :notificacion_desconocida} = Receptor.formatear({:cierre_ronda, %{}})
      assert {:error, :notificacion_desconocida} = Receptor.formatear({:fin_partida, %{}})
    end

    test "lo que no es una notificación se rechaza" do
      assert {:error, :notificacion_desconocida} = Receptor.formatear(:basura)
      assert {:error, :notificacion_desconocida} = Receptor.formatear({:aviso, 123})
      assert {:error, :notificacion_desconocida} = Receptor.formatear({:otra, "cosa"})
    end
  end

  describe "proceso" do
    test "imprime las notificaciones que llegan y descarta el resto" do
      salida =
        capture_io(fn ->
          receptor = Receptor.iniciar()

          send(receptor, {:aviso, "primer aviso"})
          send(receptor, :basura)
          send(receptor, {:aviso, "segundo aviso"})

          :ok = Receptor.detener(receptor)
        end)

      assert salida =~ "primer aviso"
      assert salida =~ "segundo aviso"
      refute salida =~ "basura"
    end

    test "detener termina el proceso" do
      receptor = Receptor.iniciar()
      referencia = Process.monitor(receptor)

      assert :ok = Receptor.detener(receptor)
      assert_receive {:DOWN, ^referencia, :process, ^receptor, :normal}

      # Detener uno que ya no existe no falla ni espera
      assert :ok = Receptor.detener(receptor)
    end
  end
end
