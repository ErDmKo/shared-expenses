defmodule SharedExpensesWeb.EventPeopleLive do
  use SharedExpensesWeb, :live_view

  alias SharedExpenses.Ledger
  alias SharedExpenses.Ledger.{Household, Member}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    event = Ledger.get_event!(slug)
    if connected?(socket), do: Ledger.subscribe(event)

    {:ok,
     socket
     |> assign(:member_form, to_form(Member.changeset(%Member{}, %{})))
     |> assign(:household_form, to_form(Household.changeset(%Household{}, %{})))
     |> assign(
       :assignment_form,
       to_form(%{"member_id" => "", "household_id" => ""}, as: :assignment)
     )
     |> assign(:assignment_error, nil)
     |> assign(:pending_delete, nil)
     |> refresh(event)}
  end

  @impl true
  def handle_info(:ledger_changed, socket), do: {:noreply, refresh(socket, socket.assigns.event)}

  @impl true
  def handle_event("add_member", %{"member" => params}, socket) do
    case Ledger.create_member(socket.assigns.event, params) do
      {:ok, _} ->
        {:noreply, assign(socket, :member_form, to_form(Member.changeset(%Member{}, %{})))}

      {:error, changeset} ->
        {:noreply, assign(socket, :member_form, to_form(%{changeset | action: :insert}))}
    end
  end

  def handle_event("add_household", %{"household" => params}, socket) do
    case Ledger.create_household(socket.assigns.event, params) do
      {:ok, _} ->
        {:noreply,
         assign(socket, :household_form, to_form(Household.changeset(%Household{}, %{})))}

      {:error, changeset} ->
        {:noreply, assign(socket, :household_form, to_form(%{changeset | action: :insert}))}
    end
  end

  def handle_event("assign_household", %{"assignment" => params}, socket) do
    case Ledger.update_member_household(
           socket.assigns.event,
           params["member_id"],
           params["household_id"]
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:assignment_error, nil)
         |> assign(
           :assignment_form,
           to_form(%{"member_id" => "", "household_id" => ""}, as: :assignment)
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:assignment_error, "Choose a person and a family from this event.")
         |> assign(:assignment_form, to_form(params, as: :assignment))}
    end
  end

  def handle_event("request_delete", %{"kind" => kind, "id" => id}, socket)
      when kind in ["member", "household"] do
    records =
      case kind do
        "member" -> socket.assigns.event.members
        "household" -> socket.assigns.event.households
      end

    case Enum.find(records, &(to_string(&1.id) == id)) do
      nil ->
        {:noreply,
         socket
         |> refresh(socket.assigns.event)
         |> put_flash(:error, "Person or family no longer available.")}

      record ->
        {:noreply,
         socket
         |> assign(:pending_delete, {kind, record.id})
         |> refresh(socket.assigns.event)}
    end
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply,
     socket
     |> assign(:pending_delete, nil)
     |> refresh(socket.assigns.event)}
  end

  def handle_event("confirm_delete", _, %{assigns: %{pending_delete: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("confirm_delete", _, socket) do
    {kind, id} = socket.assigns.pending_delete

    {result, label} =
      case kind do
        "member" -> {Ledger.delete_member(socket.assigns.event, id), "Person"}
        "household" -> {Ledger.delete_household(socket.assigns.event, id), "Family"}
      end

    socket =
      socket
      |> assign(:pending_delete, nil)
      |> refresh(socket.assigns.event)

    case result do
      {:ok, :deleted} ->
        {:noreply, put_flash(socket, :info, "#{label} deleted.")}

      {:error, :in_use} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This person cannot be deleted while they have expenses or recorded payments."
         )}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "#{label} no longer available.")}
    end
  end

  defp refresh(socket, event) do
    event = Ledger.snapshot(event)
    members = Enum.sort_by(event.members, &{&1.name, &1.id})
    households = Enum.sort_by(event.households, &{&1.name, &1.id})

    socket
    |> assign(:event, event)
    |> assign(:page_title, "People · #{event.title}")
    |> assign(:members_count, length(members))
    |> assign(:household_options, Enum.map(households, &{&1.name, to_string(&1.id)}))
    |> assign(:member_options, Enum.map(members, &{&1.name, to_string(&1.id)}))
    |> stream(:members, members, reset: true)
    |> stream(:households, households, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-5 py-6 sm:space-y-7 sm:py-10">
        <.link
          id="back-to-expenses"
          navigate={~p"/e/#{@event.slug}"}
          class="inline-flex min-h-11 items-center gap-2 text-sm font-semibold text-indigo-600 hover:text-indigo-800"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Back to expenses
        </.link>

        <header class="rounded-3xl bg-gradient-to-br from-indigo-800 via-indigo-600 to-sky-500 p-5 text-white sm:p-8">
          <p class="text-xs font-semibold uppercase tracking-widest text-white/75">{@event.title}</p>
          <h1 class="mt-2 text-2xl font-semibold tracking-tight sm:text-4xl">People & families</h1>
          <p class="mt-2 text-sm text-white/80">
            {@members_count} {if(@members_count == 1, do: "person", else: "people")} in this event
          </p>
        </header>

        <nav
          id="event-nav"
          aria-label="Event sections"
          class="grid grid-cols-2 gap-2 rounded-2xl bg-white p-1.5 ring-1 ring-slate-200"
        >
          <.link
            id="expenses-nav"
            navigate={~p"/e/#{@event.slug}"}
            class="flex min-h-11 items-center justify-center gap-2 rounded-xl px-2 py-2 text-center text-sm font-semibold text-slate-600 hover:bg-indigo-50 hover:text-indigo-700"
          >
            <.icon name="hero-receipt-percent" class="size-4" /> Expenses
          </.link>
          <span
            id="people-nav"
            aria-current="page"
            class="flex min-h-11 items-center justify-center gap-2 rounded-xl bg-indigo-50 px-2 py-2 text-center text-sm font-semibold text-indigo-700"
          >
            <.icon name="hero-user-group" class="size-4" /> People
            <span class="rounded-full bg-white px-1.5 text-xs">{@members_count}</span>
          </span>
        </nav>

        <div class="grid items-start gap-5 lg:grid-cols-2 lg:gap-6">
          <section class="surface p-5 sm:p-6" id="people-section">
            <div class="flex items-center gap-3">
              <span class="section-icon"><.icon name="hero-user-group" class="size-5" /></span>
              <div>
                <h2 class="text-xl font-semibold text-slate-900">Add people</h2><p class="text-sm text-slate-500">
                  Everyone who might share a cost.
                </p>
              </div>
            </div>
            <.form for={@member_form} id="member-form" phx-submit="add_member" class="mt-6 space-y-2">
              <.input
                field={@member_form[:name]}
                label="Person's name"
                placeholder="Alex"
                required
                maxlength="80"
              />
              <div class="flex flex-col gap-2 sm:flex-row sm:items-end">
                <div class="min-w-0 flex-1">
                  <.input
                    field={@member_form[:household_id]}
                    type="select"
                    label="Family (optional)"
                    options={@household_options}
                    prompt="On their own"
                  />
                </div>
                <button type="submit" class="primary-button mb-2 w-full sm:w-auto">Add person</button>
              </div>
            </.form>
            <div
              id="members"
              phx-update="stream"
              class="mt-4 divide-y divide-slate-100 border-t border-slate-100"
            >
              <p id="members-empty" class="hidden py-4 text-sm text-slate-500 only:block">
                No people yet. Add your first person above.
              </p>
              <div
                :for={{id, member} <- @streams.members}
                id={id}
                class="py-3 text-sm"
              >
                <div class="flex items-center justify-between gap-3">
                  <div class="flex min-w-0 items-center gap-3">
                    <span class="flex size-9 shrink-0 items-center justify-center rounded-full bg-indigo-50 font-semibold text-indigo-600">{String.first(
                      member.name
                    )}</span>
                    <div class="min-w-0">
                      <p class="truncate font-medium text-slate-800">{member.name}</p>
                      <p class="mt-0.5 truncate text-xs text-slate-500">
                        {if member.household_id,
                          do:
                            Enum.find_value(
                              @event.households,
                              &if(&1.id == member.household_id, do: &1.name)
                            ),
                          else: "Individual"}
                      </p>
                    </div>
                  </div>
                  <button
                    id={"delete-member-#{member.id}"}
                    type="button"
                    phx-click="request_delete"
                    phx-value-kind="member"
                    phx-value-id={member.id}
                    aria-label={"Delete person #{member.name}"}
                    class="inline-flex min-h-11 shrink-0 items-center gap-1.5 rounded-lg px-2 text-sm font-semibold text-rose-600 transition hover:bg-rose-50 hover:text-rose-800"
                  >
                    <.icon name="hero-trash" class="size-4" /> Delete
                  </button>
                </div>
                <.delete_confirmation
                  :if={@pending_delete == {"member", member.id}}
                  id={"confirm-delete-member-#{member.id}"}
                >
                  Delete {member.name}? People with expenses or recorded payments cannot be deleted.
                </.delete_confirmation>
              </div>
            </div>
          </section>

          <section class="surface p-5 sm:p-6" id="families-section">
            <div class="flex items-center gap-3">
              <span class="section-icon"><.icon name="hero-home" class="size-5" /></span>
              <div>
                <h2 class="text-xl font-semibold text-slate-900">Couples & families</h2><p class="text-sm text-slate-500">
                  Share one portion and settle together.
                </p>
              </div>
            </div>
            <p class="mt-5 text-sm leading-relaxed text-slate-600">
              Each family counts as one equal share of an expense, regardless of how many people it has.
              People without a family each count as one share. No payments are needed within a family.
            </p>
            <.form
              for={@household_form}
              id="household-form"
              phx-submit="add_household"
              class="mt-4 flex flex-col gap-2 sm:flex-row sm:items-end"
            >
              <div class="min-w-0 flex-1">
                <.input
                  field={@household_form[:name]}
                  label="Family name"
                  placeholder="The Parkers"
                  required
                  maxlength="80"
                />
              </div>
              <button type="submit" class="secondary-button mb-2 w-full sm:w-auto">Create family</button>
            </.form>
            <div id="households" phx-update="stream" class="mt-2 flex flex-wrap gap-2">
              <div
                :for={{id, household} <- @streams.households}
                id={id}
                class="min-w-0"
              >
                <div class="inline-flex max-w-full items-center gap-2 rounded-full bg-indigo-50 pl-3 pr-1 text-xs font-semibold text-indigo-700">
                  <span class="truncate">{household.name}</span>
                  <button
                    id={"delete-household-#{household.id}"}
                    type="button"
                    phx-click="request_delete"
                    phx-value-kind="household"
                    phx-value-id={household.id}
                    aria-label={"Delete family #{household.name}"}
                    class="inline-flex min-h-11 shrink-0 items-center gap-1.5 rounded-full px-2 text-rose-600 transition hover:bg-rose-50 hover:text-rose-800"
                  >
                    <.icon name="hero-trash" class="size-4" /> Delete
                  </button>
                </div>
                <.delete_confirmation
                  :if={@pending_delete == {"household", household.id}}
                  id={"confirm-delete-household-#{household.id}"}
                >
                  Delete {household.name}? Its people will stay in the event as individuals.
                </.delete_confirmation>
              </div>
            </div>
            <.form
              :if={@members_count > 0 and @household_options != []}
              for={@assignment_form}
              id="assignment-form"
              phx-submit="assign_household"
              class="mt-5 grid gap-2 border-t border-slate-100 pt-5 sm:grid-cols-[1fr_1fr_auto] sm:items-end"
            >
              <.input
                field={@assignment_form[:member_id]}
                type="select"
                label="Person"
                options={@member_options}
                prompt="Select"
              />
              <.input
                field={@assignment_form[:household_id]}
                type="select"
                label="Family"
                options={@household_options}
                prompt="On their own"
              />
              <button class="secondary-button mb-2 w-full sm:w-auto" type="submit">Assign</button>
            </.form>
            <p :if={@assignment_error} class="mt-2 text-sm text-rose-600">{@assignment_error}</p>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  slot :inner_block, required: true

  defp delete_confirmation(assigns) do
    ~H"""
    <div id={@id} class="mt-3 rounded-2xl border border-rose-200 bg-rose-50 p-4">
      <p class="text-sm font-medium text-rose-900">{render_slot(@inner_block)}</p>
      <div class="mt-3 flex flex-wrap gap-3">
        <button
          id={"#{@id}-confirm"}
          type="button"
          phx-click="confirm_delete"
          phx-disable-with="Deleting…"
          class="min-h-11 rounded-lg bg-rose-600 px-4 py-2 text-sm font-semibold text-white transition hover:bg-rose-700"
        >Delete permanently</button>
        <button
          id={"#{@id}-cancel"}
          type="button"
          phx-click="cancel_delete"
          class="min-h-11 rounded-lg border border-rose-200 bg-white px-4 py-2 text-sm font-semibold text-slate-700 transition hover:bg-slate-50"
        >Cancel</button>
      </div>
    </div>
    """
  end
end
