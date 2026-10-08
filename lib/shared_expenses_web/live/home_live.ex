defmodule SharedExpensesWeb.HomeLive do
  use SharedExpensesWeb, :live_view

  alias SharedExpenses.Ledger
  alias SharedExpenses.Ledger.Event

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Start an event")
     |> assign(:form, to_form(Event.changeset(%Event{}, %{})))}
  end

  @impl true
  def handle_event("validate", %{"event" => params}, socket) do
    changeset = %Event{} |> Event.changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("create", %{"event" => params}, socket) do
    case Ledger.create_event(params) do
      {:ok, event} ->
        {:noreply, push_navigate(socket, to: ~p"/e/#{event.slug}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(%{changeset | action: :insert}))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-5xl py-12 sm:py-20">
        <div class="grid items-center gap-12 lg:grid-cols-[1.1fr_.9fr] lg:gap-20">
          <section class="space-y-7">
            <div class="eyebrow">SHARED MOMENTS, SORTED MONEY</div>
            <h1 class="max-w-xl text-5xl font-semibold leading-[1.08] tracking-tight text-slate-900 sm:text-6xl">
              Make memories.<br /><span class="text-indigo-600">Keep the math simple.</span>
            </h1>
            <p class="max-w-lg text-lg leading-relaxed text-slate-600">
              A place for trips, dinners and everything in between. Add people, track what everyone spent, and see exactly how to settle up.
            </p>
            <div class="flex flex-wrap gap-3 text-sm text-slate-600">
              <span class="pill"><.icon name="hero-user-group" class="size-4" /> Friends & families</span>
              <span class="pill"><.icon name="hero-calculator" class="size-4" /> Fair splits</span>
              <span class="pill"><.icon name="hero-link" class="size-4" /> Shareable link</span>
            </div>
          </section>
          <section class="surface p-7 sm:p-9" aria-label="Create an event">
            <div class="mb-7 flex size-12 items-center justify-center rounded-2xl bg-indigo-50 text-indigo-600">
              <.icon name="hero-sparkles" class="size-6" />
            </div>
            <h2 class="text-2xl font-semibold tracking-tight text-slate-900">Start a new event</h2>
            <p class="mt-2 text-sm leading-relaxed text-slate-500">
              Give it a name. Add your people and expenses next.
            </p>
            <.form
              for={@form}
              id="event-form"
              phx-change="validate"
              phx-submit="create"
              class="mt-7 space-y-4"
            >
              <.input
                field={@form[:title]}
                label="Event name"
                placeholder="Summer in Lisbon"
                required
                maxlength="120"
              />
              <.input
                field={@form[:currency]}
                type="select"
                label="Currency"
                options={["Euro (EUR)": "EUR", "US dollar (USD)": "USD", "Russian ruble (RUB)": "RUB"]}
              />
              <button class="primary-button w-full" type="submit">Create event
              <.icon name="hero-arrow-right" class="size-5" /></button>
            </.form>
            <p class="mt-5 text-xs leading-relaxed text-slate-400">
              No account needed. Save the private event link to come back and share it with your friends. Anyone with the link can edit.
            </p>
          </section>
        </div>
        <div class="mt-24 grid gap-4 border-t border-slate-200 pt-9 sm:grid-cols-3">
          <div>
            <span class="step-number">01</span><h3 class="mt-3 font-semibold">Create your space</h3><p class="mt-1 text-sm text-slate-500">
              One event for each trip or occasion.
            </p>
          </div>
          <div>
            <span class="step-number">02</span><h3 class="mt-3 font-semibold">Add the details</h3><p class="mt-1 text-sm text-slate-500">
              Who paid, for what, and who joined in.
            </p>
          </div>
          <div>
            <span class="step-number">03</span><h3 class="mt-3 font-semibold">Settle with ease</h3><p class="mt-1 text-sm text-slate-500">
              Simple balances and suggested payments.
            </p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
