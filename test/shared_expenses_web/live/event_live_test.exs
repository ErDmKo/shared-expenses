defmodule SharedExpensesWeb.EventLiveTest do
  use SharedExpensesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias SharedExpenses.Ledger

  test "create an event, add people on their page, then record an expense", %{conn: conn} do
    {:ok, home, _} = live(conn, ~p"/")
    assert has_element?(home, "#event-form")

    redirect =
      home
      |> form("#event-form", event: %{title: "Weekend getaway", currency: "EUR"})
      |> render_submit()

    {:ok, view, _} = follow_redirect(redirect, conn)
    assert has_element?(view, "#event-hero h1", "Weekend getaway")
    assert has_element?(view, "header #site-header-content")
    assert has_element?(view, "main #site-main-content #event-hero")
    assert has_element?(view, "footer #site-footer-content")
    assert has_element?(view, "#event-hero #event-hero-total-spent", "€0")
    assert has_element?(view, "#cover-form")
    assert has_element?(view, "#expenses-section")
    assert has_element?(view, "#add-people-link")
    refute has_element?(view, "#member-form")
    refute has_element?(view, "#repayment-form")

    event = Ledger.get_event!(view |> element("#share-link") |> render() |> extract_slug())

    {:ok, people_view, _} =
      view |> element("#people-nav") |> render_click() |> follow_redirect(conn)

    assert has_element?(people_view, "#people-section")
    refute has_element?(people_view, "#expense-form")
    people_view |> form("#member-form", member: %{name: "Alex"}) |> render_submit()
    people_view |> form("#member-form", member: %{name: "Sam"}) |> render_submit()

    {:ok, view, _} =
      people_view |> element("#back-to-expenses") |> render_click() |> follow_redirect(conn)

    [alex, sam] = Enum.sort_by(event |> Ledger.snapshot() |> Map.fetch!(:members), & &1.name)
    assert has_element?(view, "#expense-participant-#{alex.id}[checked]")
    assert has_element?(view, "#expense-participant-#{sam.id}[checked]")

    view
    |> form("#expense-form",
      expense: %{
        description: "Dinner",
        amount: "20.00",
        payer_id: to_string(alex.id),
        participant_ids: [to_string(alex.id), to_string(sam.id)]
      }
    )
    |> render_submit()

    assert has_element?(view, "#expenses", "Dinner")
    assert has_element?(view, "#suggestions", "Sam")
    assert has_element?(view, "#total-spent", "€20")
    assert has_element?(view, "#event-hero-total-spent", "€20")
    refute has_element?(view, "#repayment-form")
  end

  test "a missing share link cannot show an event", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/e/not-a-real-event") end
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/e/not-a-real-event/people") end
  end

  test "families can be created and people assigned inside their event", %{conn: conn} do
    {:ok, event} = Ledger.create_event(%{"title" => "Family holiday", "currency" => "EUR"})
    {:ok, view, _} = live(conn, ~p"/e/#{event.slug}/people")

    view |> form("#household-form", household: %{name: "Our family"}) |> render_submit()
    view |> form("#member-form", member: %{name: "Pat"}) |> render_submit()
    snapshot = Ledger.snapshot(event)
    [family] = snapshot.households
    [person] = snapshot.members

    view
    |> form("#assignment-form",
      assignment: %{member_id: to_string(person.id), household_id: to_string(family.id)}
    )
    |> render_submit()

    assert Ledger.snapshot(event).members |> hd() |> Map.get(:household_id) == family.id
    assert has_element?(view, "#members", "Our family")
    assert has_element?(view, "#people-nav[aria-current='page']")
  end

  test "adding people on their page updates an already-open expense form", %{conn: conn} do
    {:ok, event} = Ledger.create_event(%{"title" => "Shared weekend", "currency" => "EUR"})
    {:ok, expense_view, _} = live(conn, ~p"/e/#{event.slug}")
    {:ok, people_view, _} = live(build_conn(), ~p"/e/#{event.slug}/people")

    people_view |> form("#member-form", member: %{name: "Alex"}) |> render_submit()

    [person] = Ledger.snapshot(event).members
    assert has_element?(expense_view, "#expense-participant-#{person.id}[checked]")
    assert has_element?(expense_view, "#people-nav", "1")
    refute has_element?(expense_view, "#add-people-link")
  end

  test "existing payments remain visible and counted without a new-payment form", %{conn: conn} do
    {:ok, event} = Ledger.create_event(%{"title" => "Old trip", "currency" => "EUR"})
    {:ok, alice} = Ledger.create_member(event, %{"name" => "Alice"})
    {:ok, bob} = Ledger.create_member(event, %{"name" => "Bob"})

    assert {:ok, _} =
             Ledger.create_expense(event, %{
               "description" => "Dinner",
               "amount" => "20",
               "payer_id" => to_string(alice.id),
               "participant_ids" => [to_string(alice.id), to_string(bob.id)]
             })

    assert {:ok, _} =
             Ledger.create_repayment(event, %{
               "amount" => "10",
               "from_member_id" => to_string(bob.id),
               "to_member_id" => to_string(alice.id)
             })

    {:ok, view, _} = live(conn, ~p"/e/#{event.slug}")
    assert has_element?(view, "#all-settled")
    assert has_element?(view, "#previous-payments", "€10")
    refute has_element?(view, "#repayment-form")
    refute has_element?(view, "#repayments-section")
  end

  test "an uploaded cover belongs to the event link", %{conn: conn} do
    {:ok, event} = Ledger.create_event(%{"title" => "Beach day", "currency" => "EUR"})
    {:ok, view, _} = live(conn, ~p"/e/#{event.slug}")

    png =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/d3sAAAAASUVORK5CYII="
      )

    upload =
      file_input(view, "#cover-form", :cover, [
        %{name: "beach.png", content: png, type: "image/png"}
      ])

    assert render_upload(upload, "beach.png") =~ "Save"
    view |> form("#cover-form") |> render_submit()

    updated = Ledger.get_event!(event.slug)
    assert updated.cover_filename
    assert response(get(conn, ~p"/e/#{event.slug}/cover"), 200) == png
    assert response(get(conn, ~p"/e/not-a-real-event/cover"), 404)

    {:ok, path} = SharedExpenses.Covers.path(updated.cover_filename)
    on_exit(fn -> File.rm(path) end)
  end

  test "a deletion can be canceled or confirmed and the other open view refreshes", %{conn: conn} do
    {:ok, event} = Ledger.create_event(%{"title" => "Weekend", "currency" => "EUR"})
    {:ok, alice} = Ledger.create_member(event, %{"name" => "Alice"})
    {:ok, bob} = Ledger.create_member(event, %{"name" => "Bob"})

    assert {:ok, expense} =
             Ledger.create_expense(event, %{
               "description" => "Tickets",
               "amount" => "10.00",
               "payer_id" => to_string(alice.id),
               "participant_ids" => Enum.map([alice, bob], &to_string(&1.id))
             })

    {:ok, view, _} = live(conn, ~p"/e/#{event.slug}")
    {:ok, second_view, _} = live(build_conn(), ~p"/e/#{event.slug}")

    assert has_element?(view, "#delete-expense-#{expense.id}")
    view |> element("#delete-expense-#{expense.id}") |> render_click()

    assert has_element?(
             view,
             "#confirm-delete-expense-#{expense.id}",
             "Recorded payments will remain"
           )

    assert length(Ledger.snapshot(event).expenses) == 1

    view |> element("#confirm-delete-expense-#{expense.id} button", "Cancel") |> render_click()
    refute has_element?(view, "#confirm-delete-expense-#{expense.id}")
    assert has_element?(view, "#total-spent", "€10")
    assert has_element?(view, "#event-hero-total-spent", "€10")

    view |> element("#delete-expense-#{expense.id}") |> render_click()

    view
    |> element("#confirm-delete-expense-#{expense.id} button", "Delete permanently")
    |> render_click()

    refute has_element?(view, "#delete-expense-#{expense.id}")
    assert has_element?(view, "#total-spent", "€0")
    assert has_element?(view, "#event-hero-total-spent", "€0")
    assert has_element?(view, "#all-settled")
    assert Ledger.snapshot(event).expenses == []

    refute has_element?(second_view, "#delete-expense-#{expense.id}")
    assert has_element?(second_view, "#total-spent", "€0")
    assert has_element?(second_view, "#event-hero-total-spent", "€0")
  end

  test "hero sums expense amounts in the event currency and updates other open views", %{
    conn: conn
  } do
    {:ok, event} = Ledger.create_event(%{"title" => "Weekend", "currency" => "USD"})
    {:ok, alice} = Ledger.create_member(event, %{"name" => "Alice"})
    {:ok, bob} = Ledger.create_member(event, %{"name" => "Bob"})
    {:ok, view, _} = live(conn, ~p"/e/#{event.slug}")
    {:ok, second_view, _} = live(build_conn(), ~p"/e/#{event.slug}")
    assert has_element?(view, "#event-hero-total-spent", "0 USD")

    for {description, amount} <- [{"Lunch", "12.34"}, {"Coffee", "5.67"}] do
      view
      |> form("#expense-form",
        expense: %{description: description, amount: amount, payer_id: to_string(alice.id)}
      )
      |> render_submit()
    end

    assert has_element?(view, "#event-hero-total-spent", "18.01 USD")
    assert has_element?(second_view, "#event-hero-total-spent", "18.01 USD")

    assert {:ok, _} =
             Ledger.create_repayment(event, %{
               "from_member_id" => to_string(bob.id),
               "to_member_id" => to_string(alice.id),
               "amount" => "1.00"
             })

    assert has_element?(view, "#event-hero-total-spent", "18.01 USD")
    assert has_element?(second_view, "#event-hero-total-spent", "18.01 USD")
    {:ok, reopened_view, _} = live(build_conn(), ~p"/e/#{event.slug}")
    assert has_element?(reopened_view, "#event-hero-total-spent", "18.01 USD")
  end

  test "a fresh expense splits between everyone and resets to all after saving", %{conn: conn} do
    {:ok, event} = Ledger.create_event(%{"title" => "Cabin trip", "currency" => "EUR"})
    {:ok, alice} = Ledger.create_member(event, %{"name" => "Alice"})
    {:ok, bob} = Ledger.create_member(event, %{"name" => "Bob"})
    {:ok, view, _} = live(conn, ~p"/e/#{event.slug}")

    assert has_element?(view, "#expense-participant-#{alice.id}[checked]")
    assert has_element?(view, "#expense-participant-#{bob.id}[checked]")
    assert has_element?(view, "#expense-form button[type='submit'][disabled]")
    original_key = expense_submission_key(view)

    view
    |> form("#expense-form",
      expense: %{description: "Groceries", amount: "9.00", payer_id: to_string(alice.id)}
    )
    |> render_submit()

    [expense] = Ledger.snapshot(event).expenses
    assert Enum.sort(Enum.map(expense.shares, & &1.member_id)) == Enum.sort([alice.id, bob.id])
    assert has_element?(view, "#expense-participant-#{alice.id}[checked]")
    assert has_element?(view, "#expense-participant-#{bob.id}[checked]")
    assert has_element?(view, "#expense-form button[type='submit'][disabled]")
    refute expense_submission_key(view) == original_key
  end

  test "save expense requires a nonblank name as well as a person", %{conn: conn} do
    {:ok, event} = Ledger.create_event(%{"title" => "Weekend", "currency" => "EUR"})
    {:ok, view, _} = live(conn, ~p"/e/#{event.slug}")
    assert has_element?(view, "#expense-form button[type='submit'][disabled]")

    view |> form("#expense-form", expense: %{description: "Coffee"}) |> render_change()
    assert has_element?(view, "#expense-form button[type='submit'][disabled]")

    {:ok, person} = Ledger.create_member(event, %{"name" => "Alex"})
    assert has_element?(view, "#expense-participant-#{person.id}")
    refute has_element?(view, "#expense-form button[type='submit'][disabled]")

    view |> form("#expense-form", expense: %{description: "  "}) |> render_change()
    assert has_element?(view, "#expense-form button[type='submit'][disabled]")

    view |> form("#expense-form", expense: %{description: " Dinner "}) |> render_change()
    refute has_element?(view, "#expense-form button[type='submit'][disabled]")

    view |> form("#expense-form", expense: %{description: ""}) |> render_change()
    assert has_element?(view, "#expense-form button[type='submit'][disabled]")
  end

  test "new people are selected on untouched forms but never override a draft's choices", %{
    conn: conn
  } do
    {:ok, event} = Ledger.create_event(%{"title" => "Group outing", "currency" => "EUR"})
    {:ok, view, _} = live(conn, ~p"/e/#{event.slug}")
    {:ok, alice} = Ledger.create_member(event, %{"name" => "Alice"})
    {:ok, bob} = Ledger.create_member(event, %{"name" => "Bob"})
    assert has_element?(view, "#expense-participant-#{alice.id}[checked]")
    assert has_element?(view, "#expense-participant-#{bob.id}[checked]")
    original_key = expense_submission_key(view)

    view
    |> form("#expense-form",
      expense: %{
        description: "Draft dinner",
        amount: "21.00",
        payer_id: to_string(alice.id),
        participant_ids: [to_string(alice.id)]
      }
    )
    |> render_change()

    {:ok, cara} = Ledger.create_member(event, %{"name" => "Cara"})
    assert has_element?(view, "#expense-participant-#{alice.id}[checked]")
    refute has_element?(view, "#expense-participant-#{bob.id}[checked]")
    refute has_element?(view, "#expense-participant-#{cara.id}[checked]")

    assert has_element?(
             view,
             "#expense-form input[name='expense[description]'][value='Draft dinner']"
           )

    assert expense_submission_key(view) == original_key

    view
    |> form("#expense-form", expense: %{participant_ids: []})
    |> render_change()

    {:ok, _} = Ledger.create_household(event, %{"name" => "Friends"})
    refute has_element?(view, "#expense-participant-#{alice.id}[checked]")
    refute has_element?(view, "#expense-participant-#{bob.id}[checked]")
    refute has_element?(view, "#expense-participant-#{cara.id}[checked]")
    assert expense_submission_key(view) == original_key

    view |> form("#expense-form") |> render_submit()
    assert has_element?(view, "#expense-error", "select one or more people")
    refute has_element?(view, "#expense-participant-#{alice.id}[checked]")
    assert Ledger.snapshot(event).expenses == []
  end

  test "a new expense splits 50/50 between families of different sizes", %{conn: conn} do
    {:ok, event} = Ledger.create_event(%{"title" => "Family trip", "currency" => "EUR"})
    {:ok, family_a} = Ledger.create_household(event, %{"name" => "Family A"})
    {:ok, family_b} = Ledger.create_household(event, %{"name" => "Family B"})

    members =
      for {name, family_id} <- [
            {"Alice", family_a.id},
            {"Bob", family_a.id},
            {"Cara", family_a.id},
            {"Dan", family_b.id}
          ] do
        {:ok, member} =
          Ledger.create_member(event, %{"name" => name, "household_id" => family_id})

        member
      end

    payer = hd(members)
    {:ok, view, _} = live(conn, ~p"/e/#{event.slug}")
    assert has_element?(view, "#expense-split-help", "one equal share")

    view
    |> form("#expense-form",
      expense: %{description: "Hotel", amount: "120", payer_id: to_string(payer.id)}
    )
    |> render_submit()

    assert has_element?(view, "#balance-household-#{family_a.id}", "€60")
    assert has_element?(view, "#balance-household-#{family_b.id}", "−€60")
    assert has_element?(view, "#suggestions", "Family B pays Family A €60")
    refute has_element?(view, "#balance-member-#{payer.id}")

    [expense] = Ledger.snapshot(event).expenses
    shares = Map.new(expense.shares, &{&1.member_id, &1.amount_cents})
    [alice, bob, cara, dan] = members
    assert shares == %{alice.id => 2000, bob.id => 2000, cara.id => 2000, dan.id => 6000}
  end

  test "family assignments and deletion recalculate existing expenses in an open view", %{
    conn: conn
  } do
    {:ok, event} = Ledger.create_event(%{"title" => "Existing trip", "currency" => "EUR"})

    members =
      for name <- ["Alice", "Bob", "Cara"] do
        {:ok, member} = Ledger.create_member(event, %{"name" => name})
        member
      end

    [alice, bob, cara] = members

    {:ok, _} =
      Ledger.create_expense(event, %{
        "description" => "Hotel",
        "amount" => "30",
        "payer_id" => to_string(cara.id),
        "participant_ids" => Enum.map(members, &to_string(&1.id))
      })

    [expense] = Ledger.snapshot(event).expenses
    assert Enum.all?(expense.shares, &(&1.amount_cents == 1000))
    {:ok, view, _} = live(conn, ~p"/e/#{event.slug}")
    assert has_element?(view, "#balance-member-#{cara.id}", "€20")

    {:ok, family} = Ledger.create_household(event, %{"name" => "Family A"})
    assert {:ok, _} = Ledger.update_member_household(event, alice.id, family.id)
    assert {:ok, _} = Ledger.update_member_household(event, bob.id, family.id)

    assert has_element?(view, "#balance-household-#{family.id}", "−€15")
    assert has_element?(view, "#balance-member-#{cara.id}", "€15")
    assert has_element?(view, "#suggestions", "Family A pays Cara €15")
    refute has_element?(view, "#balance-member-#{alice.id}")
    refute has_element?(view, "#balance-member-#{bob.id}")

    {:ok, people_view, _} = live(build_conn(), ~p"/e/#{event.slug}/people")
    people_view |> element("#delete-household-#{family.id}") |> render_click()
    people_view |> element("#confirm-delete-household-#{family.id}-confirm") |> render_click()

    refute has_element?(view, "#balance-household-#{family.id}")
    assert has_element?(view, "#balance-member-#{alice.id}", "−€10")
    assert has_element?(view, "#balance-member-#{bob.id}", "−€10")
    assert has_element?(view, "#balance-member-#{cara.id}", "€20")
    assert has_element?(view, "#total-spent", "€30")
  end

  defp expense_submission_key(view) do
    html = view |> element("#expense-form input[name='expense[submission_key]']") |> render()
    [_, key] = Regex.run(~r/value="([^"]+)"/, html)
    key
  end

  defp extract_slug(html) do
    [_, slug] = Regex.run(~r|/e/([A-Za-z0-9_-]{32})|, html)
    slug
  end
end
