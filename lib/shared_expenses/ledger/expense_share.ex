defmodule SharedExpenses.Ledger.ExpenseShare do
  use Ecto.Schema

  schema "expense_shares" do
    field :amount_cents, :integer
    belongs_to :expense, SharedExpenses.Ledger.Expense
    belongs_to :member, SharedExpenses.Ledger.Member
  end
end
