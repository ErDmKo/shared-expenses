defmodule SharedExpensesWeb.EventLive do
  use SharedExpensesWeb, :live_view

  alias SharedExpenses.{Covers, Ledger}
  alias SharedExpenses.Ledger.Calculation

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    event = Ledger.get_event!(slug)
    if connected?(socket), do: Ledger.subscribe(event)

    socket =
      socket
      |> allow_upload(:cover,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 3_000_000
      )
      |> assign(:cover_form, to_form(%{}, as: :cover))
      |> assign(:expense_form_touched?, false)
      |> assign(:expense_error, nil)
      |> assign(:pending_delete_expense_id, nil)
      |> assign(:cover_error, nil)
      |> refresh(event)

    {:ok, assign(socket, :expense_form, empty_expense_form(socket.assigns.members))}
  end

  @impl true
  def handle_info(:ledger_changed, socket), do: {:noreply, refresh(socket, socket.assigns.event)}

  @impl true
  def handle_event("change_expense", %{"expense" => params}, socket) do
    params = Map.put_new(params, "participant_ids", [])

    {:noreply,
     socket
     |> assign(:expense_form_touched?, true)
     |> assign(:expense_form, to_form(params, as: :expense))}
  end

  def handle_event("add_expense", %{"expense" => submitted}, socket) do
    params = Map.put_new(submitted, "participant_ids", [])

    case Ledger.create_expense(socket.assigns.event, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:expense_error, nil)
         |> assign(:expense_form_touched?, false)
         |> assign(:expense_form, empty_expense_form(socket.assigns.members))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:expense_error, error_text(changeset))
         |> assign(:expense_form_touched?, true)
         |> assign(:expense_form, to_form(params, as: :expense))}
    end
  end

  def handle_event("request_delete_expense", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.event.expenses, &(to_string(&1.id) == id)) do
      nil ->
        {:noreply,
         socket
         |> refresh(socket.assigns.event)
         |> put_flash(:error, "Expense no longer available.")}

      expense ->
        previous_id = socket.assigns.pending_delete_expense_id

        {:noreply,
         socket
         |> assign(:pending_delete_expense_id, expense.id)
         |> restream_expense(previous_id)
         |> stream_insert(:expenses, expense)}
    end
  end

  def handle_event("cancel_delete_expense", _, socket) do
    previous_id = socket.assigns.pending_delete_expense_id

    {:noreply,
     socket
     |> assign(:pending_delete_expense_id, nil)
     |> restream_expense(previous_id)}
  end

  def handle_event("confirm_delete_expense", _, socket) do
    result = Ledger.delete_expense(socket.assigns.event, socket.assigns.pending_delete_expense_id)

    socket =
      socket
      |> assign(:pending_delete_expense_id, nil)
      |> refresh(socket.assigns.event)

    case result do
      {:ok, :deleted} ->
        {:noreply, put_flash(socket, :info, "Expense deleted.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Expense no longer available.")}
    end
  end

  def handle_event("validate_cover", _, socket), do: {:noreply, socket}

  def handle_event("save_cover", _, socket) do
    results =
      consume_uploaded_entries(socket, :cover, fn %{path: path}, _entry ->
        {:ok, Covers.save(path)}
      end)

    case results do
      [{:ok, filename}] ->
        case Ledger.update_cover(socket.assigns.event, filename) do
          {:ok, _} ->
            if old = socket.assigns.event.cover_filename do
              with {:ok, path} <- Covers.path(old), do: File.rm(path)
            end

            {:noreply, assign(socket, :cover_error, nil)}

          {:error, _} ->
            with {:ok, path} <- Covers.path(filename), do: File.rm(path)
            {:noreply, assign(socket, :cover_error, "Could not save the cover. Try again.")}
        end

      _ ->
        {:noreply, assign(socket, :cover_error, "Choose a JPEG, PNG or WebP image up to 3 MB.")}
    end
  end

  defp refresh(socket, event) do
    event = Ledger.snapshot(event)
    members = Enum.sort_by(event.members, &{&1.name, &1.id})
    households = Enum.sort_by(event.households, &{&1.name, &1.id})
    expenses = Enum.sort_by(event.expenses, & &1.id, :desc)
    repayments = Enum.sort_by(event.repayments, & &1.id, :desc)
    balances = Calculation.balances(members, expenses, repayments)
    pooled = Calculation.pooled_balances(members, balances, households)

    socket =
      if Map.has_key?(socket.assigns, :expense_form) && !socket.assigns.expense_form_touched? do
        form = socket.assigns.expense_form
        params = Map.put(form.source, "participant_ids", Enum.map(members, &to_string(&1.id)))
        assign(socket, :expense_form, to_form(params, as: :expense))
      else
        socket
      end

    socket
    |> assign(:event, event)
    |> assign(:page_title, event.title)
    |> assign(:members_count, length(members))
    |> assign(:expenses_count, length(expenses))
    |> assign(:repayments_count, length(repayments))
    |> assign(:expense_total, Enum.sum(Enum.map(expenses, & &1.amount_cents)))
    |> assign(:members, members)
    |> assign(:member_options, Enum.map(members, &{&1.name, to_string(&1.id)}))
    |> assign(:balances, balances)
    |> assign(:pooled, pooled)
    |> assign(:suggestions, Calculation.suggestions(pooled))
    |> stream(:expenses, expenses, reset: true)
    |> stream(:repayments, repayments, reset: true)
  end

  defp restream_expense(socket, id) do
    case Enum.find(socket.assigns.event.expenses, &(&1.id == id)) do
      nil -> socket
      expense -> stream_insert(socket, :expenses, expense)
    end
  end

  defp empty_expense_form(members),
    do:
      to_form(
        %{
          "description" => "",
          "amount" => "",
          "payer_id" => "",
          "participant_ids" => Enum.map(members, &to_string(&1.id)),
          "submission_key" => new_key()
        },
        as: :expense
      )

  defp new_key, do: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

  defp error_text(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _}} -> "#{Phoenix.Naming.humanize(field)}: #{message}" end)
    |> Enum.join(" · ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-7 py-8 sm:py-11">
        <div class="flex items-center justify-between gap-3">
          <div class="eyebrow">YOUR EVENT</div>
          <.link navigate={~p"/"} class="text-sm font-semibold text-indigo-600 hover:text-indigo-800">+ New event</.link>
        </div>

        <section
          id="event-hero"
          class="relative overflow-hidden rounded-3xl bg-gradient-to-br from-indigo-800 via-indigo-600 to-sky-500 p-5 text-white sm:p-8"
          style={
            if @event.cover_filename,
              do:
                "background-image: linear-gradient(90deg, rgba(18,26,59,.86), rgba(32,45,85,.42)), url('#{~p"/e/#{@event.slug}/cover"}'); background-position: center; background-size: cover;",
              else: ""
          }
        >
          <div class="relative z-10 max-w-xl">
            <span class="rounded-full border border-white/35 bg-white/15 px-3 py-1 text-xs font-semibold uppercase tracking-widest">Shared event</span>
            <h1 class="mt-4 break-words text-2xl font-semibold tracking-tight sm:text-4xl">
              {@event.title}
            </h1>
            <p class="mt-2 text-sm text-white/80">
              {@members_count} {if(@members_count == 1, do: "person", else: "people")} · {@expenses_count} {if(
                @expenses_count == 1,
                do: "expense",
                else: "expenses"
              )} · {@event.currency}
            </p>
            <div class="mt-4">
              <p class="text-xs font-semibold uppercase tracking-wider text-white/75">Total spent</p>
              <p
                id="event-hero-total-spent"
                class="mt-1 break-words font-display text-2xl font-semibold tracking-tight tabular-nums sm:text-3xl"
              >
                <.money amount_cents={@expense_total} currency={@event.currency} />
              </p>
            </div>
          </div>
          <details id="event-details" class="group relative z-10 mt-4 border-t border-white/25 pt-1">
            <summary class="flex min-h-11 cursor-pointer items-center justify-between gap-3 text-sm font-semibold text-white/90">
              Share link & cover
              <.icon
                name="hero-chevron-down"
                class="size-4 transition-transform group-open:rotate-180"
              />
            </summary>
            <div class="flex flex-col gap-4 pb-2 pt-2 sm:flex-row sm:items-end sm:justify-between">
              <div class="min-w-0">
                <p class="text-xs font-semibold uppercase tracking-widest text-white/70">
                  Share this event
                </p>
                <p id="share-link" class="mt-1 break-all text-sm font-medium">
                  {SharedExpensesWeb.Endpoint.url() <> ~p"/e/#{@event.slug}"}
                </p>
                <p class="mt-1 text-xs text-white/70">
                  Anyone with this link can see and edit the event. Keep it with your group.
                </p>
              </div>
              <.form
                for={@cover_form}
                id="cover-form"
                phx-change="validate_cover"
                phx-submit="save_cover"
                class="flex shrink-0 items-center gap-2"
              >
                <label class="flex min-h-11 cursor-pointer items-center rounded-lg border border-white/40 bg-white/15 px-4 text-sm font-semibold transition hover:bg-white/25">
                  Add a cover <.live_file_input upload={@uploads.cover} class="sr-only" />
                </label>
                <button
                  :if={@uploads.cover.entries != []}
                  class="min-h-11 rounded-lg bg-white px-4 text-sm font-semibold text-indigo-800"
                  type="submit"
                >Save</button>
              </.form>
            </div>
            <p :if={@cover_error} class="pb-2 text-sm text-rose-100">{@cover_error}</p>
            <p :for={error <- upload_errors(@uploads.cover)} class="pb-2 text-sm text-rose-100">
              Cover upload: {inspect(error)}
            </p>
          </details>
        </section>

        <nav
          id="event-nav"
          aria-label="Event sections"
          class="grid grid-cols-2 gap-2 rounded-2xl bg-white p-1.5 ring-1 ring-slate-200"
        >
          <span
            id="expenses-nav"
            aria-current="page"
            class="flex min-h-11 items-center justify-center gap-2 rounded-xl bg-indigo-50 px-2 py-2 text-center text-sm font-semibold text-indigo-700"
          >
            <.icon name="hero-receipt-percent" class="size-4" /> Expenses
          </span>
          <.link
            id="people-nav"
            navigate={~p"/e/#{@event.slug}/people"}
            class="flex min-h-11 items-center justify-center gap-2 rounded-xl px-2 py-2 text-center text-sm font-semibold text-slate-600 hover:bg-indigo-50 hover:text-indigo-700"
          >
            <.icon name="hero-user-group" class="size-4" /> People
            <span class="rounded-full bg-slate-100 px-1.5 text-xs">{@members_count}</span>
          </.link>
        </nav>

        <section class="surface p-5 sm:p-6" id="expenses-section">
          <div class="flex items-center gap-3">
            <span class="section-icon"><.icon name="hero-receipt-percent" class="size-5" /></span>
            <div>
              <h2 class="text-xl font-semibold text-slate-900">Add an expense</h2>
              <p class="text-sm text-slate-500">Who paid, and who should split it?</p>
            </div>
          </div>
          <.form
            for={@expense_form}
            id="expense-form"
            phx-change="change_expense"
            phx-submit="add_expense"
            class="mt-6 space-y-3"
          >
            <.input field={@expense_form[:submission_key]} type="hidden" />
            <.input
              field={@expense_form[:description]}
              label="What was it for?"
              placeholder="Dinner by the beach"
              required
              maxlength="200"
            />
            <div class="grid gap-3 sm:grid-cols-2">
              <.input
                field={@expense_form[:amount]}
                type="text"
                label={"Amount (#{@event.currency})"}
                placeholder="48.50"
                inputmode="decimal"
                required
              />
              <.input
                field={@expense_form[:payer_id]}
                type="select"
                label="Paid by"
                options={@member_options}
                prompt="Select a person"
              />
            </div>
            <fieldset id="expense-participants" class="space-y-2 pt-1">
              <legend class="mb-2 text-sm font-semibold text-slate-700">
                Split between
                <span class="font-normal text-slate-500">· everyone selected by default</span>
              </legend>
              <p id="expense-split-help" class="text-xs leading-relaxed text-slate-500">
                Each selected family counts as one equal share, regardless of its size.
                Each person without a family counts as one share.
              </p>
              <label
                :for={member <- @members}
                class="flex cursor-pointer items-center gap-3 rounded-xl border border-slate-200 p-3 text-sm transition hover:border-indigo-300 hover:bg-indigo-50/50"
              >
                <input
                  id={"expense-participant-#{member.id}"}
                  type="checkbox"
                  name="expense[participant_ids][]"
                  value={member.id}
                  checked={to_string(member.id) in List.wrap(@expense_form[:participant_ids].value)}
                  class="checkbox checkbox-sm border-slate-300"
                />
                <span class="font-medium text-slate-700">{member.name}</span>
              </label>
              <p :if={@members_count == 0} class="text-sm text-slate-500">
                <.link
                  id="add-people-link"
                  navigate={~p"/e/#{@event.slug}/people"}
                  class="font-semibold text-indigo-600 underline underline-offset-2"
                >Add people</.link>
                first, then choose who shares this expense.
              </p>
            </fieldset>
            <p
              :if={@expense_error}
              id="expense-error"
              class="rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-700"
            >
              {@expense_error}
            </p>
            <button
              class="primary-button w-full sm:w-auto"
              type="submit"
              disabled={
                @members_count == 0 or String.trim(@expense_form[:description].value || "") == ""
              }
            >Save expense <.icon name="hero-arrow-right" class="size-4" /></button>
          </.form>
        </section>

        <section class="grid grid-cols-2 gap-3 sm:gap-4" aria-label="Event overview">
          <div class="surface p-4 sm:p-5">
            <p class="text-xs font-semibold uppercase tracking-wider text-slate-500">Total spent</p>
            <p
              id="total-spent"
              class="mt-2 text-xl font-semibold tracking-tight text-slate-900 sm:text-2xl"
            >
              <.money amount_cents={@expense_total} currency={@event.currency} />
            </p>
          </div>
          <div class="surface p-4 sm:p-5">
            <p class="text-xs font-semibold uppercase tracking-wider text-slate-500">Expenses</p>
            <p class="mt-2 text-xl font-semibold text-slate-900 sm:text-2xl">{@expenses_count}</p>
          </div>
        </section>

        <section class="surface p-5 sm:p-6" id="balances-section">
          <div class="flex items-center gap-3">
            <span class="section-icon"><.icon name="hero-scale" class="size-5" /></span><div>
              <h2 class="text-xl font-semibold text-slate-900">Balances</h2><p class="text-sm text-slate-500">
                Families share costs equally and settle as one group. Positive means they should receive money.
              </p>
            </div>
          </div>
          <div id="balance-list" class="mt-5 divide-y divide-slate-100">
            <p :if={@pooled == []} class="py-4 text-sm text-slate-500">
              Balances will appear when you add people.
            </p>
            <div
              :for={person <- @pooled}
              id={"balance-#{elem(person.key, 0)}-#{elem(person.key, 1)}"}
              class="flex items-center justify-between gap-3 py-3 text-sm"
            >
              <span class="font-medium text-slate-800">{person.name}
              <span :if={elem(person.key, 0) == :household} class="ml-1 text-xs text-slate-400">family</span></span>
              <.money
                amount_cents={person.amount_cents}
                currency={@event.currency}
                class={[
                  "font-semibold",
                  person.amount_cents > 0 && "text-emerald-700",
                  person.amount_cents < 0 && "text-rose-600",
                  person.amount_cents == 0 && "text-slate-400"
                ]}
              />
            </div>
          </div>
          <div class="mt-6 rounded-2xl bg-indigo-50 p-4">
            <h3 class="text-sm font-semibold text-indigo-900">To settle up</h3>
            <p :if={@suggestions == []} id="all-settled" class="mt-2 text-sm text-indigo-700">
              All settled for now.
            </p>
            <div id="suggestions" class="mt-2 space-y-2">
              <p :for={suggestion <- @suggestions} class="text-sm text-indigo-900">
                <strong>{suggestion.from}</strong> pays <strong>{suggestion.to}</strong>
                <strong><.money amount_cents={suggestion.amount_cents} currency={@event.currency} /></strong>
              </p>
            </div>
          </div>
        </section>

        <section class="surface p-6" id="expense-history">
          <h2 class="text-xl font-semibold text-slate-900">Expense history</h2>
          <p class="mt-1 text-sm text-slate-500">A clear record of what everyone contributed.</p>
          <div id="expenses" phx-update="stream" class="mt-5 divide-y divide-slate-100">
            <p id="expenses-empty" class="hidden py-5 text-sm text-slate-500 only:block">
              Nothing here yet. Your first expense will appear here.
            </p>
            <div
              :for={{id, expense} <- @streams.expenses}
              id={id}
              class="py-4"
            >
              <div class="flex flex-col justify-between gap-2 sm:flex-row sm:items-center">
                <div>
                  <p class="font-semibold text-slate-800">{expense.description}</p><p class="mt-1 text-xs text-slate-500">
                    Paid by {expense.payer.name} · Split between {expense.shares
                    |> Enum.sort_by(& &1.member_id)
                    |> Enum.map(& &1.member.name)
                    |> Enum.join(", ")}
                  </p>
                </div>
                <div class="flex shrink-0 items-center gap-4">
                  <.money
                    id={"expense-amount-#{expense.id}"}
                    amount_cents={expense.amount_cents}
                    currency={@event.currency}
                    class="font-semibold text-slate-900"
                  />
                  <button
                    id={"delete-expense-#{expense.id}"}
                    type="button"
                    phx-click="request_delete_expense"
                    phx-value-id={expense.id}
                    class="text-sm font-semibold text-rose-600 transition hover:text-rose-800"
                    aria-label={"Delete expense #{expense.description}"}
                  >Delete</button>
                </div>
              </div>
              <div
                :if={@pending_delete_expense_id == expense.id}
                id={"confirm-delete-expense-#{expense.id}"}
                class="mt-4 rounded-2xl border border-rose-200 bg-rose-50 p-4"
              >
                <p class="text-sm font-medium text-rose-900">
                  Delete this expense? This cannot be undone. Recorded payments will remain.
                </p>
                <div class="mt-3 flex flex-wrap gap-3">
                  <button
                    type="button"
                    phx-click="confirm_delete_expense"
                    phx-disable-with="Deleting…"
                    class="rounded-lg bg-rose-600 px-4 py-2 text-sm font-semibold text-white hover:bg-rose-700"
                  >Delete permanently</button>
                  <button
                    type="button"
                    phx-click="cancel_delete_expense"
                    class="rounded-lg border border-rose-200 bg-white px-4 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-50"
                  >Cancel</button>
                </div>
              </div>
            </div>
          </div>
        </section>
        <details :if={@repayments_count > 0} id="previous-payments" class="surface p-5 sm:p-6">
          <summary class="min-h-11 cursor-pointer text-sm font-semibold text-slate-700">
            Previous payments ({@repayments_count})
          </summary>
          <p class="mt-2 text-sm text-slate-500">
            These earlier payments are included in the balances above.
          </p>
          <div id="repayments" phx-update="stream" class="mt-3 divide-y divide-slate-100">
            <p :for={{id, payment} <- @streams.repayments} id={id} class="py-3 text-sm text-slate-700">
              {payment.from_member.name} → {payment.to_member.name} ·
              <strong><.money amount_cents={payment.amount_cents} currency={@event.currency} /></strong>
            </p>
          </div>
        </details>
      </div>
    </Layouts.app>
    """
  end
end
