defmodule SharedExpenses.Repo do
  use Ecto.Repo,
    otp_app: :shared_expenses,
    adapter: Ecto.Adapters.SQLite3
end
