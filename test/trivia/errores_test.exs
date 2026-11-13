defmodule Trivia.ErroresTest do
  # Los errores del enunciado de punta a punta: línea escrita -> Cliente -> Servidor -> gestor/partida.
  # Pedro es la propia prueba (usa Cliente.procesar/2); Carlos es un cliente falso que hace de testigo.
  # No es async: los procesos del servidor tienen nombres globales.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Trivia.AyudaPruebas
  alias Trivia.Cliente
  alias Trivia.Servidor

  # Cada prueba usa una carpeta temporal propia (nunca toca data/)
  @moduletag :tmp_dir

  setup %{tmp_dir: carpeta} do
    AyudaPruebas.escribir_preguntas(carpeta)
    {:ok, _pid} = Servidor.iniciar(carpeta)
    on_exit(fn -> Servidor.detener() end)

    # El nodo de las pruebas no tiene nombre: el envío a {:servidor, node()} es local
    %{estado: %{nodo: node(), receptor: self(), usuario: nil}}
  end

  # ---------- Pedro: escribe líneas como en la consola ----------

  # Ejecuta una línea y devuelve {estado nuevo, lo impreso normal, lo impreso como error}
  defp ejecutar(linea, estado) do
    {{resultado, salida}, errores} =
      with_io(:stderr, fn ->
        with_io(fn -> Cliente.procesar(linea, estado) end)
      end)

    assert {:continuar, nuevo_estado} = resultado
    {nuevo_estado, salida, errores}
  end

  # La línea debe terminar en ese error: se imprime su mensaje por la salida de errores,
  # nada por la salida normal, y el estado del cliente no cambia
  defp falla_con(linea, estado, atomo) do
    {nuevo_estado, salida, errores} = ejecutar(linea, estado)

    assert errores == Cliente.mensaje_de_error(atomo) <> "\n", "línea: #{linea}"
    assert salida == "", "línea: #{linea}"
    assert nuevo_estado == estado, "línea: #{linea}"
    estado
  end

  # La línea debe salir bien: nada por la salida de errores
  defp funciona(linea, estado) do
    {nuevo_estado, salida, errores} = ejecutar(linea, estado)

    assert errores == "", "línea: #{linea}"
    assert salida != "", "línea: #{linea}"
    nuevo_estado
  end

  # ---------- Carlos: cliente falso que reenvía a la prueba lo que recibe ----------

  defp cliente_falso do
    prueba = self()
    spawn(fn -> reenviar(prueba) end)
  end

  defp reenviar(prueba) do
    receive do
      mensaje ->
        send(prueba, {:recibido, self(), mensaje})
        reenviar(prueba)
    end
  end

  defp peticion(cliente, mensaje) do
    send(:servidor, mensaje)

    receive do
      {:recibido, ^cliente, {:respuesta, respuesta}} -> respuesta
    after
      1000 -> :sin_respuesta
    end
  end

  # Carlos con sesión y una partida en espera con 2 bots
  defp carlos_con_partida do
    carlos = cliente_falso()
    {:ok, _} = peticion(carlos, {:connect, carlos, "carlos", "abcd"})
    {:ok, %{id: id}} = peticion(carlos, {:create_game, carlos, "ciencia", 3, 20, carlos})
    {:ok, "bot_1"} = peticion(carlos, {:add_bot, carlos, :facil})
    {:ok, "bot_2"} = peticion(carlos, {:add_bot, carlos, :dificil})
    {carlos, id}
  end

  # Criterio 12: tras los errores de Pedro, Carlos conserva su sesión y su partida
  # (mismo id, mismos 2 bots) y puede jugarla
  defp carlos_sigue_intacto(carlos, id) do
    assert {:ok, %{partidas: 0}} = peticion(carlos, {:score, carlos})

    assert {:error, :ya_en_partida} =
             peticion(carlos, {:create_game, carlos, "historia", 5, 15, carlos})

    assert {:ok, %{id: ^id, total: 3}} = peticion(carlos, {:start_game, carlos})
    assert_receive {:recibido, ^carlos, {:pregunta, %{numero: 1, total: 3, tiempo: 20}}}, 1000
    assert {:ok, :recibida} = peticion(carlos, {:answer, carlos, "A"})
  end

  defp servidor_sigue_vivo do
    for nombre <- [:servidor, :gestor_jugadores, :gestor_partidas, :persistencia] do
      pid = Process.whereis(nombre)
      assert is_pid(pid) and Process.alive?(pid), "#{nombre} no está en marcha"
    end
  end

  # ---------- Los tres huecos de la auditoría ----------

  describe "error 3: usuario ya conectado en otro cliente" do
    test "se informa, el otro cliente conserva su sesión y el servidor sigue", %{estado: estado} do
      {carlos, id} = carlos_con_partida()

      estado = falla_con("connect carlos abcd", estado, :ya_conectado)
      assert estado.usuario == nil

      # El servidor atiende la siguiente petición del mismo cliente
      estado = funciona("connect pedro 1234", estado)
      assert estado.usuario == "pedro"

      servidor_sigue_vivo()
      carlos_sigue_intacto(carlos, id)
    end
  end

  describe "error 5: servidor no disponible" do
    test "se informa tras la espera y el cliente sigue; al volver el servidor, funciona", %{
      estado: estado,
      tmp_dir: carpeta
    } do
      estado = funciona("connect pedro 1234", estado)
      :ok = Servidor.detener()

      # Espera real del cliente (5 s): nadie responde
      estado = falla_con("score", estado, :servidor_no_disponible)
      assert estado.usuario == "pedro"

      # El cliente no se cayó: cuando el servidor vuelve, atiende de nuevo (y pedro persiste)
      {:ok, _pid} = Servidor.iniciar(carpeta)
      # El servidor nuevo no conoce la sesión vieja: el cliente lo nota y olvida el usuario
      {estado, _salida, errores} = ejecutar("score", estado)
      assert errores == Cliente.mensaje_de_error(:sin_sesion) <> "\n"
      assert estado.usuario == nil

      {estado, salida, errores} = ejecutar("connect pedro 1234", estado)
      assert salida =~ "Bienvenido de nuevo, pedro"
      assert errores == ""
      assert estado.usuario == "pedro"
    end
  end

  describe "error 9: add_bot con la partida ya iniciada" do
    test "se informa, la partida sigue en curso y la de otro jugador no se toca", %{
      estado: estado
    } do
      {carlos, id} = carlos_con_partida()

      estado = funciona("connect pedro 1234", estado)
      estado = funciona("create_game tema=historia preguntas=5 tiempo=15", estado)
      estado = funciona("add_bot facil", estado)
      estado = funciona("add_bot dificil", estado)
      estado = funciona("start_game", estado)
      assert_receive {:pregunta, %{numero: 1, total: 5}}, 1000

      # Hay cupo (3 de 4 jugadores): el rechazo es porque ya empezó
      estado = falla_con("add_bot facil", estado, :partida_iniciada)

      # La partida de Pedro sigue en curso y acepta su respuesta
      funciona("answer a", estado)

      servidor_sigue_vivo()
      carlos_sigue_intacto(carlos, id)
    end
  end

  # ---------- Recorrido ----------

  describe "recorrido de errores" do
    # El error 5 no entra aquí: necesita el servidor detenido y tiene su propia prueba
    test "Pedro provoca los errores uno tras otro y nada se cae (criterio 12)", %{
      estado: estado
    } do
      {carlos, id} = carlos_con_partida()

      # 1: comando sin sesión
      estado = falla_con("score", estado, :sin_sesion)
      estado = falla_con("create_game tema=historia preguntas=5 tiempo=15", estado, :sin_sesion)

      # 2: clave incorrecta (pedro ya registrado)
      estado = funciona("connect pedro 1234", estado)
      estado = funciona("disconnect", estado)
      estado = falla_con("connect pedro 9999", estado, :clave_incorrecta)

      # 3: usuario ya conectado en otro cliente
      estado = falla_con("connect carlos abcd", estado, :ya_conectado)

      # 4: prefijo bot_ reservado
      estado = falla_con("connect bot_1 1234", estado, :usuario_reservado)

      estado = funciona("connect pedro 1234", estado)

      # 8: add_bot y start_game sin estar en partida
      estado = falla_con("add_bot facil", estado, :sin_partida)
      estado = falla_con("start_game", estado, :sin_partida)

      # 7: tema inexistente o sin preguntas suficientes
      estado =
        falla_con("create_game tema=cocina preguntas=5 tiempo=15", estado, :tema_inexistente)

      estado =
        falla_con(
          "create_game tema=escaso preguntas=5 tiempo=15",
          estado,
          :preguntas_insuficientes
        )

      # 6: create_game estando ya en partida
      estado = funciona("create_game tema=historia preguntas=5 tiempo=15", estado)
      estado = falla_con("create_game tema=ciencia preguntas=5 tiempo=15", estado, :ya_en_partida)

      # 10: start_game con menos de 2 bots
      estado = funciona("add_bot facil", estado)
      estado = falla_con("start_game", estado, :bots_insuficientes)

      # 11: respuesta fuera de ronda
      estado = falla_con("answer a", estado, :sin_ronda_abierta)

      # 9: partida llena
      estado = funciona("add_bot dificil", estado)
      estado = funciona("add_bot facil", estado)
      estado = falla_con("add_bot facil", estado, :partida_llena)

      estado = funciona("start_game", estado)
      assert_receive {:pregunta, %{numero: 1, total: 5}}, 1000

      # 9: partida iniciada
      estado = falla_con("add_bot facil", estado, :partida_iniciada)
      estado = falla_con("start_game", estado, :partida_iniciada)

      # 11: letra inválida (no consume la respuesta) y, de paso, respuesta repetida
      estado = falla_con("answer z", estado, :letra_invalida)
      estado = funciona("answer a", estado)
      estado = falla_con("answer b", estado, :respuesta_repetida)

      # Después de todo, el servidor atiende una petición normal de Pedro...
      {estado, salida, errores} = ejecutar("score", estado)
      assert salida =~ "Puntaje total: 0 en 0 partidas"
      assert errores == ""
      assert estado.usuario == "pedro"

      # ...y Carlos no se enteró de nada
      servidor_sigue_vivo()
      carlos_sigue_intacto(carlos, id)
    end
  end

  # ---------- Ventana del gestor (progreso.md, T5–T8) ----------

  describe "la partida termina mientras el gestor la está llamando" do
    # Una partida falsa ocupa el lugar de la de Pedro: recibe la llamada del gestor,
    # avisa que terminó y sale con :normal SIN responder. Es lo que hace la Partida real
    # cuando el answer llega justo al vencer el tiempo de la última ronda.
    defp partida_que_termina_sin_responder(id) do
      prueba = self()

      spawn(fn ->
        receive do
          {:"$gen_call", _desde, peticion} ->
            send(:gestor_partidas, {:partida_terminada, id})
            send(prueba, {:llamada_recibida, peticion})
        end
      end)
    end

    test "el gestor sigue vivo, el jugador recibe un error y los demás no se afectan" do
      {carlos, id_carlos} = carlos_con_partida()

      pedro = cliente_falso()
      {:ok, _} = peticion(pedro, {:connect, pedro, "pedro", "1234"})
      {:ok, %{id: id}} = peticion(pedro, {:create_game, pedro, "historia", 5, 15, pedro})

      # El gestor toma la partida falsa como si fuera un reinicio (y avisa al creador)
      falsa = partida_que_termina_sin_responder(id)
      send(:gestor_partidas, {:partida_iniciada, id, falsa})
      assert_receive {:recibido, ^pedro, {:aviso, _texto}}, 1000

      gestor = Process.whereis(:gestor_partidas)
      referencia = Process.monitor(gestor)

      assert {:error, :sin_partida} = peticion(pedro, {:answer, pedro, "A"})
      assert_received {:llamada_recibida, {:responder, "pedro", "A"}}

      # El gestor no cayó y atiende la siguiente petición de Pedro
      refute_received {:DOWN, ^referencia, :process, ^gestor, _razon}
      servidor_sigue_vivo()

      assert {:ok, %{id: _otro_id}} =
               peticion(pedro, {:create_game, pedro, "ciencia", 3, 20, pedro})

      carlos_sigue_intacto(carlos, id_carlos)
    end
  end
end
