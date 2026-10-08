defmodule SharedExpenses.Ledger.Event do
  use Ecto.Schema
  import Ecto.Changeset

  schema "events" do
    field :title, :string
    field :currency, :string, default: "EUR"
    field :slug, :string
    field :cover_filename, :string
    has_many :members, SharedExpenses.Ledger.Member
    has_many :households, SharedExpenses.Ledger.Household
    has_many :expenses, SharedExpenses.Ledger.Expense
    has_many :repayments, SharedExpenses.Ledger.Repayment
    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:title, :currency])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title, :currency])
    |> validate_length(:title, min: 2, max: 120)
    |> validate_inclusion(:currency, ~w(EUR USD RUB))
    |> unique_constraint(:slug)
  end
end
