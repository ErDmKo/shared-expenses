defmodule SharedExpensesWeb.EventComponents do
  use Phoenix.Component
  use SharedExpensesWeb, :verified_routes

  @doc "Keeps event page spacing and the action row consistent when switching sections."
  slot :actions, required: true
  slot :inner_block, required: true

  def event_page(assigns) do
    ~H"""
    <div id="event-page" class="space-y-5 py-6 sm:space-y-7 sm:py-8">
      <div id="event-page-actions" class="flex min-h-11 items-center justify-between gap-3">
        {render_slot(@actions)}
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "Renders the page badge and event title with identical typography on every event page."
  attr :id, :string, required: true
  attr :event, :map, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  def event_heading(assigns) do
    ~H"""
    <div id={@id} class="max-w-xl">
      <span
        id={"#{@id}-badge"}
        class="rounded-full border border-white/35 bg-white/15 px-3 py-1 text-xs font-semibold uppercase tracking-widest"
      >
        {@label}
      </span>
      <h1
        id={"#{@id}-title"}
        class="mt-3 break-words text-2xl font-semibold tracking-tight sm:text-4xl"
      >
        {@event.title}
      </h1>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "Renders the shared event cover with space reserved for expense details on both pages."
  attr :id, :string, required: true
  attr :event, :map, required: true
  attr :preview_entry, :any, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def event_hero(assigns) do
    ~H"""
    <section
      id={@id}
      class={[
        "relative min-h-[15rem] overflow-hidden rounded-3xl bg-gradient-to-br from-indigo-800 via-indigo-600 to-sky-500 p-4 text-white sm:min-h-[16.5rem] sm:p-6",
        @class
      ]}
      style={
        if @event.cover_filename,
          do:
            "background-image: linear-gradient(90deg, rgba(18,26,59,.86), rgba(32,45,85,.42)), url('#{~p"/e/#{@event.slug}/cover?#{[v: @event.cover_filename]}"}'); background-position: center; background-size: cover;",
          else: ""
      }
    >
      <div
        :if={@preview_entry}
        id={"#{@id}-preview"}
        class="pointer-events-none absolute inset-0"
        aria-hidden="true"
      >
        <.live_img_preview
          id={"#{@id}-cover-preview-#{@preview_entry.ref}"}
          entry={@preview_entry}
          class="absolute inset-0 h-full w-full object-cover"
          alt=""
        />
        <div
          class="absolute inset-0"
          style="background-image: linear-gradient(90deg, rgba(18,26,59,.86), rgba(32,45,85,.42));"
        >
        </div>
      </div>
      <div class="relative z-10">{render_slot(@inner_block)}</div>
    </section>
    """
  end
end
