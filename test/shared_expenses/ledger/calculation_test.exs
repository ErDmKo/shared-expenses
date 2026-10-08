defmodule SharedExpenses.Ledger.CalculationTest do
  use ExUnit.Case, async: true

  alias SharedExpenses.Ledger.Calculation

  setup do
    members = [
      %{id: 1, name: "Alice", household_id: 1},
      %{id: 2, name: "Bob", household_id: 1},
      %{id: 3, name: "Cara", household_id: 1},
      %{id: 4, name: "Dan", household_id: 2}
    ]

    households = [%{id: 1, name: "Family A"}, %{id: 2, name: "Family B"}]
    %{members: members, households: households}
  end

  test "unequal families split historical per-person expenses 50/50", context do
    expense = %{
      payer_id: 1,
      amount_cents: 12000,
      shares: Enum.map(context.members, &%{member_id: &1.id, amount_cents: 3000})
    }

    balances = Calculation.balances(context.members, [expense], [])
    pooled = Calculation.pooled_balances(context.members, balances, context.households)

    assert Enum.sum(Map.values(balances)) == 0

    assert pooled == [
             %{key: {:household, 1}, name: "Family A", amount_cents: 6000},
             %{key: {:household, 2}, name: "Family B", amount_cents: -6000}
           ]

    assert Calculation.suggestions(pooled) == [
             %{from: "Family B", to: "Family A", amount_cents: 6000}
           ]
  end

  test "selecting one or several people from a family counts that family once", context do
    for ids <- [[2, 4], [1, 2, 3, 4]] do
      expense = %{
        payer_id: 1,
        amount_cents: 12000,
        shares: Enum.map(ids, &%{member_id: &1})
      }

      balances = Calculation.balances(context.members, [expense], [])
      pooled = Calculation.pooled_balances(context.members, balances, context.households)
      assert Enum.map(pooled, & &1.amount_cents) == [6000, -6000]
    end
  end

  test "an excluded payer's family receives no expense share", context do
    expense = %{payer_id: 4, amount_cents: 12000, shares: [%{member_id: 1}, %{member_id: 2}]}
    balances = Calculation.balances(context.members, [expense], [])
    pooled = Calculation.pooled_balances(context.members, balances, context.households)

    assert Enum.map(pooled, & &1.amount_cents) == [-12000, 12000]

    assert Calculation.suggestions(pooled) == [
             %{from: "Family A", to: "Family B", amount_cents: 12000}
           ]
  end

  test "internal family expenses and repayments create no settlement debts", context do
    expense = %{payer_id: 1, amount_cents: 1500, shares: [%{member_id: 2}, %{member_id: 3}]}
    repayment = %{from_member_id: 2, to_member_id: 1, amount_cents: 500}
    balances = Calculation.balances(context.members, [expense], [repayment])
    pooled = Calculation.pooled_balances(context.members, balances, context.households)

    assert Enum.all?(pooled, &(&1.amount_cents == 0))
    assert Calculation.suggestions(pooled) == []
  end

  test "payments between families reduce the debt and internal payments do not change it",
       context do
    expense = %{
      payer_id: 1,
      amount_cents: 12000,
      shares: Enum.map(context.members, &%{member_id: &1.id})
    }

    repayments = [
      %{from_member_id: 4, to_member_id: 2, amount_cents: 2000},
      %{from_member_id: 2, to_member_id: 1, amount_cents: 1300}
    ]

    balances = Calculation.balances(context.members, [expense], repayments)
    pooled = Calculation.pooled_balances(context.members, balances, context.households)
    assert Enum.map(pooled, & &1.amount_cents) == [4000, -4000]

    assert Calculation.suggestions(pooled) == [
             %{from: "Family B", to: "Family A", amount_cents: 4000}
           ]
  end

  test "families and individuals each receive one share with deterministic cent rounding",
       context do
    solo = %{id: 5, name: "Eve", household_id: nil}
    participants = context.members ++ [solo]
    shares = Calculation.expense_shares(101, participants)

    assert Map.new(shares) == %{1 => 12, 2 => 11, 3 => 11, 4 => 34, 5 => 33}
    assert Enum.sum(Enum.map(shares, &elem(&1, 1))) == 101
    assert Calculation.expense_shares(101, Enum.reverse(participants)) == shares

    for amount <- [0, 1, 2, 5, 7, 1001] do
      shares = Calculation.expense_shares(amount, participants)
      by_member = Map.new(shares)
      group_amounts = [by_member[1] + by_member[2] + by_member[3], by_member[4], by_member[5]]

      assert Enum.sum(group_amounts) == amount
      assert Enum.all?(shares, fn {_id, share} -> share >= 0 end)
      assert Enum.max(group_amounts) - Enum.min(group_amounts) <= 1
    end
  end
end
