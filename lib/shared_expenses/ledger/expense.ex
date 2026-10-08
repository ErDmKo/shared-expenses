defmodule SharedExpenses.Ledger.Expense do
  use Ecto.Schema
  import Ecto.Changeset

  schema "expenses" do
    field :description, :string
    field :amount_cents, :integer
    field :submission_key, :string
    belongs_to :event, SharedExpenses.Ledger.Event
    belongs_to :payer, SharedExpenses.Ledger.Member
    has_many :shares, SharedExpenses.Ledger.ExpenseShare
    timestamps(type: :utc_datetime)
  end

  def changeset(expense, attrs) do
    expense
    |> cast(attrs, [:description])
    |> update_change(:description, &String.trim/1)
    |> validate_required([:description])
    |> validate_length(:description, max: 200)
  end
end
