defmodule Sheetfolio.UrbanitaePending do
  @moduledoc """
  What Urbanitae told us by email that isn't in `urbanitae_transactions` yet.

  Nothing here is stored — it's derived on every read by subtracting the
  recorded transactions from the parsed emails. That's deliberate: a pending
  item disappears the moment the matching transaction is ingested, so there's
  no state to clear and no way for a stale flag to survive.

  It exists because the distribution emails never say how much *you* received
  (see `Sheetfolio.UrbanitaeParser`). Urbanitae tells us a payment happened,
  on what date, and whether it was rent/interest or the liquidation — enough
  to know a Movimientos screenshot is owed, not enough to write the row.

  Each item is `%{type, date, city, project, project_key, amount,
  repayment_kind}` where `type` is:

    * `:repayment`       — a distribution landed, no transaction recorded
    * `:investment`      — an investment we know the amount of, not recorded
    * `:unknown_project` — an email names a project missing from
                           `urbanitae_projects` (its type is unknown, so the
                           rollup can't place it)
  """

  alias Sheetfolio.UrbanitaeEmails
  alias Sheetfolio.UrbanitaeProjects
  alias Sheetfolio.UrbanitaeTransactions

  @doc "Pending items from the cached emails, most recent first."
  def list do
    list(
      UrbanitaeEmails.cached_events(),
      UrbanitaeTransactions.all(),
      UrbanitaeProjects.all()
    )
  end

  def list(events, transactions, projects) do
    events
    |> Enum.flat_map(&pending(&1, find_project(&1, projects), transactions))
    |> Enum.sort_by(& &1.date, :desc)
  end

  @doc """
  The `urbanitae_projects` document an email refers to. Distribution emails
  name the project without its city, so those resolve by name alone;
  investment and funding-close emails carry both.
  """
  def find_project(%{city: nil, project: name}, projects) do
    Enum.find(projects, &(&1["project"] == name))
  end

  def find_project(%{city: city, project: name}, projects) do
    key = UrbanitaeTransactions.project_key(city, name)
    Enum.find(projects, &(&1["project_key"] == key))
  end

  defp pending(event, nil, _transactions), do: [item(:unknown_project, event, nil)]

  defp pending(%{kind: :distribution} = event, project, transactions) do
    recorded? =
      Enum.any?(transactions, fn tx ->
        tx["project_key"] == project["project_key"] and tx["kind"] == "repayment" and
          tx["date"] == event.date
      end)

    if recorded?, do: [], else: [item(:repayment, event, project)]
  end

  defp pending(%{kind: :investment} = event, project, transactions) do
    recorded? =
      Enum.any?(transactions, fn tx ->
        tx["project_key"] == project["project_key"] and tx["kind"] == "investment" and
          tx["date"] == event.date and tx["amount"] == event.amount
      end)

    if recorded?, do: [], else: [item(:investment, event, project)]
  end

  # The funding-close mail restates the total invested, so it catches an
  # investment that was never screenshotted even though no confirmation mail
  # was sent — which is now the normal case, Urbanitae stopped sending them.
  # Its own date is the close, days off from the movement, so the item carries
  # the amount but the date is only a hint.
  defp pending(%{kind: :funded} = event, project, transactions) do
    invested =
      transactions
      |> Enum.filter(
        &(&1["project_key"] == project["project_key"] and &1["kind"] == "investment")
      )
      |> Enum.map(& &1["amount"])
      |> Enum.sum()

    if invested == event.amount, do: [], else: [item(:investment, event, project)]
  end

  defp item(type, event, project) do
    %{
      type: type,
      date: event.date,
      city: event.city || project["city"],
      project: event.project,
      project_key: project["project_key"],
      amount: Map.get(event, :amount),
      repayment_kind: Map.get(event, :repayment_kind)
    }
  end
end
