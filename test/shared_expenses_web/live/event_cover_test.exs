defmodule SharedExpensesWeb.EventCoverTest do
  use SharedExpensesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias SharedExpenses.Ledger

  test "both pages show the same fallback and reserve the same hero space", %{conn: conn} do
    {:ok, event} = Ledger.create_event(%{"title" => "Weekend", "currency" => "EUR"})
    {:ok, expenses, _} = live(conn, ~p"/e/#{event.slug}")
    {:ok, people, _} = live(build_conn(), ~p"/e/#{event.slug}/people")

    assert has_element?(expenses, "#event-hero.bg-gradient-to-br h1", "Weekend")
    assert has_element?(people, "#people-hero.bg-gradient-to-br h1", "Weekend")
    assert has_element?(expenses, "#event-heading-badge", "Expenses")
    assert has_element?(people, "#people-heading-badge", "People & families")

    assert expenses
           |> element("#event-heading-title")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.attribute("class") ==
             people
             |> element("#people-heading-title")
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.attribute("class")

    assert hero_style(expenses, "#event-hero") == [""]
    assert hero_style(people, "#people-hero") == [""]
    assert has_element?(expenses, "#event-details > summary#event-details-toggle")

    for {view, selector} <- [{expenses, "#event-hero"}, {people, "#people-hero"}] do
      assert has_element?(view, "#event-page #event-page-actions.min-h-11")

      assert has_element?(
               view,
               "#event-page.space-y-5.py-6 > #{selector}"
             )

      [classes] =
        view
        |> element(selector)
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.attribute("class")

      assert "min-h-[15rem]" in String.split(classes)
      assert "sm:min-h-[16.5rem]" in String.split(classes)
      assert "p-4" in String.split(classes)
      assert "sm:p-6" in String.split(classes)
    end
  end

  test "both pages use the event's cover and update when it is replaced", %{conn: conn} do
    {:ok, event} = Ledger.create_event(%{"title" => "Weekend", "currency" => "EUR"})
    {:ok, _} = Ledger.update_cover(event, "first.png")
    {:ok, expenses, _} = live(conn, ~p"/e/#{event.slug}")
    {:ok, people, _} = live(build_conn(), ~p"/e/#{event.slug}/people")

    [first_style] = hero_style(expenses, "#event-hero")
    assert hero_style(people, "#people-hero") == [first_style]
    assert first_style =~ ~p"/e/#{event.slug}/cover?#{[v: "first.png"]}"

    assert {:ok, _} = Ledger.update_cover(event, "second.png")
    [updated_style] = hero_style(expenses, "#event-hero")
    assert hero_style(people, "#people-hero") == [updated_style]
    assert updated_style =~ ~p"/e/#{event.slug}/cover?#{[v: "second.png"]}"
    refute updated_style == first_style

    {:ok, reopened_people, _} = live(build_conn(), ~p"/e/#{event.slug}/people")
    assert hero_style(reopened_people, "#people-hero") == [updated_style]

    assert {:ok, _} = Ledger.update_cover(Ledger.get_event!(event.slug), nil)
    assert hero_style(expenses, "#event-hero") == [""]
    assert hero_style(people, "#people-hero") == [""]
  end

  test "a selected cover previews before upload and cancel keeps the saved cover", %{conn: conn} do
    {:ok, event} = Ledger.create_event(%{"title" => "Weekend", "currency" => "EUR"})
    {:ok, event} = Ledger.update_cover(event, "existing.png")
    {:ok, view, _} = live(conn, ~p"/e/#{event.slug}")
    {:ok, people, _} = live(build_conn(), ~p"/e/#{event.slug}/people")
    original_style = hero_style(view, "#event-hero")

    png =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/d3sAAAAASUVORK5CYII="
      )

    upload =
      file_input(view, "#cover-form", :cover, [
        %{name: "replacement.png", content: png, type: "image/png"}
      ])

    assert {:ok, _} = preflight_upload(upload)
    assert has_element?(view, "#event-hero-preview img[data-phx-hook='Phoenix.LiveImgPreview']")
    assert has_element?(view, "#cover-preview-notice")
    assert has_element?(view, "#event-details[open]")
    assert has_element?(view, "#save-cover")
    assert Ledger.get_event!(event.slug).cover_filename == "existing.png"
    refute has_element?(people, "#people-hero-preview")

    view |> element("#cancel-cover-upload") |> render_click()
    refute has_element?(view, "#event-hero-preview")
    refute has_element?(view, "#cover-preview-notice")
    refute has_element?(view, "#save-cover")
    assert hero_style(view, "#event-hero") == original_style
    assert hero_style(people, "#people-hero") == original_style
    assert Ledger.get_event!(event.slug).cover_filename == "existing.png"
  end

  defp hero_style(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("style")
  end
end
