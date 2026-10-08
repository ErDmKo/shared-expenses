defmodule SharedExpenses.Money do
  @moduledoc "Exact two-decimal currency amounts stored as integer minor units."

  def parse(value) when is_binary(value) do
    case Regex.run(~r/\A(\d{1,9})(?:[.,](\d{1,2}))?\z/, String.trim(value)) do
      [_, whole] ->
        positive(String.to_integer(whole) * 100)

      [_, whole, fraction] ->
        positive(
          String.to_integer(whole) * 100 +
            String.to_integer(String.pad_trailing(fraction, 2, "0"))
        )

      _ ->
        {:error, "enter a positive amount with up to two decimal places"}
    end
  end

  def parse(_), do: {:error, "enter a positive amount with up to two decimal places"}

  def format(cents, currency \\ "EUR") when is_integer(cents) do
    sign = if cents < 0, do: "−", else: ""
    cents = abs(cents)

    "#{sign}#{div(cents, 100)}.#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")} #{currency}"
  end

  def split(cents, recipient_ids)
      when is_integer(cents) and cents >= 0 and is_list(recipient_ids) do
    ids = Enum.sort(recipient_ids)
    count = length(ids)

    Enum.with_index(ids, fn id, index ->
      {id, div(cents, count) + if(index < rem(cents, count), do: 1, else: 0)}
    end)
  end

  defp positive(cents) when cents > 0, do: {:ok, cents}
  defp positive(_), do: {:error, "amount must be greater than zero"}
end
