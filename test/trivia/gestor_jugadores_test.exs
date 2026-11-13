defmodule Trivia.GestorJugadoresTest do
  # Solo lógica pura: no se levanta ningún proceso del gestor
  use ExUnit.Case, async: true

  alias Trivia.GestorJugadores

  # Dos clientes distintos (basta con que los PID sean diferentes)
  defp clientes do
    {self(), spawn(fn -> :ok end)}
  end

  defp estado_con_pedro do
    GestorJugadores.nuevo(%{"pedro" => "1234"})
  end

  describe "abrir_sesion" do
    test "un usuario nuevo se registra y queda con sesión" do
      {cliente, _otro} = clientes()
      estado = GestorJugadores.nuevo(%{})

      assert {:ok, nuevo, :nuevo} = GestorJugadores.abrir_sesion(estado, cliente, "pedro", "1234")
      assert nuevo.usuarios == %{"pedro" => "1234"}
      assert nuevo.sesiones == %{cliente => "pedro"}
    end

    test "un usuario existente con su clave abre sesión sin cambiar los usuarios" do
      {cliente, _otro} = clientes()
      estado = estado_con_pedro()

      assert {:ok, nuevo, :existente} =
               GestorJugadores.abrir_sesion(estado, cliente, "pedro", "1234")

      assert nuevo.usuarios == estado.usuarios
      assert nuevo.sesiones == %{cliente => "pedro"}
    end

    test "clave incorrecta" do
      {cliente, _otro} = clientes()

      assert {:error, :clave_incorrecta} =
               GestorJugadores.abrir_sesion(estado_con_pedro(), cliente, "pedro", "9999")
    end

    test "el prefijo bot_ está reservado" do
      {cliente, _otro} = clientes()
      estado = GestorJugadores.nuevo(%{})

      assert {:error, :usuario_reservado} =
               GestorJugadores.abrir_sesion(estado, cliente, "bot_1", "1234")

      assert {:error, :usuario_reservado} =
               GestorJugadores.abrir_sesion(estado, cliente, "bot_", "1234")
    end

    test "un usuario ya conectado en otro cliente se rechaza, aunque la clave sea mala" do
      {cliente, otro} = clientes()

      {:ok, estado, _} =
        GestorJugadores.abrir_sesion(estado_con_pedro(), cliente, "pedro", "1234")

      assert {:error, :ya_conectado} = GestorJugadores.abrir_sesion(estado, otro, "pedro", "1234")
      assert {:error, :ya_conectado} = GestorJugadores.abrir_sesion(estado, otro, "pedro", "mala")
    end

    test "un cliente con sesión abierta no puede abrir otra" do
      {cliente, _otro} = clientes()

      {:ok, estado, _} =
        GestorJugadores.abrir_sesion(estado_con_pedro(), cliente, "pedro", "1234")

      assert {:error, :sesion_abierta} =
               GestorJugadores.abrir_sesion(estado, cliente, "pedro", "1234")

      assert {:error, :sesion_abierta} =
               GestorJugadores.abrir_sesion(estado, cliente, "carlos", "abcd")
    end

    test "rechaza usuario o clave inválidos" do
      {cliente, _otro} = clientes()
      estado = GestorJugadores.nuevo(%{})

      invalidos = [
        {"", "1234"},
        {"dos palabras", "1234"},
        {" pedro", "1234"},
        {"pedro\n", "1234"},
        {"pedro", ""},
        {nil, "1234"},
        {"pedro", nil},
        {123, "1234"}
      ]

      for {usuario, clave} <- invalidos do
        assert {:error, :parametros_invalidos} =
                 GestorJugadores.abrir_sesion(estado, cliente, usuario, clave)
      end
    end

    test "rechaza usuarios con los separadores del historial (| , :)" do
      {cliente, _otro} = clientes()
      estado = GestorJugadores.nuevo(%{})

      for usuario <- ["a|b", "a,b", "a:b", "ana:99,bot_9", "|", ",", ":"] do
        assert {:error, :parametros_invalidos} =
                 GestorJugadores.abrir_sesion(estado, cliente, usuario, "1234")
      end
    end

    test "otros símbolos en el usuario se aceptan, y la clave no tiene restricción de símbolos" do
      {cliente, _otro} = clientes()
      estado = GestorJugadores.nuevo(%{})

      for usuario <- ["ana.perez", "ana-1", "ana_2", "ñandú"] do
        assert {:ok, _estado, :nuevo} =
                 GestorJugadores.abrir_sesion(estado, cliente, usuario, "1234")
      end

      assert {:ok, _estado, :nuevo} =
               GestorJugadores.abrir_sesion(estado, cliente, "pedro", "a|b,c:d")
    end
  end

  describe "cerrar_sesion" do
    test "devuelve el usuario y deja de tener sesión, pero sigue registrado" do
      {cliente, _otro} = clientes()

      {:ok, estado, _} =
        GestorJugadores.abrir_sesion(estado_con_pedro(), cliente, "pedro", "1234")

      assert {:ok, cerrado, "pedro"} = GestorJugadores.cerrar_sesion(estado, cliente)
      assert cerrado.sesiones == %{}
      assert cerrado.usuarios == %{"pedro" => "1234"}
    end

    test "un cliente sin sesión no puede cerrar nada" do
      {cliente, _otro} = clientes()

      assert {:error, :sin_sesion} = GestorJugadores.cerrar_sesion(estado_con_pedro(), cliente)
    end

    test "tras cerrar la sesión el usuario puede entrar desde otro cliente" do
      {cliente, otro} = clientes()

      {:ok, estado, _} =
        GestorJugadores.abrir_sesion(estado_con_pedro(), cliente, "pedro", "1234")

      {:ok, estado, _} = GestorJugadores.cerrar_sesion(estado, cliente)

      assert {:ok, _estado, :existente} =
               GestorJugadores.abrir_sesion(estado, otro, "pedro", "1234")
    end
  end

  describe "buscar_usuario" do
    test "encuentra al usuario de un cliente con sesión" do
      {cliente, otro} = clientes()

      {:ok, estado, _} =
        GestorJugadores.abrir_sesion(estado_con_pedro(), cliente, "pedro", "1234")

      assert {:ok, "pedro"} = GestorJugadores.buscar_usuario(estado, cliente)
      assert {:error, :sin_sesion} = GestorJugadores.buscar_usuario(estado, otro)
    end
  end

  describe "score_desde y ranking_desde" do
    # Historial de ejemplo: dos temas, dos jugadores y bots
    defp historial do
      [
        "2026-11-10 20:15:03|P-1001|historia|basico|pedro|pedro:45,bot_1:30,bot_2:-5",
        "2026-11-10 20:31:47|P-1002|ciencia|basico|bot_2|carlos:20,bot_1:15,bot_2:38",
        "2026-11-11 09:00:00|P-1003|historia|basico|bot_1|pedro:15,bot_1:40,bot_2:10",
        "linea dañada",
        "2026-11-11 10:00:00|P-1004|historia|basico|bot_1|carlos:-8,bot_1:25,bot_2:5"
      ]
    end

    test "score de un jugador con partidas en dos temas" do
      assert GestorJugadores.score_desde(historial(), "pedro") ==
               {:ok,
                %{
                  puntaje: 60,
                  partidas: 2,
                  por_tema: %{"historia" => %{puntaje: 60, nivel: :intermedio}}
                }}

      assert {:ok, %{puntaje: 12, partidas: 2, por_tema: por_tema}} =
               GestorJugadores.score_desde(historial(), "carlos")

      assert por_tema == %{
               "ciencia" => %{puntaje: 20, nivel: :basico},
               "historia" => %{puntaje: -8, nivel: :basico}
             }
    end

    test "score de un jugador nuevo queda en cero" do
      assert GestorJugadores.score_desde(historial(), "maria") ==
               {:ok, %{puntaje: 0, partidas: 0, por_tema: %{}}}

      assert GestorJugadores.score_desde([], "pedro") ==
               {:ok, %{puntaje: 0, partidas: 0, por_tema: %{}}}
    end

    test "ranking global y por tema, sin bots" do
      assert GestorJugadores.ranking_desde(historial(), nil) ==
               {:ok, [{"pedro", 60}, {"carlos", 12}]}

      assert GestorJugadores.ranking_desde(historial(), "historia") ==
               {:ok, [{"pedro", 60}, {"carlos", -8}]}

      assert GestorJugadores.ranking_desde(historial(), "ciencia") == {:ok, [{"carlos", 20}]}
    end

    test "el tema se pasa a minúscula antes de consultar" do
      assert GestorJugadores.ranking_desde(historial(), "HISTORIA") ==
               GestorJugadores.ranking_desde(historial(), "historia")

      assert GestorJugadores.ranking_desde(historial(), "Ciencia") == {:ok, [{"carlos", 20}]}
    end

    test "tema que nadie ha jugado o historial vacío dan lista vacía" do
      assert GestorJugadores.ranking_desde(historial(), "geografia") == {:ok, []}
      assert GestorJugadores.ranking_desde([], nil) == {:ok, []}
    end

    test "un tema que no es texto se rechaza sin romper nada" do
      assert GestorJugadores.ranking_desde(historial(), 123) == {:error, :parametros_invalidos}

      assert GestorJugadores.ranking_desde(historial(), :historia) ==
               {:error, :parametros_invalidos}
    end
  end
end
