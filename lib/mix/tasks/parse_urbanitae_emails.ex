defmodule Mix.Tasks.ParseUrbanitaeEmails do
  use Mix.Task

  alias Sheetfolio.UrbanitaeEmails
  alias Sheetfolio.UrbanitaeProjects
  alias Sheetfolio.UrbanitaeTransactions

  @shortdoc "Dry run: fetch and parse all Urbanitae emails, reconciled against Mongo"

  @moduledoc """
  Prints every event parseable from the Urbanitae inbox next to what
  `urbanitae_transactions` / `urbanitae_projects` already hold, so a missing
  screenshot ingest shows up as a `MISSING` row.

  Writes nothing: distribution emails don't state the amount received, so a
  repayment they reveal still has to be ingested from a Movimientos screenshot
  via the `urbanitae-ingest` skill.
  """

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("Fetching Urbanitae emails...\n")

    {:ok, {events, ignored}} = UrbanitaeEmails.fetch_all()

    projects = UrbanitaeProjects.all()
    transactions = UrbanitaeTransactions.all()

    Mix.shell().info("#{length(events)} transactional emails (#{ignored} marketing skipped)\n")

    annotated = Enum.map(events, &annotate(&1, projects, transactions))

    Enum.each(annotated, &Mix.shell().info(format_row(&1)))

    Mix.shell().info("\n" <> summary(annotated))
  end

  defp annotate(event, projects, transactions) do
    project = find_project(event, projects)
    Map.put(event, :status, status(event, project, transactions))
  end

  # Distribution emails name the project without its city, so those resolve by
  # name alone; investment and funded mails carry both.
  defp find_project(%{city: nil, project: name}, projects) do
    Enum.find(projects, &(&1["project"] == name))
  end

  defp find_project(%{city: city, project: name}, projects) do
    key = UrbanitaeTransactions.project_key(city, name)
    Enum.find(projects, &(&1["project_key"] == key))
  end

  defp status(_event, nil, _transactions), do: "✗ project not in urbanitae_projects"

  defp status(%{kind: :investment} = event, project, transactions) do
    match =
      Enum.find(transactions, fn tx ->
        tx["project_key"] == project["project_key"] and tx["kind"] == "investment" and
          tx["date"] == event.date and tx["amount"] == event.amount
      end)

    if match, do: "✓ recorded", else: "✗ MISSING investment in urbanitae_transactions"
  end

  # The funding-close mail restates the total invested, which is the one
  # independent check we have on the screenshot-entered amounts.
  defp status(%{kind: :funded} = event, project, transactions) do
    invested =
      transactions
      |> Enum.filter(
        &(&1["project_key"] == project["project_key"] and &1["kind"] == "investment")
      )
      |> Enum.map(& &1["amount"])
      |> Enum.sum()

    if invested == event.amount,
      do: "✓ invested #{money(invested)} matches",
      else: "✗ email says #{money(event.amount)}, recorded #{money(invested)}"
  end

  defp status(%{kind: :distribution} = event, project, transactions) do
    match =
      Enum.find(transactions, fn tx ->
        tx["project_key"] == project["project_key"] and tx["kind"] == "repayment" and
          tx["date"] == event.date
      end)

    repayment_status(match, event)
  end

  defp repayment_status(nil, _event), do: "✗ MISSING repayment in urbanitae_transactions"

  defp repayment_status(%{"repayment_kind" => kind} = tx, %{repayment_kind: kind}) do
    "✓ recorded #{money(tx["amount"])}"
  end

  defp repayment_status(tx, event) do
    "⚠ recorded #{money(tx["amount"])} as #{tx["repayment_kind"]}, email says #{event.repayment_kind}"
  end

  defp format_row(event) do
    [
      event.date,
      String.pad_trailing(to_string(event.kind), 13),
      String.pad_trailing(label(event), 32),
      String.pad_leading(detail(event), 12),
      " ",
      event.status
    ]
    |> Enum.join("  ")
  end

  defp label(%{city: nil, project: project}), do: project
  defp label(%{city: city, project: project}), do: "#{city} | #{project}"

  defp detail(%{kind: :distribution, repayment_kind: kind}), do: "[#{kind}]"
  defp detail(%{amount: amount}), do: money(amount)

  defp summary(events) do
    counts = Enum.frequencies_by(events, & &1.kind)
    missing = Enum.count(events, &String.starts_with?(&1.status, "✗"))

    "#{Map.get(counts, :investment, 0)} investments, " <>
      "#{Map.get(counts, :funded, 0)} funding closes, " <>
      "#{Map.get(counts, :distribution, 0)} distributions — #{missing} need attention."
  end

  defp money(amount), do: :erlang.float_to_binary(amount / 1, decimals: 2) <> " €"
end
