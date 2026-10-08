defmodule SharedExpenses.Ledger.Member do
  use Ecto.Schema
  import Ecto.Changeset

  schema "members" do
    field :name, :string
    belongs_to :event, SharedExpenses.Ledger.Event
    belongs_to :household, SharedExpenses.Ledger.Household
    timestamps(type: :utc_datetime)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
  end
end
