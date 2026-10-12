defmodule SharedExpensesWeb.MoneyComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias SharedExpensesWeb.CoreComponents

  test "whole amounts omit cents, including zero, negative amounts and thousands" do
    for {cents, expected} <- [
          {0, "€0"},
          {10000, "€100"},
          {385_000, "€3,850"},
          {-123_400, "−€1,234"}
        ] do
      assert render_money(amount_cents: cents) |> LazyHTML.text() |> String.trim() == expected
    end
  end

  test "nonzero cents retain both decimal digits" do
    for {cents, expected} <- [
          {1, "€0.01"},
          {10005, "€100.05"},
          {10050, "€100.50"},
          {-123_456, "−€1,234.56"}
        ] do
      assert render_money(amount_cents: cents) |> LazyHTML.text() |> String.trim() == expected
    end
  end

  test "currency, custom classes and global attributes can be passed by callers" do
    node =
      render_money(
        amount_cents: 10000,
        currency: "USD",
        class: ["font-semibold", "text-indigo-600"],
        id: "example-price",
        title: "Price"
      )
      |> LazyHTML.filter("#example-price.tabular-nums.font-semibold.text-indigo-600")

    assert LazyHTML.text(node) |> String.trim() == "100 USD"
    assert LazyHTML.attribute(node, "title") == ["Price"]

    assert render_money(amount_cents: 10005, currency: "RUB") |> LazyHTML.text() |> String.trim() ==
             "100.05 RUB"
  end

  defp render_money(assigns) do
    render_component(&CoreComponents.money/1, assigns) |> LazyHTML.from_fragment()
  end
end
