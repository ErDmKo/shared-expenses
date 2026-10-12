defmodule SharedExpenses.MoneyTest do
  use ExUnit.Case, async: true

  alias SharedExpenses.Money

  test "euro amounts use the currency symbol, grouping and exactly two decimals" do
    for {cents, formatted} <- [
          {0, "€0.00"},
          {1, "€0.01"},
          {125, "€1.25"},
          {99999, "€999.99"},
          {100_000, "€1,000.00"},
          {385_000, "€3,850.00"},
          {123_456_789, "€1,234,567.89"},
          {-125, "−€1.25"},
          {-123_456, "−€1,234.56"}
        ] do
      assert Money.format(cents, "EUR") == formatted
      assert Money.format(cents) == formatted
    end
  end

  test "other currencies retain their currency code" do
    assert Money.format(1801, "USD") == "18.01 USD"
    assert Money.format(-125, "USD") == "−1.25 USD"
    assert Money.format(123_456, "RUB") == "1234.56 RUB"
  end

  test "zero cents can be omitted without losing nonzero cents" do
    assert Money.format(10000, "EUR", trim_zero_cents: true) == "€100"
    assert Money.format(0, "EUR", trim_zero_cents: true) == "€0"
    assert Money.format(-123_400, "EUR", trim_zero_cents: true) == "−€1,234"
    assert Money.format(10005, "EUR", trim_zero_cents: true) == "€100.05"
    assert Money.format(10050, "EUR", trim_zero_cents: true) == "€100.50"
    assert Money.format(10000, "USD", trim_zero_cents: true) == "100 USD"
    assert Money.format(10005, "USD", trim_zero_cents: true) == "100.05 USD"
  end
end
