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
end
