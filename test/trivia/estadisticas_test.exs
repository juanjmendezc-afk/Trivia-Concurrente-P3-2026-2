defmodule Trivia.EstadisticasTest do
  use ExUnit.Case, async: true

  alias Trivia.Estadisticas

  # Historial de ejemplo: no se abre ningún archivo, las líneas son strings
  defp historial do
    [
      "2026-11-10 20:15:03|P-1001|historia|basico|pedro|pedro:45,bot_1:30,bot_2:-5",
      "2026-11-10 20:31:47|P-1002|ciencia|basico|bot_2|carlos:20,bot_1:15,bot_2:38",
      "2026-11-11 09:00:00|P-1003|historia|basico|bot_1|pedro:15,bot_1:40,bot_2:10",
      "2026-11-11 09:30:00|P-1004|ciencia|basico|pedro,bot_1|pedro:30,bot_1:30,bot_2:0",
      "2026-11-11 10:00:00|P-1005|historia|basico|bot_1|carlos:-8,bot_1:25,bot_2:5"
    ]
  end

  # Una sola partida de `usuario` en historia con ese puntaje
  defp linea_con(usuario, puntaje) do
    "2026-11-12 08:00:00|P-2001|historia|basico|bot_1|#{usuario}:#{puntaje},bot_1:500,bot_2:0"
  end

  describe "parsear_linea/1" do
    test "convierte una línea válida en un mapa" do
      linea = "2026-11-12 20:15:03|P-1001|historia|basico|pedro|pedro:45,bot_1:30,bot_2:-5"

      assert Estadisticas.parsear_linea(linea) ==
               {:ok,
                %{
                  fecha: "2026-11-12 20:15:03",
                  id: "P-1001",
                  tema: "historia",
                  nivel: :basico,
                  ganadores: ["pedro"],
                  puntajes: [{"pedro", 45}, {"bot_1", 30}, {"bot_2", -5}]
                }}
    end

    test "con empate deja a todos los ganadores" do
      linea = "2026-11-12 20:15:03|P-1001|ciencia|avanzado|pedro,bot_1|pedro:30,bot_1:30"

      assert {:ok, %{ganadores: ["pedro", "bot_1"], nivel: :avanzado}} =
               Estadisticas.parsear_linea(linea)
    end

    test "quita el \\r, el salto de línea y los espacios del final" do
      base = "2026-11-12 20:15:03|P-1001|historia|intermedio|pedro|pedro:45,bot_1:30"
      {:ok, esperado} = Estadisticas.parsear_linea(base)

      assert Estadisticas.parsear_linea(base <> "\r") == {:ok, esperado}
      assert Estadisticas.parsear_linea(base <> "\r\n") == {:ok, esperado}
      assert Estadisticas.parsear_linea(base <> "   ") == {:ok, esperado}
      assert esperado.puntajes == [{"pedro", 45}, {"bot_1", 30}]
    end

    test "rechaza líneas con campos de más o de menos" do
      assert Estadisticas.parsear_linea("") == {:error, :linea_invalida}
      assert Estadisticas.parsear_linea("hola") == {:error, :linea_invalida}

      # Sin fecha (5 campos)
      assert Estadisticas.parsear_linea("P-1001|historia|basico|pedro|pedro:45") ==
               {:error, :linea_invalida}

      # Con un campo de más
      assert Estadisticas.parsear_linea(
               "2026-11-12 20:15:03|P-1001|historia|basico|pedro|pedro:45|extra"
             ) == {:error, :linea_invalida}
    end

    test "rechaza puntajes que no son enteros o que vienen mal formados" do
      inicio = "2026-11-12 20:15:03|P-1001|historia|basico|pedro|"

      assert Estadisticas.parsear_linea(inicio <> "pedro:abc") == {:error, :linea_invalida}
      assert Estadisticas.parsear_linea(inicio <> "pedro:4.5") == {:error, :linea_invalida}
      assert Estadisticas.parsear_linea(inicio <> "pedro:45x") == {:error, :linea_invalida}
      assert Estadisticas.parsear_linea(inicio <> "pedro") == {:error, :linea_invalida}
      assert Estadisticas.parsear_linea(inicio <> ":45") == {:error, :linea_invalida}
      assert Estadisticas.parsear_linea(inicio <> "pedro:45,") == {:error, :linea_invalida}
      assert Estadisticas.parsear_linea(inicio <> "") == {:error, :linea_invalida}
    end

    test "rechaza nivel desconocido y campos vacíos" do
      assert Estadisticas.parsear_linea(
               "2026-11-12 20:15:03|P-1001|historia|experto|pedro|pedro:45"
             ) == {:error, :linea_invalida}

      assert Estadisticas.parsear_linea("2026-11-12 20:15:03|P-1001||basico|pedro|pedro:45") ==
               {:error, :linea_invalida}

      assert Estadisticas.parsear_linea("2026-11-12 20:15:03|P-1001|historia|basico||pedro:45") ==
               {:error, :linea_invalida}
    end

    test "rechaza lo que no es un string" do
      assert Estadisticas.parsear_linea(nil) == {:error, :linea_invalida}
      assert Estadisticas.parsear_linea(123) == {:error, :linea_invalida}
    end
  end

  describe "puntaje_en_tema/3" do
    test "suma las partidas del usuario en ese tema" do
      assert Estadisticas.puntaje_en_tema(historial(), "pedro", "historia") == 60
      assert Estadisticas.puntaje_en_tema(historial(), "pedro", "ciencia") == 30
      assert Estadisticas.puntaje_en_tema(historial(), "carlos", "ciencia") == 20
    end

    test "tema nunca jugado, usuario desconocido o historial vacío dan 0" do
      assert Estadisticas.puntaje_en_tema(historial(), "pedro", "geografia") == 0
      assert Estadisticas.puntaje_en_tema(historial(), "maria", "historia") == 0
      assert Estadisticas.puntaje_en_tema([], "pedro", "historia") == 0
    end

    test "el puntaje puede ser negativo" do
      assert Estadisticas.puntaje_en_tema(historial(), "carlos", "historia") == -8
    end

    test "los bots se ignoran" do
      assert Estadisticas.puntaje_en_tema(historial(), "bot_1", "historia") == 0
    end

    test "las líneas inválidas se saltan" do
      lineas = ["basura", "" | historial()] ++ ["a|b|c|d|e|pedro:x"]

      assert Estadisticas.puntaje_en_tema(lineas, "pedro", "historia") == 60
    end

    test "acepta las líneas con \\r al final" do
      lineas = Enum.map(historial(), &(&1 <> "\r"))

      assert Estadisticas.puntaje_en_tema(lineas, "pedro", "historia") == 60
    end
  end

  describe "resumen/2" do
    test "puntaje total, partidas y puntaje y nivel por tema" do
      assert Estadisticas.resumen(historial(), "pedro") ==
               {:ok,
                %{
                  puntaje: 90,
                  partidas: 3,
                  por_tema: %{
                    "historia" => %{puntaje: 60, nivel: :intermedio},
                    "ciencia" => %{puntaje: 30, nivel: :basico}
                  }
                }}
    end

    test "con puntaje negativo el nivel es básico" do
      assert Estadisticas.resumen(historial(), "carlos") ==
               {:ok,
                %{
                  puntaje: 12,
                  partidas: 2,
                  por_tema: %{
                    "ciencia" => %{puntaje: 20, nivel: :basico},
                    "historia" => %{puntaje: -8, nivel: :basico}
                  }
                }}
    end

    test "usuario que nunca jugó" do
      assert Estadisticas.resumen(historial(), "maria") ==
               {:ok, %{puntaje: 0, partidas: 0, por_tema: %{}}}

      assert Estadisticas.resumen([], "pedro") ==
               {:ok, %{puntaje: 0, partidas: 0, por_tema: %{}}}
    end

    test "los bots se ignoran" do
      assert Estadisticas.resumen(historial(), "bot_1") ==
               {:ok, %{puntaje: 0, partidas: 0, por_tema: %{}}}
    end

    test "una partida con 0 puntos (por ejemplo, abandonada) también cuenta" do
      lineas = [
        "2026-11-12 18:24:04|P-1003|geografia|basico|pedro,bot_1,bot_2|pedro:0,bot_1:0,bot_2:0"
        | historial()
      ]

      {:ok, resumen} = Estadisticas.resumen(lineas, "pedro")

      assert resumen.partidas == 4
      assert resumen.puntaje == 90
      assert resumen.por_tema["geografia"] == %{puntaje: 0, nivel: :basico}
    end

    test "las líneas inválidas se saltan" do
      lineas = ["basura" | historial()] ++ ["2026|P-1|historia|basico|pedro|pedro:mil"]

      assert Estadisticas.resumen(lineas, "pedro") == Estadisticas.resumen(historial(), "pedro")
    end

    test "umbrales de nivel: 59, 60, 179 y 180" do
      assert nivel_con(59) == :basico
      assert nivel_con(60) == :intermedio
      assert nivel_con(179) == :intermedio
      assert nivel_con(180) == :avanzado
      assert nivel_con(-20) == :basico
    end

    test "el nivel sale de la suma de varias partidas del tema" do
      lineas = [linea_con("ana", 100), linea_con("ana", 90), linea_con("ana", -10)]

      {:ok, resumen} = Estadisticas.resumen(lineas, "ana")

      assert resumen.partidas == 3
      assert resumen.por_tema == %{"historia" => %{puntaje: 180, nivel: :avanzado}}
    end
  end

  describe "ranking/2" do
    test "global: suma todos los temas, de mayor a menor y sin bots" do
      assert Estadisticas.ranking(historial(), nil) == [{"pedro", 90}, {"carlos", 12}]
    end

    test "por tema: solo las partidas de ese tema" do
      assert Estadisticas.ranking(historial(), "historia") == [{"pedro", 60}, {"carlos", -8}]
      assert Estadisticas.ranking(historial(), "ciencia") == [{"pedro", 30}, {"carlos", 20}]
    end

    test "tema nunca jugado o historial vacío dan lista vacía" do
      assert Estadisticas.ranking(historial(), "geografia") == []
      assert Estadisticas.ranking([], nil) == []
    end

    test "en empate ordena alfabéticamente" do
      lineas = [
        linea_con("zoe", 50),
        linea_con("ana", 50),
        linea_con("luis", 70),
        linea_con("beto", 50)
      ]

      assert Estadisticas.ranking(lineas, nil) ==
               [{"luis", 70}, {"ana", 50}, {"beto", 50}, {"zoe", 50}]
    end

    test "un historial solo de bots da lista vacía" do
      lineas = ["2026-11-12 08:00:00|P-1|historia|basico|bot_1|bot_1:50,bot_2:10"]

      assert Estadisticas.ranking(lineas, nil) == []
    end

    test "las líneas inválidas se saltan" do
      lineas = ["", "x|y", "2026|P-9|historia|basico|pedro|pedro:1000,"] ++ historial()

      assert Estadisticas.ranking(lineas, nil) == [{"pedro", 90}, {"carlos", 12}]
      assert Estadisticas.ranking(lineas, "historia") == [{"pedro", 60}, {"carlos", -8}]
    end
  end

  # Nivel en historia de un usuario con una sola partida de ese puntaje
  defp nivel_con(puntaje) do
    {:ok, resumen} = Estadisticas.resumen([linea_con("ana", puntaje)], "ana")
    resumen.por_tema["historia"].nivel
  end
end
