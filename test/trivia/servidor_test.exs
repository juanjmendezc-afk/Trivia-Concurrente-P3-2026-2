defmodule Trivia.ServidorTest do
  # No es async: los procesos del servidor tienen nombres globales
  use ExUnit.Case, async: false

  alias Trivia.GestorJugadores
  alias Trivia.Persistencia
  alias Trivia.Servidor

  # Cada prueba usa una carpeta temporal propia (nunca toca data/)
  @moduletag :tmp_dir

  setup %{tmp_dir: carpeta} do
    {:ok, _pid} = Servidor.iniciar(carpeta)
    on_exit(fn -> Servidor.detener() end)
    :ok
  end

  # Un cliente falso: reenvía a la prueba todo lo que le llegue del servidor
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

  # Envía la petición al servidor y espera la respuesta que le llega al cliente
  defp peticion(cliente, mensaje) do
    send(:servidor, mensaje)

    receive do
      {:recibido, ^cliente, {:respuesta, respuesta}} -> respuesta
    after
      1000 -> :sin_respuesta
    end
  end

  defp connect(cliente, usuario, clave) do
    peticion(cliente, {:connect, cliente, usuario, clave})
  end

  defp disconnect(cliente), do: peticion(cliente, {:disconnect, cliente})

  # Espera (consultando por mensajes, sin dormir) a que el servidor cierre la sesión
  defp esperar_cierre(cliente, limite \\ System.monotonic_time(:millisecond) + 2000) do
    case GestorJugadores.usuario_de(cliente) do
      {:error, :sin_sesion} ->
        :ok

      {:ok, _usuario} ->
        if System.monotonic_time(:millisecond) < limite do
          esperar_cierre(cliente, limite)
        else
          :tiempo_agotado
        end
    end
  end

  describe "arranque" do
    test "no se puede iniciar dos veces", %{tmp_dir: carpeta} do
      assert {:error, :ya_iniciado} = Servidor.iniciar(carpeta)
    end

    test "con users.json dañado no arranca y no deja nada en marcha", %{tmp_dir: carpeta} do
      :ok = Servidor.detener()
      File.write!(Path.join(carpeta, "users.json"), "esto no es json")

      assert {:error, :json_invalido} = Servidor.iniciar(carpeta)
      assert Process.whereis(:servidor) == nil
      assert Process.whereis(:gestor_jugadores) == nil
      assert Process.whereis(:persistencia) == nil
    end
  end

  describe "connect y disconnect" do
    test "un usuario nuevo se registra y queda guardado en users.json" do
      cliente = cliente_falso()

      assert {:ok, %{usuario: "pedro", registrado: true}} = connect(cliente, "pedro", "1234")
      assert {:ok, %{"pedro" => "1234"}} = Persistencia.cargar_usuarios()
    end

    test "un usuario registrado vuelve a entrar con su clave" do
      cliente = cliente_falso()

      assert {:ok, %{registrado: true}} = connect(cliente, "pedro", "1234")
      assert {:ok, %{usuario: "pedro"}} = disconnect(cliente)
      assert {:ok, %{usuario: "pedro", registrado: false}} = connect(cliente, "pedro", "1234")
    end

    test "clave incorrecta" do
      cliente = cliente_falso()

      assert {:ok, _} = connect(cliente, "pedro", "1234")
      assert {:ok, _} = disconnect(cliente)
      assert {:error, :clave_incorrecta} = connect(cliente, "pedro", "9999")
    end

    test "usuario reservado y parámetros inválidos" do
      cliente = cliente_falso()

      assert {:error, :usuario_reservado} = connect(cliente, "bot_1", "1234")
      assert {:error, :parametros_invalidos} = connect(cliente, "dos palabras", "1234")
      assert {:error, :parametros_invalidos} = connect(cliente, "pedro", "")
    end

    test "un usuario no puede tener dos sesiones a la vez" do
      uno = cliente_falso()
      otro = cliente_falso()

      assert {:ok, _} = connect(uno, "pedro", "1234")
      assert {:error, :ya_conectado} = connect(otro, "pedro", "1234")
      assert {:error, :sesion_abierta} = connect(uno, "carlos", "abcd")
    end

    test "disconnect sin sesión" do
      cliente = cliente_falso()

      assert {:error, :sin_sesion} = disconnect(cliente)
    end

    test "los usuarios persisten al reiniciar el servidor", %{tmp_dir: carpeta} do
      antes = cliente_falso()
      assert {:ok, %{registrado: true}} = connect(antes, "pedro", "1234")

      :ok = Servidor.detener()
      {:ok, _pid} = Servidor.iniciar(carpeta)

      despues = cliente_falso()
      assert {:error, :clave_incorrecta} = connect(despues, "pedro", "9999")
      assert {:ok, %{usuario: "pedro", registrado: false}} = connect(despues, "pedro", "1234")
    end
  end

  describe "otras peticiones" do
    test "sin sesión toda petición se rechaza" do
      cliente = cliente_falso()
      receptor = cliente_falso()

      assert {:error, :sin_sesion} = peticion(cliente, {:score, cliente})
      assert {:error, :sin_sesion} = peticion(cliente, {:answer, cliente, "A"})

      assert {:error, :sin_sesion} =
               peticion(cliente, {:create_game, cliente, "historia", 5, 15, receptor})
    end

    test "con sesión, una petición sin implementar se rechaza como comando inválido" do
      cliente = cliente_falso()

      assert {:ok, _} = connect(cliente, "pedro", "1234")
      assert {:error, :comando_invalido} = peticion(cliente, {:score, cliente})
    end

    test "un mensaje desconocido no tumba el servidor" do
      cliente = cliente_falso()
      servidor = Process.whereis(:servidor)

      send(:servidor, :basura)
      send(:servidor, {:cosa, "sin pid"})

      assert {:ok, _} = connect(cliente, "pedro", "1234")
      assert Process.whereis(:servidor) == servidor
    end
  end

  describe "vigilar clientes" do
    test "si el cliente desaparece, se cierra su sesión" do
      cliente = cliente_falso()
      otro = cliente_falso()

      assert {:ok, _} = connect(cliente, "pedro", "1234")
      assert {:error, :ya_conectado} = connect(otro, "pedro", "1234")

      Process.exit(cliente, :kill)

      assert :ok = esperar_cierre(cliente)
      assert {:ok, %{usuario: "pedro", registrado: false}} = connect(otro, "pedro", "1234")
    end

    test "se sigue vigilando al cliente que se desconecta y vuelve a conectar" do
      cliente = cliente_falso()
      otro = cliente_falso()

      assert {:ok, _} = connect(cliente, "pedro", "1234")
      assert {:ok, _} = disconnect(cliente)
      assert {:ok, _} = connect(cliente, "pedro", "1234")

      Process.exit(cliente, :kill)

      assert :ok = esperar_cierre(cliente)
      assert {:ok, _} = connect(otro, "pedro", "1234")
    end
  end
end
