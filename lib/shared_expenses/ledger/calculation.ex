defmodule SharedExpenses.Ledger.Calculation do
  @moduledoc "Splits expenses equally between families and individuals, then suggests transfers."

  alias SharedExpenses.Money

  @doc "Splits equally between participating groups, then allocates each group's share to its selected people."
  def expense_shares(amount_cents, participants) do
    groups = Enum.group_by(participants, &group_key/1)

    amount_cents
    |> Money.split(Map.keys(groups))
    |> Enum.flat_map(fn {key, amount} ->
      ids = Enum.map(Map.fetch!(groups, key), & &1.id)
      Money.split(amount, ids)
    end)
  end

  @doc "Recalculates all expenses using current family assignments, including older per-person splits."
  def balances(members, expenses, repayments) do
    initial = Map.new(members, &{&1.id, 0})
    members_by_id = Map.new(members, &{&1.id, &1})

    balances =
      Enum.reduce(expenses, initial, fn expense, result ->
        result = Map.update!(result, expense.payer_id, &(&1 + expense.amount_cents))
        participants = Enum.map(expense.shares, &Map.fetch!(members_by_id, &1.member_id))

        expense.amount_cents
        |> expense_shares(participants)
        |> Enum.reduce(result, fn {id, amount}, acc ->
          Map.update!(acc, id, &(&1 - amount))
        end)
      end)

    Enum.reduce(repayments, balances, fn repayment, result ->
      result
      |> Map.update!(repayment.from_member_id, &(&1 + repayment.amount_cents))
      |> Map.update!(repayment.to_member_id, &(&1 - repayment.amount_cents))
    end)
  end

  def pooled_balances(members, balances, households) do
    household_names = Map.new(households, &{&1.id, &1.name})

    members
    |> Enum.group_by(&group_key/1)
    |> Enum.map(fn {key, grouped} ->
      name =
        case key do
          {:household, id} -> Map.fetch!(household_names, id)
          {:member, _} -> hd(grouped).name
        end

      %{
        key: key,
        name: name,
        amount_cents: Enum.sum(Enum.map(grouped, &Map.fetch!(balances, &1.id)))
      }
    end)
    |> Enum.sort_by(&{&1.name, &1.key})
  end

  def suggestions(pooled) do
    debtors =
      pooled |> Enum.filter(&(&1.amount_cents < 0)) |> Enum.sort_by(&{&1.amount_cents, &1.name})

    creditors =
      pooled |> Enum.filter(&(&1.amount_cents > 0)) |> Enum.sort_by(&{-&1.amount_cents, &1.name})

    settle(debtors, creditors, [])
  end

  defp group_key(member) do
    if member.household_id, do: {:household, member.household_id}, else: {:member, member.id}
  end

  defp settle([], _, result), do: Enum.reverse(result)
  defp settle(_, [], result), do: Enum.reverse(result)

  defp settle([debtor | debtors], [creditor | creditors], result) do
    amount = min(-debtor.amount_cents, creditor.amount_cents)
    debtor = %{debtor | amount_cents: debtor.amount_cents + amount}
    creditor = %{creditor | amount_cents: creditor.amount_cents - amount}

    settle(
      if(debtor.amount_cents == 0, do: debtors, else: [debtor | debtors]),
      if(creditor.amount_cents == 0, do: creditors, else: [creditor | creditors]),
      [%{from: debtor.name, to: creditor.name, amount_cents: amount} | result]
    )
  end
end
