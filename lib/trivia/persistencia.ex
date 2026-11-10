defmodule Trivia.Persistencia do
  alias Trivia.Util

  @nombre :persistencia
  @espera 5000
  @carpeta_datos Path.expand(Path.join([__DIR__, "..", "..", "data"]))

  @archivo_usuarios "users.json"
  @archivo_preguntas "questions.json"
  @archivo_resultados "results.log"

  @niveles ["basico", "intermedio", "avanzado"]
  @letras ["A", "B", "C", "D"]

  # Segundos que se restan a UTC para obtener la hora de Colombia
  @desfase_colombia 5 * 3600

  # ---------- Funciones cliente: solo envían mensajes ----------

  # Carpeta donde viven los archivos por defecto
  def carpeta_datos, do: @carpeta_datos

  # Arranca el proceso y lo registra con nombre
  def iniciar(carpeta \\ @carpeta_datos) do
    case Process.whereis(@nombre) do
      nil ->
        File.mkdir_p!(carpeta)
        pid = spawn(fn -> loop(carpeta) end)
        Process.register(pid, @nombre)
        {:ok, pid}

      _pid ->
        {:error, :ya_iniciado}
    end
  end

  def cargar_usuarios, do: pedir(:cargar_usuarios, nil)

  def guardar_usuarios(usuarios), do: pedir(:guardar_usuarios, usuarios)

  def cargar_preguntas, do: pedir(:cargar_preguntas, nil)

  def leer_historial, do: pedir(:leer_historial, nil)

  def detener, do: pedir(:detener, nil)

  # Sin respuesta: la Partida no espera confirmación
  def guardar_resultado(linea) when is_binary(linea) do
    case Process.whereis(@nombre) do
      nil ->
        {:error, :persistencia_no_disponible}

      pid ->
        send(pid, {:guardar_resultado, linea})
        :ok
    end
  end

  def guardar_resultado(_linea), do: {:error, :linea_invalida}

  # Envía la petición y espera la respuesta con la misma etiqueta
  defp pedir(accion, datos) do
    case Process.whereis(@nombre) do
      nil ->
        {:error, :persistencia_no_disponible}

      pid ->
        send(pid, {accion, self(), datos})

        receive do
          {^accion, respuesta} -> respuesta
        after
          @espera -> {:error, :persistencia_no_disponible}
        end
    end
  end

  # ---------- Bucle del proceso: único que toca los archivos ----------

  defp loop(carpeta) do
    receive do
      {:cargar_usuarios, remitente, _datos} ->
        send(remitente, {:cargar_usuarios, leer_usuarios(carpeta)})
        loop(carpeta)

      {:guardar_usuarios, remitente, usuarios} ->
        send(remitente, {:guardar_usuarios, escribir_usuarios(carpeta, usuarios)})
        loop(carpeta)

      {:cargar_preguntas, remitente, _datos} ->
        send(remitente, {:cargar_preguntas, leer_preguntas(carpeta)})
        loop(carpeta)

      {:leer_historial, remitente, _datos} ->
        send(remitente, {:leer_historial, leer_lineas(carpeta)})
        loop(carpeta)

      {:guardar_resultado, linea} when is_binary(linea) ->
        anotar_resultado(carpeta, linea)
        loop(carpeta)

      {:detener, remitente, _datos} ->
        # Libera el nombre antes de responder para poder reiniciar sin esperas
        Process.unregister(@nombre)
        send(remitente, {:detener, :ok})

      _otro ->
        # Mensaje desconocido: se descarta para no acumularlo
        loop(carpeta)
    end
  end

  # ---------- Usuarios ----------

  defp leer_usuarios(carpeta) do
    with {:ok, datos} <- leer_json(ruta(carpeta, @archivo_usuarios)) do
      usuarios_desde_json(datos)
    end
  end

  defp escribir_usuarios(carpeta, usuarios) when is_map(usuarios) do
    if Enum.all?(usuarios, &usuario_guardable?/1) do
      lista =
        usuarios
        |> Enum.sort()
        |> Enum.map(fn {usuario, clave} -> %{"usuario" => usuario, "clave" => clave} end)

      with {:ok, json} <- Jason.encode(lista, pretty: true) do
        File.write(ruta(carpeta, @archivo_usuarios), json)
      else
        {:error, _} -> {:error, :json_invalido}
      end
    else
      {:error, :formato_invalido}
    end
  end

  defp escribir_usuarios(_carpeta, _usuarios), do: {:error, :formato_invalido}

  # Solo se guarda lo que después se puede volver a leer
  defp usuario_guardable?({usuario, clave}), do: is_binary(usuario) and is_binary(clave)

  # users.json es una lista de objetos; se convierte en un mapa usuario => clave
  defp usuarios_desde_json(datos) when is_list(datos) do
    if Enum.all?(datos, &usuario_valido?/1) do
      {:ok, Map.new(datos, fn %{"usuario" => usuario, "clave" => clave} -> {usuario, clave} end)}
    else
      {:error, :formato_invalido}
    end
  end

  defp usuarios_desde_json(_datos), do: {:error, :formato_invalido}

  defp usuario_valido?(%{"usuario" => usuario, "clave" => clave}) do
    is_binary(usuario) and is_binary(clave)
  end

  defp usuario_valido?(_otro), do: false

  # ---------- Preguntas ----------

  defp leer_preguntas(carpeta) do
    with {:ok, datos} <- leer_json(ruta(carpeta, @archivo_preguntas)) do
      preguntas_desde_json(datos)
    end
  end

  # Si una sola pregunta es inválida se rechaza el archivo completo
  defp preguntas_desde_json(datos) when is_list(datos) do
    if Enum.all?(datos, &pregunta_valida?/1) do
      {:ok, Enum.map(datos, &pregunta_desde_json/1)}
    else
      {:error, :formato_invalido}
    end
  end

  defp preguntas_desde_json(_datos), do: {:error, :formato_invalido}

  defp pregunta_valida?(%{
         "tema" => tema,
         "nivel" => nivel,
         "enunciado" => enunciado,
         "opciones" => opciones,
         "respuesta" => respuesta
       }) do
    tema_valido?(tema) and nivel in @niveles and is_binary(enunciado) and
      opciones_validas?(opciones) and respuesta in @letras
  end

  defp pregunta_valida?(_otra), do: false

  # Tema en minúscula y sin espacios
  defp tema_valido?(tema) when is_binary(tema) do
    tema != "" and tema == String.downcase(tema) and not String.contains?(tema, " ")
  end

  defp tema_valido?(_otro), do: false

  # Debe tener exactamente las opciones A, B, C y D, todas con texto
  defp opciones_validas?(opciones) when is_map(opciones) do
    Enum.sort(Map.keys(opciones)) == @letras and Enum.all?(Map.values(opciones), &is_binary/1)
  end

  defp opciones_validas?(_otro), do: false

  # Mapa con claves string del JSON -> mapa con claves átomo
  defp pregunta_desde_json(pregunta) do
    %{
      tema: pregunta["tema"],
      nivel: nivel_desde_texto(pregunta["nivel"]),
      enunciado: pregunta["enunciado"],
      opciones: pregunta["opciones"],
      respuesta: pregunta["respuesta"]
    }
  end

  defp nivel_desde_texto("basico"), do: :basico
  defp nivel_desde_texto("intermedio"), do: :intermedio
  defp nivel_desde_texto("avanzado"), do: :avanzado

  # ---------- Historial ----------

  # File.stream! no tiene variante con tupla: se verifica antes que exista
  defp leer_lineas(carpeta) do
    ruta = ruta(carpeta, @archivo_resultados)

    if File.exists?(ruta) do
      lineas =
        ruta
        |> File.stream!()
        |> Stream.map(&String.trim/1)
        |> Stream.reject(&(&1 == ""))
        |> Enum.to_list()

      {:ok, lineas}
    else
      {:ok, []}
    end
  end

  # Agrega "fecha|linea" al final del archivo; si falla, informa y sigue
  defp anotar_resultado(carpeta, linea) do
    registro = "#{fecha_hora()}|#{String.trim(linea)}\n"

    case File.write(ruta(carpeta, @archivo_resultados), registro, [:append]) do
      :ok -> :ok
      {:error, motivo} -> Util.imprimir("No se pudo guardar el resultado: #{motivo}", :error)
    end
  end

  # Fecha y hora de Colombia, por ejemplo 2026-11-12 20:15:03
  defp fecha_hora do
    DateTime.utc_now()
    |> DateTime.add(-@desfase_colombia, :second)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  # ---------- Utilidades de archivos ----------

  defp ruta(carpeta, archivo), do: Path.join(carpeta, archivo)

  # Si el archivo no existe (primer arranque) se entrega una lista vacía
  defp leer_json(ruta) do
    case File.read(ruta) do
      {:ok, contenido} -> decodificar(contenido)
      {:error, :enoent} -> {:ok, []}
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp decodificar(contenido) do
    case Jason.decode(contenido) do
      {:ok, datos} -> {:ok, datos}
      {:error, _} -> {:error, :json_invalido}
    end
  end
end
