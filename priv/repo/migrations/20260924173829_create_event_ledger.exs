defmodule SharedExpenses.Repo.Migrations.CreateEventLedger do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :title, :string, null: false
      add :currency, :string, null: false, default: "EUR"
      add :slug, :string, null: false
      add :cover_filename, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:events, [:slug])

    create table(:households) do
      add :event_id, references(:events, on_delete: :restrict), null: false
      add :name, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:households, [:event_id])

    create table(:members) do
      add :event_id, references(:events, on_delete: :restrict), null: false
      add :household_id, references(:households, on_delete: :restrict)
      add :name, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:members, [:event_id])
    create index(:members, [:household_id])

    create table(:expenses) do
      add :event_id, references(:events, on_delete: :restrict), null: false
      add :payer_id, references(:members, on_delete: :restrict), null: false
      add :description, :string, null: false

      add :amount_cents, :integer,
        null: false,
        check: %{name: "positive_expense", expr: "amount_cents > 0"}

      timestamps(type: :utc_datetime)
    end

    create index(:expenses, [:event_id])

    create table(:expense_shares) do
      add :expense_id, references(:expenses, on_delete: :delete_all), null: false
      add :member_id, references(:members, on_delete: :restrict), null: false

      add :amount_cents, :integer,
        null: false,
        check: %{name: "nonnegative_share", expr: "amount_cents >= 0"}
    end

    create unique_index(:expense_shares, [:expense_id, :member_id])
    create index(:expense_shares, [:member_id])

    create table(:repayments) do
      add :event_id, references(:events, on_delete: :restrict), null: false
      add :from_member_id, references(:members, on_delete: :restrict), null: false
      add :to_member_id, references(:members, on_delete: :restrict), null: false

      add :amount_cents, :integer,
        null: false,
        check: %{
          name: "positive_repayment",
          expr: "amount_cents > 0 AND from_member_id != to_member_id"
        }

      timestamps(type: :utc_datetime)
    end

    create index(:repayments, [:event_id])
  end
end
