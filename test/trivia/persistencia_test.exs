defmodule Trivia.PersistenciaTest do
  # No es async: el proceso Persistencia tiene un nombre global
  use ExUnit.Case, async: false

  alias Trivia.Persistencia

  # Cada prueba usa una carpeta temporal propia (nunca toca data/)
  @moduletag :tmp_dir

  # Una pregunta válida en formato JSON; `cambios` permite estropear un campo
  defp pregunta_json(cambios \\ %{}) do
    Map.merge(
      %{
        "tema" => "historia",
        "nivel" => "basico",
        "enunciado" => "¿En qué año llegó Colón a América?",
        "opciones" => %{"A" => "1492", "B" => "1500", "C" => "1810", "D" => "1453"},
        "respuesta" => "A"
      },
      cambios
    )
  end

  defp escribir(carpeta, archivo, contenido) do
    File.write!(Path.join(carpeta, archivo), contenido)
  end

  describe "sin Persistencia iniciada" do
    test "todas las funciones informan que no está disponible" do
      Persistencia.detener()

      assert {:error, :persistencia_no_disponible} = Persistencia.cargar_usuarios()
      assert {:error, :persistencia_no_disponible} = Persistencia.guardar_usuarios(%{})
      assert {:error, :persistencia_no_disponible} = Persistencia.cargar_preguntas()
      assert {:error, :persistencia_no_disponible} = Persistencia.leer_historial()
      assert {:error, :persistencia_no_disponible} = Persistencia.guardar_resultado("x")
    end
  end

  describe "con Persistencia iniciada" do
    setup %{tmp_dir: carpeta} do
      {:ok, _pid} = Persistencia.iniciar(carpeta)
      on_exit(fn -> Persistencia.detener() end)
      :ok
    end

    test "no se puede iniciar dos veces", %{tmp_dir: carpeta} do
      assert {:error, :ya_iniciado} = Persistencia.iniciar(carpeta)
    end

    test "detener libera el nombre y permite iniciar de nuevo", %{tmp_dir: carpeta} do
      assert :ok = Persistencia.detener()
      assert {:ok, _pid} = Persistencia.iniciar(carpeta)
    end

    test "sin users.json los usuarios son un mapa vacío" do
      assert {:ok, %{}} = Persistencia.cargar_usuarios()
    end

    test "los usuarios guardados se cargan igual, también tras reemplazarlos" do
      primero = %{"pedro" => "1234"}
      segundo = %{"pedro" => "1234", "carlos" => "contraseña", "ñandú" => "abcd"}

      assert :ok = Persistencia.guardar_usuarios(primero)
      assert {:ok, ^primero} = Persistencia.cargar_usuarios()

      assert :ok = Persistencia.guardar_usuarios(segundo)
      assert {:ok, ^segundo} = Persistencia.cargar_usuarios()
    end

    test "users.json dañado se informa y no se sobrescribe", %{tmp_dir: carpeta} do
      escribir(carpeta, "users.json", "esto no es json")

      assert {:error, :json_invalido} = Persistencia.cargar_usuarios()
      assert File.read!(Path.join(carpeta, "users.json")) == "esto no es json"
    end

    test "users.json con otra estructura es formato inválido", %{tmp_dir: carpeta} do
      escribir(carpeta, "users.json", ~s([{"usuario": "pedro"}]))
      assert {:error, :formato_invalido} = Persistencia.cargar_usuarios()

      escribir(carpeta, "users.json", ~s({"pedro": "1234"}))
      assert {:error, :formato_invalido} = Persistencia.cargar_usuarios()
    end

    test "no guarda usuarios que luego no se podrían leer" do
      assert {:error, :formato_invalido} = Persistencia.guardar_usuarios(%{"pedro" => 1234})
      assert {:error, :formato_invalido} = Persistencia.guardar_usuarios(["pedro"])
    end

    test "sin questions.json las preguntas son una lista vacía" do
      assert {:ok, []} = Persistencia.cargar_preguntas()
    end

    test "las preguntas se cargan con claves átomo y nivel átomo", %{tmp_dir: carpeta} do
      datos = [pregunta_json(), pregunta_json(%{"tema" => "ciencia", "nivel" => "avanzado"})]
      escribir(carpeta, "questions.json", Jason.encode!(datos))

      assert {:ok, [primera, segunda]} = Persistencia.cargar_preguntas()

      assert primera == %{
               tema: "historia",
               nivel: :basico,
               enunciado: "¿En qué año llegó Colón a América?",
               opciones: %{"A" => "1492", "B" => "1500", "C" => "1810", "D" => "1453"},
               respuesta: "A"
             }

      assert segunda.tema == "ciencia"
      assert segunda.nivel == :avanzado
    end

    test "una pregunta inválida rechaza todo el archivo", %{tmp_dir: carpeta} do
      invalidas = [
        %{"nivel" => "experto"},
        %{"tema" => "Historia"},
        %{"tema" => "mi tema"},
        %{"respuesta" => "E"},
        %{"enunciado" => nil},
        %{"opciones" => %{"A" => "1492", "B" => "1500"}}
      ]

      for cambios <- invalidas do
        datos = [pregunta_json(), pregunta_json(cambios)]
        escribir(carpeta, "questions.json", Jason.encode!(datos))

        assert {:error, :formato_invalido} = Persistencia.cargar_preguntas()
      end
    end

    test "questions.json dañado se informa", %{tmp_dir: carpeta} do
      escribir(carpeta, "questions.json", "[{")
      assert {:error, :json_invalido} = Persistencia.cargar_preguntas()
    end

    test "sin results.log el historial es una lista vacía" do
      assert {:ok, []} = Persistencia.leer_historial()
    end

    test "cada resultado queda en su línea con la fecha al inicio" do
      uno = "P-1001|historia|basico|pedro|pedro:45,bot_1:30,bot_2:-5"
      dos = "P-1002|ciencia|intermedio|bot_2|carlos:20,bot_1:15,bot_2:38"

      assert :ok = Persistencia.guardar_resultado(uno)
      assert :ok = Persistencia.guardar_resultado(dos)

      assert {:ok, [linea_uno, linea_dos]} = Persistencia.leer_historial()

      fecha = ~r/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\|/
      assert linea_uno =~ fecha
      assert linea_dos =~ fecha
      assert String.ends_with?(linea_uno, "|" <> uno)
      assert String.ends_with?(linea_dos, "|" <> dos)
    end

    test "agrega al historial existente y ignora las líneas en blanco", %{tmp_dir: carpeta} do
      anterior = "2026-11-12 20:15:03|P-1001|historia|basico|pedro|pedro:45"
      escribir(carpeta, "results.log", anterior <> "\n\n")

      assert :ok = Persistencia.guardar_resultado("P-1002|ciencia|basico|pedro|pedro:10\n")

      assert {:ok, [^anterior, nueva]} = Persistencia.leer_historial()
      assert String.ends_with?(nueva, "|P-1002|ciencia|basico|pedro|pedro:10")
    end

    test "rechaza un resultado que no es texto" do
      assert {:error, :linea_invalida} = Persistencia.guardar_resultado(nil)
      assert {:error, :linea_invalida} = Persistencia.guardar_resultado(123)
    end
  end
end
