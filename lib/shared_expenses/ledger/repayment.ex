defmodule SharedExpenses.Ledger.Repayment do
  use Ecto.Schema

  schema "repayments" do
    field :amount_cents, :integer
    field :submission_key, :string
    belongs_to :event, SharedExpenses.Ledger.Event
    belongs_to :from_member, SharedExpenses.Ledger.Member
    belongs_to :to_member, SharedExpenses.Ledger.Member
    timestamps(type: :utc_datetime)
  end
end
