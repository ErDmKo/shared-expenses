defmodule SharedExpenses.Repo.Migrations.AddSubmissionKeys do
  use Ecto.Migration

  def change do
    alter table(:expenses) do
      add :submission_key, :string
    end

    create unique_index(:expenses, [:event_id, :submission_key])

    alter table(:repayments) do
      add :submission_key, :string
    end

    create unique_index(:repayments, [:event_id, :submission_key])
  end
end
