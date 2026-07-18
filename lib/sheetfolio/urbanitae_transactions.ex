defmodule Sheetfolio.UrbanitaeTransactions do
  @moduledoc """
  Per-transaction Urbanitae history. Urbanitae has no API, so INVERSIÓN and
  REEMBOLSO rows are extracted from Movimientos screenshots via the
  `urbanitae-ingest` skill. INGRESO / TRANSFERENCIA a cuenta (wallet ↔ bank)
  are not tracked here.

  Each document:

      { date: "2024-05-23",         # ISO date the movement happened
        kind: "investment" | "repayment",
        # For repayments only:
        repayment_kind: "yield" | "principal",
        city: "Valencia",
        project: "Montesano",
        project_key: "valencia-montesano",
        amount: 10000.00,           # always positive, sign implied by kind
        raw_title: "Inversión en el proyecto Valencia | Proyecto Montesano",
        captured_at: <DateTime> }   # when we recorded it

  `repayment_kind` matters because Urbanitae doesn't split principal from
  yield in the movement list. Most REEMBOLSO on Alquiler/Préstamo projects
  are yield (rent / interest); principal comes back at closure. Getting this
  right is what makes `outstanding` match Urbanitae's "Invertido".
  """

  alias Sheetfolio.UrbanitaeProjects

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
  Update a transaction's repayment_kind by natural key.
  """
  def set_repayment_kind(%{date: date, project_key: pk, amount: amount}, kind)
      when kind in ["yield", "principal"] do
    {:ok, _} =
      Mongo.update_one(
        :mongo,
        @collection,
        %{"date" => date, "kind" => "repayment", "project_key" => pk, "amount" => amount},
        %{"$set" => %{"repayment_kind" => kind}}
      )

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
  Group transactions by project and compute derived fields matching
  Urbanitae's semantics. A project is `closed` once all principal has been
  returned; while active, repayments accumulate as yield_returned and do
  NOT reduce `outstanding` (which is what Urbanitae calls Invertido).

      %{project_key, city, project, type,
        invested, principal_returned, yield_returned, returned_total,
        outstanding, net_pnl, status, first_date, last_date, tx_count}
  """
  def rollup_by_project(transactions, types_by_key \\ nil) do
    types_by_key = types_by_key || UrbanitaeProjects.types_by_key()

    transactions
    |> Enum.group_by(&{&1["project_key"], &1["city"], &1["project"]})
    |> Enum.map(fn {{key, city, project}, txs} ->
      invested = sum_amount(txs, &(&1["kind"] == "investment"))
      principal_returned = sum_amount(txs, &principal_repayment?/1)
      yield_returned = sum_amount(txs, &yield_repayment?/1)
      returned_total = principal_returned + yield_returned
      status = if principal_returned >= invested and invested > 0, do: "closed", else: "active"
      dates = Enum.map(txs, & &1["date"])

      %{
        project_key: key,
        city: city,
        project: project,
        type: Map.get(types_by_key, key),
        invested: round2(invested),
        principal_returned: round2(principal_returned),
        yield_returned: round2(yield_returned),
        returned_total: round2(returned_total),
        outstanding: outstanding(status, invested, principal_returned),
        net_pnl: round2(returned_total - invested),
        status: status,
        first_date: Enum.min(dates),
        last_date: Enum.max(dates),
        tx_count: length(txs)
      }
    end)
    |> Enum.sort_by(&{&1.status, -&1.invested})
  end

  @doc """
  Time series over the transaction history: one snapshot per event date,
  plus a final `today` point. Each snapshot has:

      %{date: "2024-05-23", outstanding: 10000.00, earnings: 0.00}

  Outstanding sums per-project (invested − principal_returned), floored at 0.
  Earnings accumulates: every yield repayment adds its full amount; every
  principal repayment adds the surplus over what remained outstanding for
  that project (i.e. the closure gain).
  """
  def time_series(transactions) do
    sorted = Enum.sort_by(transactions, & &1["date"])

    {points, state} =
      Enum.reduce(sorted, {[], %{}}, fn tx, {points, per_project} ->
        per_project = apply_transaction(per_project, tx)
        {outstanding, earnings} = totals_from(per_project)
        point = %{date: tx["date"], outstanding: round2(outstanding), earnings: round2(earnings)}
        {[point | points], per_project}
      end)

    today = Date.utc_today() |> Date.to_iso8601()

    trailing =
      case state do
        state when map_size(state) == 0 ->
          []

        state ->
          {outstanding, earnings} = totals_from(state)
          [%{date: today, outstanding: round2(outstanding), earnings: round2(earnings)}]
      end

    points |> Enum.reverse() |> collapse_same_day() |> Kernel.++(trailing)
  end

  # One doc per date (drop earlier same-day points so we only emit the
  # end-of-day snapshot).
  defp collapse_same_day(points) do
    points
    |> Enum.reverse()
    |> Enum.uniq_by(& &1.date)
    |> Enum.reverse()
  end

  defp apply_transaction(state, %{"kind" => "investment", "project_key" => pk, "amount" => amount}) do
    Map.update(state, pk, %{invested: amount, principal_returned: 0.0, yield_returned: 0.0}, fn p ->
      %{p | invested: p.invested + amount}
    end)
  end

  defp apply_transaction(
         state,
         %{"kind" => "repayment", "project_key" => pk, "amount" => amount} = tx
       ) do
    project = Map.get(state, pk, %{invested: 0.0, principal_returned: 0.0, yield_returned: 0.0})

    project =
      case Map.get(tx, "repayment_kind") do
        "principal" -> %{project | principal_returned: project.principal_returned + amount}
        _ -> %{project | yield_returned: project.yield_returned + amount}
      end

    Map.put(state, pk, project)
  end

  defp totals_from(per_project) do
    Enum.reduce(per_project, {0.0, 0.0}, fn {_pk, p}, {outstanding, earnings} ->
      remaining = max(p.invested - p.principal_returned, 0.0)
      surplus = max(p.principal_returned - p.invested, 0.0)
      {outstanding + remaining, earnings + p.yield_returned + surplus}
    end)
  end

  defp outstanding("closed", _invested, _principal_returned), do: 0.0
  defp outstanding(_, invested, principal_returned), do: round2(invested - principal_returned)

  defp principal_repayment?(%{"kind" => "repayment", "repayment_kind" => "principal"}), do: true
  defp principal_repayment?(_), do: false

  defp yield_repayment?(%{"kind" => "repayment"} = tx),
    do: Map.get(tx, "repayment_kind") != "principal"

  defp yield_repayment?(_), do: false

  defp sum_amount(txs, filter_fn) do
    txs
    |> Enum.filter(filter_fn)
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
