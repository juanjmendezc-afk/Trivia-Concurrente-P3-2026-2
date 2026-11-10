defmodule Trivia.Util do
  # Imprime por la salida estándar
  def imprimir(mensaje), do: IO.puts(mensaje)

  # Imprime por la salida de errores
  def imprimir(mensaje, :error), do: IO.puts(:stderr, mensaje)

  # Lee texto del teclado sin espacios al inicio ni al final
  def leer(mensaje, :string) do
    mensaje
    |> IO.gets()
    |> String.trim()
  end

  # Lee un entero; repite la pregunta hasta que sea válido
  def leer(mensaje, :integer) do
    texto = leer(mensaje, :string)

    case Integer.parse(texto) do
      {numero, ""} ->
        numero

      _ ->
        imprimir("Error, debe ingresar un número entero", :error)
        leer(mensaje, :integer)
    end
  end

  # Lee un decimal; repite la pregunta hasta que sea válido
  def leer(mensaje, :float) do
    texto = leer(mensaje, :string)

    case Float.parse(texto) do
      {numero, ""} ->
        numero

      _ ->
        imprimir("Error, debe ingresar un número decimal", :error)
        leer(mensaje, :float)
    end
  end
end
