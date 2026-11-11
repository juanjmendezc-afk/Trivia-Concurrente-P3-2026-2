defmodule Trivia.ReceptorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Trivia.Receptor

  describe "formatear/1" do
    test "un aviso se muestra tal cual" do
      assert {:ok, "Tu partida falló"} = Receptor.formatear({:aviso, "Tu partida falló"})
    end

    test "pregunta, cierre de ronda y fin de partida llevan su rótulo" do
      assert {:ok, "[Pregunta] " <> _} = Receptor.formatear({:pregunta, %{numero: 1}})
      assert {:ok, "[Cierre de ronda] " <> _} = Receptor.formatear({:cierre_ronda, %{}})
      assert {:ok, "[Fin de la partida] " <> _} = Receptor.formatear({:fin_partida, %{}})
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
