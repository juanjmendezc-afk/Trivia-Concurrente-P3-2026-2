defmodule Trivia.ClienteTest do
  # No es async: el servidor de las pruebas tiene nombres globales
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Trivia.Cliente
  alias Trivia.GestorJugadores
  alias Trivia.Servidor

  # Ejecuta una línea y devuelve {resultado, lo impreso normal, lo impreso como error}
  defp ejecutar(linea, estado) do
    {{resultado, salida}, errores} =
      with_io(:stderr, fn ->
        with_io(fn -> Cliente.procesar(linea, estado) end)
      end)

    {resultado, salida, errores}
  end

  describe "interpretar/3" do
    # El pid del cliente es el de la prueba; el del receptor es otro cualquiera
    setup do
      %{cliente: self(), receptor: spawn(fn -> :ok end)}
    end

    test "connect y disconnect", %{cliente: cliente, receptor: receptor} do
      assert {:ok, {:connect, ^cliente, "pedro", "1234"}} =
               Cliente.interpretar("connect pedro 1234", cliente, receptor)

      assert {:ok, {:disconnect, ^cliente}} =
               Cliente.interpretar("disconnect", cliente, receptor)
    end

    test "ignora espacios de más entre las palabras", %{cliente: cliente, receptor: receptor} do
      assert {:ok, {:connect, ^cliente, "pedro", "1234"}} =
               Cliente.interpretar("  connect    pedro   1234  ", cliente, receptor)
    end

    test "connect con parámetros de más o de menos", %{cliente: cliente, receptor: receptor} do
      assert {:error, :parametros_invalidos} =
               Cliente.interpretar("connect pedro", cliente, receptor)

      assert {:error, :parametros_invalidos} =
               Cliente.interpretar("connect pedro 1234 extra", cliente, receptor)

      assert {:error, :parametros_invalidos} = Cliente.interpretar("connect", cliente, receptor)
    end

    test "create_game lleva el pid del receptor", %{cliente: cliente, receptor: receptor} do
      assert {:ok, {:create_game, ^cliente, "historia", 5, 15, ^receptor}} =
               Cliente.interpretar(
                 "create_game tema=historia preguntas=5 tiempo=15",
                 cliente,
                 receptor
               )
    end

    test "create_game acepta los parámetros en cualquier orden", %{
      cliente: cliente,
      receptor: receptor
    } do
      assert {:ok, {:create_game, ^cliente, "ciencia", 10, 20, ^receptor}} =
               Cliente.interpretar(
                 "create_game tiempo=20 tema=ciencia preguntas=10",
                 cliente,
                 receptor
               )
    end

    test "create_game con parámetros mal escritos", %{cliente: cliente, receptor: receptor} do
      malos = [
        "create_game",
        "create_game tema=historia preguntas=5",
        "create_game tema=historia preguntas=cinco tiempo=15",
        "create_game tema=historia preguntas=5 tiempo=1.5",
        "create_game tema=historia preguntas=5 tiempo=",
        "create_game tema=historia preguntas=5 duracion=15",
        "create_game tema=historia tema=ciencia preguntas=5",
        "create_game historia 5 15",
        "create_game tema=historia preguntas=5 tiempo=15 extra=1"
      ]

      for linea <- malos do
        assert {:error, :parametros_invalidos} = Cliente.interpretar(linea, cliente, receptor),
               "debió rechazar: #{linea}"
      end
    end

    test "add_bot con cada dificultad", %{cliente: cliente, receptor: receptor} do
      assert {:ok, {:add_bot, ^cliente, :facil}} =
               Cliente.interpretar("add_bot facil", cliente, receptor)

      assert {:ok, {:add_bot, ^cliente, :dificil}} =
               Cliente.interpretar("add_bot dificil", cliente, receptor)

      assert {:error, :parametros_invalidos} =
               Cliente.interpretar("add_bot medio", cliente, receptor)

      assert {:error, :parametros_invalidos} = Cliente.interpretar("add_bot", cliente, receptor)
    end

    test "start_game, leave_game y score", %{cliente: cliente, receptor: receptor} do
      assert {:ok, {:start_game, ^cliente}} =
               Cliente.interpretar("start_game", cliente, receptor)

      assert {:ok, {:leave_game, ^cliente}} =
               Cliente.interpretar("leave_game", cliente, receptor)

      assert {:ok, {:score, ^cliente}} = Cliente.interpretar("score", cliente, receptor)
    end

    test "answer envía la letra en mayúscula y sin revisarla", %{
      cliente: cliente,
      receptor: receptor
    } do
      assert {:ok, {:answer, ^cliente, "B"}} =
               Cliente.interpretar("answer b", cliente, receptor)

      # Una letra inválida la rechaza el servidor, no el cliente
      assert {:ok, {:answer, ^cliente, "Z"}} =
               Cliente.interpretar("answer z", cliente, receptor)

      assert {:error, :parametros_invalidos} = Cliente.interpretar("answer", cliente, receptor)

      assert {:error, :parametros_invalidos} =
               Cliente.interpretar("answer A B", cliente, receptor)
    end

    test "ranking global y por tema", %{cliente: cliente, receptor: receptor} do
      assert {:ok, {:ranking, ^cliente, nil}} =
               Cliente.interpretar("ranking", cliente, receptor)

      assert {:ok, {:ranking, ^cliente, "historia"}} =
               Cliente.interpretar("ranking historia", cliente, receptor)

      assert {:error, :parametros_invalidos} =
               Cliente.interpretar("ranking historia ciencia", cliente, receptor)
    end

    test "comando desconocido o línea vacía", %{cliente: cliente, receptor: receptor} do
      assert {:error, :comando_invalido} = Cliente.interpretar("bailar", cliente, receptor)
      assert {:error, :comando_invalido} = Cliente.interpretar("Connect a b", cliente, receptor)
      assert {:error, :comando_invalido} = Cliente.interpretar("", cliente, receptor)
    end
  end

  describe "mensaje_de_error/1" do
    # Los átomos de la sección 6 de la arquitectura, más el propio del cliente
    @atomos [
      :sin_sesion,
      :clave_incorrecta,
      :ya_conectado,
      :usuario_reservado,
      :servidor_no_disponible,
      :ya_en_partida,
      :tema_inexistente,
      :preguntas_insuficientes,
      :sin_partida,
      :partida_llena,
      :partida_iniciada,
      :bots_insuficientes,
      :letra_invalida,
      :sin_ronda_abierta,
      :respuesta_repetida,
      :sesion_abierta,
      :comando_invalido,
      :parametros_invalidos,
      :nodo_sin_nombre
    ]

    test "cada error de la tabla tiene su mensaje propio" do
      for atomo <- @atomos do
        mensaje = Cliente.mensaje_de_error(atomo)

        assert is_binary(mensaje)
        refute mensaje =~ "Error:", "falta el mensaje de #{inspect(atomo)}"
      end
    end

    test "los mensajes son los acordados" do
      assert "Clave incorrecta" = Cliente.mensaje_de_error(:clave_incorrecta)
      assert "Responde A, B, C o D" = Cliente.mensaje_de_error(:letra_invalida)

      assert "No se pudo conectar con el servidor" =
               Cliente.mensaje_de_error(:servidor_no_disponible)
    end

    test "un error desconocido no rompe al cliente" do
      assert "Error: :algo_raro" = Cliente.mensaje_de_error(:algo_raro)
    end
  end

  describe "nodo_servidor/1" do
    test "busca el servidor en el mismo equipo" do
      assert :servidor@mipc = Cliente.nodo_servidor(:pedro@mipc)
      assert :servidor@mipc = Cliente.nodo_servidor(:carlos@mipc)
    end
  end

  describe "iniciar/1" do
    test "un nodo sin nombre no puede hablar con el servidor" do
      # mix test corre en un nodo sin nombre
      salida =
        capture_io(:stderr, fn ->
          assert {:error, :nodo_sin_nombre} = Cliente.iniciar(:servidor@mipc)
        end)

      assert salida =~ "Este nodo no tiene nombre"
    end
  end

  describe "procesar/2 con un servidor en marcha" do
    @describetag :tmp_dir

    setup %{tmp_dir: carpeta} do
      {:ok, _pid} = Servidor.iniciar(carpeta)
      on_exit(fn -> Servidor.detener() end)

      # El nodo de las pruebas no tiene nombre: el envío a {:servidor, node()} es local
      %{estado: %{nodo: node(), receptor: self(), usuario: nil}}
    end

    test "connect de un usuario nuevo abre la sesión", %{estado: estado} do
      {resultado, salida, errores} = ejecutar("connect pedro 1234", estado)

      assert {:continuar, %{usuario: "pedro"}} = resultado
      assert salida =~ "Usuario nuevo registrado. Bienvenido, pedro"
      assert errores == ""
      assert {:ok, "pedro"} = GestorJugadores.usuario_de(self())
    end

    test "connect de un usuario ya registrado", %{estado: estado} do
      {{:continuar, estado}, _, _} = ejecutar("connect pedro 1234", estado)
      {{:continuar, estado}, _, _} = ejecutar("disconnect", estado)
      {resultado, salida, _} = ejecutar("connect pedro 1234", estado)

      assert {:continuar, %{usuario: "pedro"}} = resultado
      assert salida =~ "Bienvenido de nuevo, pedro"
    end

    test "disconnect cierra la sesión", %{estado: estado} do
      {{:continuar, estado}, _, _} = ejecutar("connect pedro 1234", estado)
      {resultado, salida, errores} = ejecutar("disconnect", estado)

      assert {:continuar, %{usuario: nil}} = resultado
      assert salida =~ "Sesión cerrada. Hasta pronto, pedro"
      assert errores == ""
      assert {:error, :sin_sesion} = GestorJugadores.usuario_de(self())
    end

    test "los errores salen por la salida de errores y la sesión no cambia", %{estado: estado} do
      {{:continuar, estado}, _, _} = ejecutar("connect pedro 1234", estado)
      {{:continuar, estado}, _, _} = ejecutar("disconnect", estado)

      {resultado, salida, errores} = ejecutar("connect pedro 9999", estado)

      assert {:continuar, %{usuario: nil}} = resultado
      assert salida == ""
      assert errores =~ "Clave incorrecta"
    end

    test "otros errores del servidor se traducen", %{estado: estado} do
      {_, _, errores} = ejecutar("connect bot_1 1234", estado)
      assert errores =~ "reservados"

      {_, _, errores} = ejecutar("connect dos:puntos 1234", estado)
      assert errores =~ "Revisa los parámetros"

      {{:continuar, estado}, _, _} = ejecutar("connect pedro 1234", estado)
      {_, _, errores} = ejecutar("connect carlos abcd", estado)
      assert errores =~ "Ya tienes una sesión abierta"
    end

    test "sin sesión, los demás comandos piden iniciar sesión", %{estado: estado} do
      {resultado, _, errores} = ejecutar("score", estado)

      assert {:continuar, ^estado} = resultado
      assert errores =~ "Primero inicia sesión"

      {_, _, errores} = ejecutar("create_game tema=historia preguntas=5 tiempo=15", estado)
      assert errores =~ "Primero inicia sesión"
    end

    test "con sesión, un comando que el servidor aún no implementa se rechaza", %{estado: estado} do
      {{:continuar, estado}, _, _} = ejecutar("connect pedro 1234", estado)
      {resultado, _, errores} = ejecutar("score", estado)

      assert {:continuar, %{usuario: "pedro"}} = resultado
      assert errores =~ "Comando no reconocido"
    end

    test "un comando mal escrito no llega al servidor", %{estado: estado} do
      {{:continuar, estado}, _, _} = ejecutar("connect pedro 1234", estado)

      {resultado, salida, errores} = ejecutar("bailar", estado)

      assert {:continuar, ^estado} = resultado
      assert salida == ""
      assert errores =~ "Comando no reconocido"
      refute_received {:respuesta, _}
    end

    test "una línea vacía se ignora", %{estado: estado} do
      {resultado, salida, errores} = ejecutar("   ", estado)

      assert {:continuar, ^estado} = resultado
      assert salida == ""
      assert errores == ""
    end

    test "salir con sesión la cierra en el servidor", %{estado: estado} do
      {{:continuar, estado}, _, _} = ejecutar("connect pedro 1234", estado)
      {resultado, salida, _} = ejecutar("salir", estado)

      assert resultado == :salir
      assert salida =~ "Sesión cerrada"
      assert {:error, :sin_sesion} = GestorJugadores.usuario_de(self())
    end

    test "salir sin sesión no habla con el servidor", %{estado: estado} do
      {resultado, salida, errores} = ejecutar("salir", estado)

      assert resultado == :salir
      assert salida == ""
      assert errores == ""
      refute_received {:respuesta, _}
    end

    test "si el servidor perdió la sesión, el cliente lo nota", %{estado: estado} do
      {{:continuar, estado}, _, _} = ejecutar("connect pedro 1234", estado)
      assert estado.usuario == "pedro"

      # El servidor cierra la sesión por su lado
      assert {:ok, %{usuario: "pedro"}} = GestorJugadores.desconectar(self())

      {resultado, _, errores} = ejecutar("score", estado)

      assert {:continuar, %{usuario: nil}} = resultado
      assert errores =~ "Primero inicia sesión"
    end
  end

  describe "procesar/2 con partidas" do
    @describetag :tmp_dir

    setup %{tmp_dir: carpeta} do
      Trivia.AyudaPruebas.escribir_preguntas(carpeta)
      {:ok, _pid} = Servidor.iniciar(carpeta)
      on_exit(fn -> Servidor.detener() end)

      {resultado, _, _} =
        ejecutar("connect pedro 1234", %{nodo: node(), receptor: self(), usuario: nil})

      assert {:continuar, estado} = resultado
      %{estado: estado}
    end

    test "create_game muestra el id, el tema y el nivel", %{estado: estado} do
      {resultado, salida, errores} =
        ejecutar("create_game tema=historia preguntas=5 tiempo=15", estado)

      assert {:continuar, ^estado} = resultado
      assert salida =~ "Partida P-1001 creada: tema historia, 5 preguntas, 15 s por pregunta"
      assert salida =~ "Tu nivel en historia: básico"
      assert salida =~ "add_bot"
      assert errores == ""
    end

    test "add_bot muestra el nombre y la dificultad del bot", %{estado: estado} do
      {_, _, _} = ejecutar("create_game tema=historia preguntas=5 tiempo=15", estado)

      {_, salida, errores} = ejecutar("add_bot facil", estado)
      assert salida =~ "Bot agregado: bot_1 (facil)"
      assert errores == ""

      {_, salida, _} = ejecutar("add_bot dificil", estado)
      assert salida =~ "Bot agregado: bot_2 (dificil)"
    end

    test "el cuarto bot da partida llena", %{estado: estado} do
      {_, _, _} = ejecutar("create_game tema=historia preguntas=5 tiempo=15", estado)
      for _ <- 1..3, do: ejecutar("add_bot facil", estado)

      {resultado, salida, errores} = ejecutar("add_bot facil", estado)

      assert {:continuar, ^estado} = resultado
      assert salida == ""
      assert errores =~ "La partida está llena"
    end

    test "leave_game cancela la partida y permite crear otra", %{estado: estado} do
      {_, _, _} = ejecutar("create_game tema=historia preguntas=5 tiempo=15", estado)

      {resultado, salida, errores} = ejecutar("leave_game", estado)
      assert {:continuar, ^estado} = resultado
      assert salida =~ "Saliste de la partida P-1001: quedó cancelada"
      assert errores == ""

      {_, salida, _} = ejecutar("create_game tema=ciencia preguntas=10 tiempo=20", estado)
      assert salida =~ "Partida P-1002 creada: tema ciencia, 10 preguntas, 20 s por pregunta"
    end

    test "los errores de partida se traducen", %{estado: estado} do
      {_, _, errores} = ejecutar("add_bot facil", estado)
      assert errores =~ "No estás en ninguna partida"

      {_, _, errores} = ejecutar("leave_game", estado)
      assert errores =~ "No estás en ninguna partida"

      {_, _, errores} = ejecutar("create_game tema=cocina preguntas=5 tiempo=15", estado)
      assert errores =~ "Ese tema no existe"

      {_, _, errores} = ejecutar("create_game tema=escaso preguntas=5 tiempo=15", estado)
      assert errores =~ "No hay preguntas suficientes"

      {_, _, errores} = ejecutar("create_game tema=historia preguntas=11 tiempo=15", estado)
      assert errores =~ "Revisa los parámetros"

      {_, _, errores} = ejecutar("create_game tema=historia preguntas=5 tiempo=0", estado)
      assert errores =~ "Revisa los parámetros"

      {_, _, _} = ejecutar("create_game tema=historia preguntas=5 tiempo=15", estado)
      {_, _, errores} = ejecutar("create_game tema=ciencia preguntas=5 tiempo=15", estado)
      assert errores =~ "Ya estás en una partida"
    end

    test "start_game aún no está implementado (T6)", %{estado: estado} do
      {_, _, errores} = ejecutar("start_game", estado)

      assert errores =~ "Comando no reconocido"
    end
  end

  describe "pedir/3" do
    @describetag :tmp_dir

    setup %{tmp_dir: carpeta} do
      {:ok, _pid} = Servidor.iniciar(carpeta)
      on_exit(fn -> Servidor.detener() end)
      :ok
    end

    test "devuelve la respuesta del servidor" do
      assert {:ok, %{usuario: "pedro", registrado: true}} =
               Cliente.pedir(node(), {:connect, self(), "pedro", "1234"})
    end

    test "sin servidor, responde servidor no disponible tras la espera" do
      :ok = Servidor.detener()

      assert {:error, :servidor_no_disponible} =
               Cliente.pedir(node(), {:connect, self(), "pedro", "1234"}, 50)
    end

    test "una respuesta vieja no se confunde con la nueva" do
      send(self(), {:respuesta, {:error, :vieja}})

      assert {:ok, %{usuario: "pedro"}} =
               Cliente.pedir(node(), {:connect, self(), "pedro", "1234"})
    end
  end
end
