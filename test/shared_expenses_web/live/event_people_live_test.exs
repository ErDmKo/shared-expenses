defmodule SharedExpensesWeb.EventPeopleLiveTest do
  use SharedExpensesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias SharedExpenses.Ledger

  test "person deletion can be canceled and updates other open views when confirmed", %{
    conn: conn
  } do
    event = event!()
    {:ok, family} = Ledger.create_household(event, %{"name" => "Our family"})
    {:ok, person} = Ledger.create_member(event, %{"name" => "Alex", "household_id" => family.id})
    {:ok, view, _} = live(conn, ~p"/e/#{event.slug}/people")
    {:ok, other_view, _} = live(build_conn(), ~p"/e/#{event.slug}/people")
    {:ok, expense_view, _} = live(build_conn(), ~p"/e/#{event.slug}")

    view |> element("#delete-member-#{person.id}") |> render_click()
    assert has_element?(view, "#confirm-delete-member-#{person.id}")
    assert length(Ledger.snapshot(event).members) == 1

    view |> element("#confirm-delete-member-#{person.id}-cancel") |> render_click()
    refute has_element?(view, "#confirm-delete-member-#{person.id}")
    assert has_element?(view, "#delete-member-#{person.id}")

    view |> element("#delete-member-#{person.id}") |> render_click()

    view
    |> element("#confirm-delete-member-#{person.id}-confirm")
    |> render_click()

    assert Ledger.snapshot(event).members == []
    refute has_element?(view, "#members-#{person.id}")
    assert has_element?(view, "#people-nav", "0")
    assert has_element?(view, "#delete-household-#{family.id}")
    refute has_element?(view, "#assignment-form")
    refute has_element?(other_view, "#members-#{person.id}")
    assert has_element?(other_view, "#people-nav", "0")
    refute has_element?(expense_view, "#expense-participant-#{person.id}")
    refute has_element?(expense_view, "#expense-form select option[value='#{person.id}']")
    assert has_element?(expense_view, "#add-people-link")
  end

  test "family deletion keeps people as individuals and refreshes family options", %{conn: conn} do
    event = event!()
    {:ok, family} = Ledger.create_household(event, %{"name" => "Our family"})
    {:ok, person} = Ledger.create_member(event, %{"name" => "Alex", "household_id" => family.id})
    {:ok, view, _} = live(conn, ~p"/e/#{event.slug}/people")
    {:ok, other_view, _} = live(build_conn(), ~p"/e/#{event.slug}/people")

    view |> element("#delete-member-#{person.id}") |> render_click()
    view |> element("#delete-household-#{family.id}") |> render_click()
    refute has_element?(view, "#confirm-delete-member-#{person.id}")
    assert has_element?(view, "#confirm-delete-household-#{family.id}")

    view |> element("#confirm-delete-household-#{family.id}-cancel") |> render_click()
    assert has_element?(view, "#delete-household-#{family.id}")
    refute has_element?(view, "#confirm-delete-household-#{family.id}")
    assert Ledger.snapshot(event).members |> hd() |> Map.get(:household_id) == family.id

    view |> element("#delete-household-#{family.id}") |> render_click()

    view
    |> element("#confirm-delete-household-#{family.id}-confirm")
    |> render_click()

    assert Ledger.snapshot(event).households == []
    assert Ledger.snapshot(event).members |> hd() |> Map.get(:household_id) == nil
    assert has_element?(view, "#members-#{person.id}", "Individual")
    assert has_element?(view, "#people-nav", "1")
    refute has_element?(view, "#households-#{family.id}")
    refute has_element?(view, "#member-form select option[value='#{family.id}']")
    refute has_element?(view, "#assignment-form")
    assert has_element?(other_view, "#members-#{person.id}", "Individual")
    refute has_element?(other_view, "#households-#{family.id}")
  end

  test "a person with ledger history gets an error instead of being deleted", %{conn: conn} do
    event = event!()
    {:ok, person} = Ledger.create_member(event, %{"name" => "Alex"})
    {:ok, view, _} = live(conn, ~p"/e/#{event.slug}/people")
    view |> element("#delete-member-#{person.id}") |> render_click()

    {:ok, expense} =
      Ledger.create_expense(event, %{
        "description" => "Dinner",
        "amount" => "20",
        "payer_id" => to_string(person.id),
        "participant_ids" => [to_string(person.id)]
      })

    view
    |> element("#confirm-delete-member-#{person.id}-confirm")
    |> render_click()

    assert has_element?(view, "#flash-error", "cannot be deleted")
    assert has_element?(view, "#delete-member-#{person.id}")
    refute has_element?(view, "#confirm-delete-member-#{person.id}")
    snapshot = Ledger.snapshot(event)
    assert Enum.map(snapshot.members, & &1.id) == [person.id]
    assert Enum.map(snapshot.expenses, & &1.id) == [expense.id]
  end

  test "foreign IDs and a stale confirmation do not delete other records", %{conn: conn} do
    event = event!()
    other_event = event!()
    {:ok, person} = Ledger.create_member(event, %{"name" => "Alex"})
    {:ok, outsider} = Ledger.create_member(other_event, %{"name" => "Outsider"})
    {:ok, family} = Ledger.create_household(other_event, %{"name" => "Other family"})
    {:ok, view, _} = live(conn, ~p"/e/#{event.slug}/people")

    render_click(view, "confirm_delete")
    assert length(Ledger.snapshot(event).members) == 1

    for {kind, id} <- [{"member", outsider.id}, {"household", family.id}, {"member", "invalid"}] do
      render_click(view, "request_delete", %{"kind" => kind, "id" => to_string(id)})
      assert has_element?(view, "#flash-error", "no longer available")
      render_click(view, "confirm_delete")
    end

    assert Enum.map(Ledger.snapshot(other_event).members, & &1.id) == [outsider.id]
    assert Enum.map(Ledger.snapshot(other_event).households, & &1.id) == [family.id]

    view |> element("#delete-member-#{person.id}") |> render_click()
    assert {:ok, :deleted} = Ledger.delete_member(event, person.id)
    render_click(view, "confirm_delete")
    assert has_element?(view, "#flash-error", "Person no longer available")
    assert Ledger.snapshot(event).members == []
  end

  defp event! do
    {:ok, event} = Ledger.create_event(%{"title" => "Shared weekend", "currency" => "EUR"})
    event
  end
end
