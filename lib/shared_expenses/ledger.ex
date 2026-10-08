defmodule SharedExpenses.Ledger do
  @moduledoc "Events, people and the financial entries belonging to them."
  import Ecto.Query

  alias Ecto.Changeset
  alias SharedExpenses.{Money, Repo}

  alias SharedExpenses.Ledger.{
    Calculation,
    Event,
    Expense,
    ExpenseShare,
    Household,
    Member,
    Repayment
  }

  def get_event!(slug), do: Repo.get_by!(Event, slug: slug)
  def get_event(slug), do: Repo.get_by(Event, slug: slug)

  def create_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Changeset.put_change(
      :slug,
      Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    )
    |> Repo.insert()
  end

  def update_cover(%Event{} = event, filename) do
    result = event |> Changeset.change(cover_filename: filename) |> Repo.update()
    notify(result, event)
  end

  def create_household(%Event{} = event, attrs) do
    result = %Household{event_id: event.id} |> Household.changeset(attrs) |> Repo.insert()
    notify(result, event)
  end

  def delete_household(%Event{} = event, household_id) do
    with id when not is_nil(id) <- parse_id(household_id) do
      result =
        Repo.transaction(fn ->
          household = Repo.get_by(Household, id: id, event_id: event.id)
          if is_nil(household), do: Repo.rollback(:not_found)

          Repo.update_all(
            from(member in Member,
              where: member.household_id == ^id and member.event_id == ^event.id
            ),
            set: [household_id: nil]
          )

          Repo.delete!(household)
          :deleted
        end)

      notify(result, event)
    else
      _ -> {:error, :not_found}
    end
  end

  def create_member(%Event{} = event, attrs) do
    household_id = parse_id(Map.get(attrs, "household_id"))
    changeset = %Member{event_id: event.id} |> Member.changeset(attrs)

    changeset =
      if Map.get(attrs, "household_id") in [nil, ""] or
           (household_id && Repo.get_by(Household, id: household_id, event_id: event.id)) do
        Changeset.put_change(changeset, :household_id, household_id)
      else
        Changeset.add_error(changeset, :household_id, "select a family in this event")
      end

    notify(Repo.insert(changeset), event)
  end

  def delete_member(%Event{} = event, member_id) do
    with id when not is_nil(id) <- parse_id(member_id) do
      member_query =
        from member in Member, where: member.id == ^id and member.event_id == ^event.id

      unused_member_query =
        from member in member_query,
          where: member.id not in subquery(from expense in Expense, select: expense.payer_id),
          where: member.id not in subquery(from share in ExpenseShare, select: share.member_id),
          where:
            member.id not in subquery(
              from repayment in Repayment, select: repayment.from_member_id
            ),
          where:
            member.id not in subquery(from repayment in Repayment, select: repayment.to_member_id)

      case Repo.delete_all(unused_member_query) do
        {1, _} -> notify({:ok, :deleted}, event)
        {0, _} -> {:error, if(Repo.exists?(member_query), do: :in_use, else: :not_found)}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def update_member_household(%Event{} = event, member_id, household_id) do
    with id when not is_nil(id) <- parse_id(member_id),
         %Member{} = member <- Repo.get_by(Member, id: id, event_id: event.id),
         {:ok, household_id} <- find_household(event, household_id) do
      notify(member |> Changeset.change(household_id: household_id) |> Repo.update(), event)
    else
      _ -> {:error, :invalid_membership}
    end
  end

  def create_expense(%Event{} = event, attrs) do
    changeset = %Expense{event_id: event.id} |> Expense.changeset(attrs)
    {changeset, amount} = validate_amount(changeset, Map.get(attrs, "amount"))
    {changeset, payer} = validate_member(changeset, event, :payer_id, Map.get(attrs, "payer_id"))

    ids =
      case Map.get(attrs, "participant_ids", []) do
        list when is_list(list) -> Enum.reject(list, &(&1 in ["", "false", nil]))
        _ -> []
      end

    parsed = Enum.map(ids, &parse_id/1)
    unique_ids = Enum.uniq(parsed)

    selected =
      if unique_ids != [] and nil not in unique_ids do
        Repo.all(from m in Member, where: m.event_id == ^event.id and m.id in ^unique_ids)
      else
        []
      end

    changeset =
      if ids == [] or length(parsed) != length(unique_ids) or length(selected) != length(ids) do
        Changeset.add_error(
          changeset,
          :participant_ids,
          "select one or more people in this event"
        )
      else
        changeset
      end

    if changeset.valid? do
      key = submission_key(attrs)

      {:ok, expense} =
        Repo.transaction(fn ->
          case Repo.get_by(Expense, event_id: event.id, submission_key: key) do
            %Expense{} = expense ->
              expense

            nil ->
              expense =
                changeset
                |> Changeset.put_change(:amount_cents, amount)
                |> Changeset.put_change(:payer_id, payer.id)
                |> Changeset.put_change(:submission_key, key)
                |> Repo.insert!()

              Enum.each(Calculation.expense_shares(amount, selected), fn {id, share} ->
                Repo.insert!(%ExpenseShare{
                  expense_id: expense.id,
                  member_id: id,
                  amount_cents: share
                })
              end)

              expense
          end
        end)

      notify({:ok, expense}, event)
    else
      {:error, changeset}
    end
  end

  def delete_expense(%Event{} = event, expense_id) do
    case parse_id(expense_id) do
      nil ->
        {:error, :not_found}

      id ->
        case Repo.delete_all(
               from expense in Expense,
                 where: expense.id == ^id and expense.event_id == ^event.id
             ) do
          {1, _} -> notify({:ok, :deleted}, event)
          {0, _} -> {:error, :not_found}
        end
    end
  end

  def create_repayment(%Event{} = event, attrs) do
    changeset = Changeset.change(%Repayment{event_id: event.id})
    {changeset, amount} = validate_amount(changeset, Map.get(attrs, "amount"))

    {changeset, from} =
      validate_member(changeset, event, :from_member_id, Map.get(attrs, "from_member_id"))

    {changeset, to} =
      validate_member(changeset, event, :to_member_id, Map.get(attrs, "to_member_id"))

    changeset =
      if from && to && from.id == to.id,
        do: Changeset.add_error(changeset, :to_member_id, "choose another person"),
        else: changeset

    if changeset.valid? do
      key = submission_key(attrs)

      result =
        Repo.transaction(fn ->
          Repo.get_by(Repayment, event_id: event.id, submission_key: key) ||
            Repo.insert!(%Repayment{
              event_id: event.id,
              from_member_id: from.id,
              to_member_id: to.id,
              amount_cents: amount,
              submission_key: key
            })
        end)

      notify(result, event)
    else
      {:error, changeset}
    end
  end

  def snapshot(%Event{} = event) do
    {:ok, snapshot} =
      Repo.transaction(fn ->
        event
        |> Repo.reload!()
        |> Repo.preload([
          :households,
          :members,
          expenses: [:payer, shares: :member],
          repayments: [:from_member, :to_member]
        ])
      end)

    snapshot
  end

  def subscribe(%Event{} = event),
    do: Phoenix.PubSub.subscribe(SharedExpenses.PubSub, "event:#{event.id}")

  defp notify({:ok, _} = result, event) do
    Phoenix.PubSub.broadcast(SharedExpenses.PubSub, "event:#{event.id}", :ledger_changed)
    result
  end

  defp notify(result, _event), do: result

  defp validate_amount(changeset, raw) do
    case Money.parse(raw) do
      {:ok, amount} -> {changeset, amount}
      {:error, error} -> {Changeset.add_error(changeset, :amount, error), nil}
    end
  end

  defp validate_member(changeset, event, field, raw) do
    member = if id = parse_id(raw), do: Repo.get_by(Member, id: id, event_id: event.id)

    if member,
      do: {changeset, member},
      else: {Changeset.add_error(changeset, field, "select a person in this event"), nil}
  end

  defp find_household(_event, raw) when raw in [nil, ""], do: {:ok, nil}

  defp find_household(event, raw) do
    if id = parse_id(raw) do
      case Repo.get_by(Household, id: id, event_id: event.id) do
        %Household{} -> {:ok, id}
        nil -> {:error, :invalid_membership}
      end
    else
      {:error, :invalid_membership}
    end
  end

  defp parse_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807,
    do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 and value <= 9_223_372_036_854_775_807 -> value
      _ -> nil
    end
  end

  defp parse_id(_), do: nil

  defp submission_key(%{"submission_key" => key}) when is_binary(key) and byte_size(key) == 32,
    do: key

  defp submission_key(_), do: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
end
