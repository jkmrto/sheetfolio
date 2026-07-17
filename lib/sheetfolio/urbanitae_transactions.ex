defmodule Sheetfolio.UrbanitaeTransactions do
  @moduledoc """
  Per-transaction Urbanitae history. Urbanitae has no API, so INVERSIÓN and
  REEMBOLSO rows are extracted from Movimientos screenshots via the
  `urbanitae-ingest` skill. INGRESO / TRANSFERENCIA a cuenta (wallet ↔ bank)
  are not tracked here.

  Each document:

      { date: "2024-05-23",         # ISO date the movement happened
        kind: "investment" | "repayment",
        city: "Valencia",
        project: "Montesano",
        project_key: "valencia-montesano",
        amount: 10000.00,           # always positive, sign implied by kind
        raw_title: "Inversión en el proyecto Valencia | Proyecto Montesano",
        captured_at: <DateTime> }   # when we recorded it
  """

  @collection "urbanitae_transactions"

  def all do
    Mongo.find(:mongo, @collection, %{}, sort: %{date: -1, captured_at: -1})
    |> Enum.to_list()
  end

  def insert_many([]), do: :ok

  def insert_many(docs) do
    {:ok, _} = Mongo.insert_many(:mongo, @collection, docs)
    :ok
  end

  @doc """
  Look up an existing doc with the same natural key
  (date + kind + project_key + amount). Used by the ingest skill to
  distinguish new rows from duplicates.
  """
  def find_matching(%{date: date, kind: kind, project_key: pk, amount: amount}) do
    Mongo.find_one(:mongo, @collection, %{
      "date" => date,
      "kind" => kind,
      "project_key" => pk,
      "amount" => amount
    })
  end

  @doc """
  Turn "Valencia" + "Montesano" into "valencia-montesano".
  """
  def project_key(city, project) do
    Enum.map_join([city, project], "-", &slugify/1)
  end

  @doc """
  Group transactions by project and compute invested / returned / outstanding /
  net_pnl. A project is considered closed once returned >= invested.
  """
  def rollup_by_project(transactions) do
    transactions
    |> Enum.group_by(&{&1["project_key"], &1["city"], &1["project"]})
    |> Enum.map(fn {{key, city, project}, txs} ->
      invested = sum_amount(txs, "investment")
      returned = sum_amount(txs, "repayment")
      dates = Enum.map(txs, & &1["date"])

      %{
        project_key: key,
        city: city,
        project: project,
        invested: round2(invested),
        returned: round2(returned),
        outstanding: round2(invested - returned),
        net_pnl: round2(returned - invested),
        status: if(returned >= invested and invested > 0, do: "closed", else: "active"),
        first_date: Enum.min(dates),
        last_date: Enum.max(dates),
        tx_count: length(txs)
      }
    end)
    |> Enum.sort_by(&{&1.status, -&1.invested})
  end

  defp sum_amount(txs, kind) do
    txs
    |> Enum.filter(&(&1["kind"] == kind))
    |> Enum.reduce(0.0, &(&1["amount"] + &2))
  end

  defp round2(number), do: Float.round(number * 1.0, 2)

  defp slugify(string) do
    string
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9\s-]/u, "")
    |> String.trim()
    |> String.replace(~r/[\s-]+/, "-")
  end
end
