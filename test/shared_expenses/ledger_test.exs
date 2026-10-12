defmodule SharedExpenses.LedgerTest do
  use SharedExpenses.DataCase

  alias SharedExpenses.{Ledger, Money}
  alias SharedExpenses.Ledger.{Calculation, Expense, ExpenseShare, Household, Member, Repayment}

  test "an event requires a name and has an unguessable share link" do
    assert {:error, changeset} = Ledger.create_event(%{"title" => "  ", "currency" => "EUR"})
    assert errors_on(changeset).title

    assert {:ok, event} =
             Ledger.create_event(%{"title" => "  Summer trip  ", "currency" => "EUR"})

    assert event.title == "Summer trip"
    assert byte_size(event.slug) == 32
    assert Ledger.get_event!(event.slug).id == event.id
  end

  test "equal splits conserve cents, and repayments reduce balances" do
    event = event!()
    alice = member!(event, "Alice")
    bob = member!(event, "Bob")
    cara = member!(event, "Cara")

    assert {:ok, expense} =
             Ledger.create_expense(event, %{
               "description" => "Lunch",
               "amount" => "10.01",
               "payer_id" => to_string(alice.id),
               "participant_ids" => Enum.map([alice, bob, cara], &to_string(&1.id))
             })

    shares = Repo.all(from share in ExpenseShare, where: share.expense_id == ^expense.id)
    assert Enum.sum(Enum.map(shares, & &1.amount_cents)) == 1001
    assert Enum.sort(Enum.map(shares, & &1.amount_cents)) == [333, 334, 334]

    snapshot = Ledger.snapshot(event)
    balances = Calculation.balances(snapshot.members, snapshot.expenses, snapshot.repayments)
    assert Enum.sum(Map.values(balances)) == 0
    assert balances[alice.id] > 0

    assert {:ok, _} =
             Ledger.create_repayment(event, %{
               "from_member_id" => to_string(bob.id),
               "to_member_id" => to_string(alice.id),
               "amount" => "1.00"
             })

    updated = Ledger.snapshot(event)
    new_balances = Calculation.balances(updated.members, updated.expenses, updated.repayments)
    assert new_balances[bob.id] == balances[bob.id] + 100
    assert new_balances[alice.id] == balances[alice.id] - 100
    assert Enum.sum(Map.values(new_balances)) == 0
  end

  test "payer can be excluded from an expense and suggestions settle individual balances" do
    event = event!()
    alice = member!(event, "Alice")
    bob = member!(event, "Bob")
    cara = member!(event, "Cara")

    assert {:ok, _} =
             Ledger.create_expense(event, %{
               "description" => "Tickets",
               "amount" => "12",
               "payer_id" => to_string(alice.id),
               "participant_ids" => Enum.map([bob, cara], &to_string(&1.id))
             })

    snapshot = Ledger.snapshot(event)
    balances = Calculation.balances(snapshot.members, snapshot.expenses, snapshot.repayments)
    assert balances == %{alice.id => 1200, bob.id => -600, cara.id => -600}
    pooled = Calculation.pooled_balances(snapshot.members, balances, snapshot.households)
    transfers = Calculation.suggestions(pooled)
    assert length(transfers) == 2
    assert Enum.sum(Enum.map(transfers, & &1.amount_cents)) == 1200
  end

  test "a family and an individual split an expense equally regardless of family size" do
    event = event!()
    {:ok, family} = Ledger.create_household(event, %{"name" => "The Parkers"})
    alice = member!(event, "Alice", family.id)
    bob = member!(event, "Bob", family.id)
    cara = member!(event, "Cara")

    assert {:ok, _} =
             Ledger.create_expense(event, %{
               "description" => "Hotel",
               "amount" => "30",
               "payer_id" => to_string(cara.id),
               "participant_ids" => Enum.map([alice, bob, cara], &to_string(&1.id))
             })

    snapshot = Ledger.snapshot(event)
    balances = Calculation.balances(snapshot.members, snapshot.expenses, snapshot.repayments)
    assert balances[alice.id] == -750
    assert balances[bob.id] == -750
    assert balances[cara.id] == 1500
    shares = Map.new(hd(snapshot.expenses).shares, &{&1.member_id, &1.amount_cents})
    assert shares == %{alice.id => 750, bob.id => 750, cara.id => 1500}
    pooled = Calculation.pooled_balances(snapshot.members, balances, snapshot.households)

    assert Calculation.suggestions(pooled) == [
             %{from: "The Parkers", to: "Cara", amount_cents: 1500}
           ]
  end

  test "invalid or cross-event members cannot create ledger entries" do
    event = event!()
    other = event!()
    alice = member!(event, "Alice")
    outsider = member!(other, "Outsider")

    assert {:error, changeset} =
             Ledger.create_member(event, %{"name" => "Fake", "household_id" => "99999"})

    assert errors_on(changeset).household_id

    assert {:error, changeset} =
             Ledger.create_expense(event, %{
               "description" => "Invalid",
               "amount" => "1.234",
               "payer_id" => to_string(alice.id),
               "participant_ids" => [to_string(outsider.id)]
             })

    assert errors_on(changeset).amount
    assert errors_on(changeset).participant_ids
    assert Repo.aggregate(Expense, :count) == 0

    assert {:error, changeset} =
             Ledger.create_repayment(event, %{
               "amount" => "2",
               "from_member_id" => to_string(alice.id),
               "to_member_id" => to_string(outsider.id)
             })

    assert errors_on(changeset).to_member_id
    assert Repo.aggregate(Repayment, :count) == 0
  end

  test "exact money parsing rejects floats and too many decimals" do
    assert Money.parse("10,50") == {:ok, 1050}
    assert Money.parse("0.01") == {:ok, 1}
    assert {:error, _} = Money.parse("0")
    assert {:error, _} = Money.parse("0.001")
    assert {:error, _} = Money.parse(12.3)
    assert Money.format(-125, "EUR") == "−€1.25"
  end

  test "replaying the same form does not double-charge an expense or payment" do
    event = event!()
    alice = member!(event, "Alice")
    bob = member!(event, "Bob")

    expense = %{
      "description" => "Snacks",
      "amount" => "7.50",
      "payer_id" => to_string(alice.id),
      "participant_ids" => [to_string(alice.id), to_string(bob.id)],
      "submission_key" => String.duplicate("x", 32)
    }

    assert {:ok, first} = Ledger.create_expense(event, expense)
    assert {:ok, second} = Ledger.create_expense(event, expense)
    assert first.id == second.id
    assert Repo.aggregate(Expense, :count) == 1
    assert Repo.aggregate(ExpenseShare, :count) == 2

    payment = %{
      "amount" => "3.75",
      "from_member_id" => to_string(bob.id),
      "to_member_id" => to_string(alice.id),
      "submission_key" => String.duplicate("y", 32)
    }

    assert {:ok, first} = Ledger.create_repayment(event, payment)
    assert {:ok, second} = Ledger.create_repayment(event, payment)
    assert first.id == second.id
    assert Repo.aggregate(Repayment, :count) == 1
  end

  test "deleting an expense cascades its shares and recalculates balances without removing repayments" do
    event = event!()
    {:ok, family} = Ledger.create_household(event, %{"name" => "Our family"})
    alice = member!(event, "Alice", family.id)
    bob = member!(event, "Bob")

    assert {:ok, dinner} =
             Ledger.create_expense(event, %{
               "description" => "Dinner",
               "amount" => "20",
               "payer_id" => to_string(alice.id),
               "participant_ids" => Enum.map([alice, bob], &to_string(&1.id))
             })

    assert {:ok, breakfast} =
             Ledger.create_expense(event, %{
               "description" => "Breakfast",
               "amount" => "6",
               "payer_id" => to_string(bob.id),
               "participant_ids" => Enum.map([alice, bob], &to_string(&1.id))
             })

    assert {:ok, payment} =
             Ledger.create_repayment(event, %{
               "amount" => "10",
               "from_member_id" => to_string(bob.id),
               "to_member_id" => to_string(alice.id)
             })

    assert {:ok, :deleted} = Ledger.delete_expense(event, to_string(dinner.id))
    assert Repo.get(Expense, dinner.id) == nil
    assert Repo.all(from share in ExpenseShare, where: share.expense_id == ^dinner.id) == []
    assert Repo.aggregate(ExpenseShare, :count) == 2
    assert Repo.get(Expense, breakfast.id)
    assert Repo.get(Repayment, payment.id)

    snapshot = Ledger.snapshot(event)
    assert length(snapshot.members) == 2
    assert length(snapshot.households) == 1
    assert Enum.map(snapshot.expenses, & &1.description) == ["Breakfast"]
    balances = Calculation.balances(snapshot.members, snapshot.expenses, snapshot.repayments)
    assert balances == %{alice.id => -1300, bob.id => 1300}
    pooled = Calculation.pooled_balances(snapshot.members, balances, snapshot.households)

    assert Calculation.suggestions(pooled) == [
             %{from: "Our family", to: "Bob", amount_cents: 1300}
           ]

    assert {:ok, :deleted} = Ledger.delete_expense(event, breakfast.id)
    snapshot = Ledger.snapshot(event)
    assert snapshot.expenses == []
    assert Repo.aggregate(ExpenseShare, :count) == 0
    assert length(snapshot.repayments) == 1
  end

  test "deletion never affects another event and repeated or invalid IDs are harmless" do
    event = event!()
    another = event!()
    alice = member!(event, "Alice")
    outsider = member!(another, "Outsider")

    assert {:ok, expense} =
             Ledger.create_expense(another, %{
               "description" => "Taxi",
               "amount" => "7",
               "payer_id" => to_string(outsider.id),
               "participant_ids" => [to_string(outsider.id)]
             })

    for id <- [expense.id, "invalid", "0", String.duplicate("9", 100)] do
      assert {:error, :not_found} = Ledger.delete_expense(event, id)
    end

    assert Repo.get(Expense, expense.id)
    assert {:ok, :deleted} = Ledger.delete_expense(another, expense.id)
    assert {:error, :not_found} = Ledger.delete_expense(another, expense.id)
    assert Ledger.snapshot(event).members == [alice]
  end

  test "an unused person can be deleted without removing their family or other people" do
    event = event!()
    {:ok, family} = Ledger.create_household(event, %{"name" => "Our family"})
    alice = member!(event, "Alice", family.id)
    bob = member!(event, "Bob", family.id)
    Ledger.subscribe(event)

    assert {:ok, :deleted} = Ledger.delete_member(event, to_string(alice.id))
    assert_receive :ledger_changed
    assert Repo.get(Member, alice.id) == nil
    assert Repo.get(Member, bob.id).household_id == family.id
    assert Repo.get(Household, family.id)
  end

  test "expense payers, participants and both sides of repayments cannot be deleted" do
    event = event!()
    payer = member!(event, "Payer")
    participant = member!(event, "Participant")
    sender = member!(event, "Sender")
    recipient = member!(event, "Recipient")

    {:ok, expense} =
      Ledger.create_expense(event, %{
        "description" => "Tickets",
        "amount" => "10",
        "payer_id" => to_string(payer.id),
        "participant_ids" => [to_string(participant.id)]
      })

    {:ok, repayment} =
      Ledger.create_repayment(event, %{
        "amount" => "5",
        "from_member_id" => to_string(sender.id),
        "to_member_id" => to_string(recipient.id)
      })

    before = Ledger.snapshot(event)
    Ledger.subscribe(event)

    for member <- [payer, participant, sender, recipient] do
      assert {:error, :in_use} = Ledger.delete_member(event, member.id)
    end

    refute_receive :ledger_changed
    assert Ledger.snapshot(event) == before
    assert Repo.get(Expense, expense.id)
    assert Repo.get(Repayment, repayment.id)

    assert {:ok, :deleted} = Ledger.delete_expense(event, expense.id)
    assert {:ok, :deleted} = Ledger.delete_member(event, payer.id)
    assert {:ok, :deleted} = Ledger.delete_member(event, participant.id)
  end

  test "deleting a family keeps its people and financial history and unpools balances" do
    event = event!()
    {:ok, family} = Ledger.create_household(event, %{"name" => "Our family"})
    alice = member!(event, "Alice", family.id)
    bob = member!(event, "Bob", family.id)

    {:ok, _} =
      Ledger.create_expense(event, %{
        "description" => "Dinner",
        "amount" => "20",
        "payer_id" => to_string(alice.id),
        "participant_ids" => Enum.map([alice, bob], &to_string(&1.id))
      })

    {:ok, _} =
      Ledger.create_repayment(event, %{
        "amount" => "3",
        "from_member_id" => to_string(bob.id),
        "to_member_id" => to_string(alice.id)
      })

    before = Ledger.snapshot(event)
    Ledger.subscribe(event)
    assert {:ok, :deleted} = Ledger.delete_household(event, to_string(family.id))
    assert_receive :ledger_changed

    snapshot = Ledger.snapshot(event)
    assert snapshot.households == []
    assert length(snapshot.members) == 2
    assert Enum.all?(snapshot.members, &is_nil(&1.household_id))
    assert Enum.map(snapshot.expenses, & &1.id) == Enum.map(before.expenses, & &1.id)
    assert Enum.map(snapshot.repayments, & &1.id) == Enum.map(before.repayments, & &1.id)
    balances = Calculation.balances(snapshot.members, snapshot.expenses, snapshot.repayments)
    assert balances == %{alice.id => 700, bob.id => -700}
    pooled = Calculation.pooled_balances(snapshot.members, balances, snapshot.households)
    assert Calculation.suggestions(pooled) == [%{from: "Bob", to: "Alice", amount_cents: 700}]
  end

  test "people and family deletion rejects cross-event, invalid and already-deleted IDs" do
    event = event!()
    another = event!()
    {:ok, family} = Ledger.create_household(another, %{"name" => "Other family"})
    outsider = member!(another, "Outsider", family.id)

    for id <- [outsider.id, nil, "invalid", "0", String.duplicate("9", 100)] do
      assert {:error, :not_found} = Ledger.delete_member(event, id)
    end

    for id <- [family.id, nil, "invalid", "0", String.duplicate("9", 100)] do
      assert {:error, :not_found} = Ledger.delete_household(event, id)
    end

    assert Repo.get(Member, outsider.id).household_id == family.id
    assert Repo.get(Household, family.id)
    assert {:ok, :deleted} = Ledger.delete_household(another, family.id)
    assert {:error, :not_found} = Ledger.delete_household(another, family.id)
    assert {:ok, :deleted} = Ledger.delete_member(another, outsider.id)
    assert {:error, :not_found} = Ledger.delete_member(another, outsider.id)
  end

  defp event! do
    {:ok, event} = Ledger.create_event(%{"title" => "Test event", "currency" => "EUR"})
    event
  end

  defp member!(event, name, family_id \\ nil) do
    {:ok, member} = Ledger.create_member(event, %{"name" => name, "household_id" => family_id})
    member
  end
end
