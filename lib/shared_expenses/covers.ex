defmodule SharedExpenses.Covers do
  @moduledoc "Local persistent storage for event cover images."

  def save(path) do
    with {:ok, header} <- read_header(path),
         {:ok, extension} <- extension(header),
         :ok <- File.mkdir_p(directory()) do
      filename = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false) <> extension

      case File.cp(path, Path.join(directory(), filename)) do
        :ok -> {:ok, filename}
        error -> error
      end
    end
  end

  def path(filename) when is_binary(filename) do
    if Regex.match?(~r/\A[A-Za-z0-9_-]{24}\.(png|jpg|webp)\z/, filename),
      do: {:ok, Path.join(directory(), filename)},
      else: :error
  end

  def content_type(filename) do
    case Path.extname(filename) do
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".webp" -> "image/webp"
    end
  end

  defp directory do
    Application.get_env(:shared_expenses, :cover_dir, Path.expand("data/covers"))
  end

  defp read_header(path) do
    with {:ok, file} <- File.open(path, [:read, :binary]) do
      result = IO.binread(file, 12)
      File.close(file)
      if is_binary(result), do: {:ok, result}, else: :error
    end
  end

  defp extension(<<0xFF, 0xD8, 0xFF, _::binary>>), do: {:ok, ".jpg"}
  defp extension(<<137, 80, 78, 71, 13, 10, 26, 10, _::binary>>), do: {:ok, ".png"}
  defp extension(<<"RIFF", _::binary-size(4), "WEBP">>), do: {:ok, ".webp"}
  defp extension(_), do: {:error, :unsupported_image}
end
