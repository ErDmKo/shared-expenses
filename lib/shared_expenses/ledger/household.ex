defmodule SharedExpenses.Ledger.Household do
  use Ecto.Schema
  import Ecto.Changeset

  schema "households" do
    field :name, :string
    belongs_to :event, SharedExpenses.Ledger.Event
    has_many :members, SharedExpenses.Ledger.Member
    timestamps(type: :utc_datetime)
  end

  def changeset(household, attrs) do
    household
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
  end
end
