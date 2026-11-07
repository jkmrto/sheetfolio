defmodule Sheetfolio.UrbanitaeProjects do
  @moduledoc """
  Metadata for Urbanitae projects. One document per project, keyed by the
  same `project_key` used in `urbanitae_transactions`.

      { project_key: "valencia-perez-galdos",
        city: "Valencia",
        project: "Pérez Galdós",
        type: "alquiler",              # plusvalia | alquiler | prestamo
        status: "pending",             # optional: funded, investors not yet given entry
        forecast: %{...},              # optional: see put_forecast/2
        captured_at: <DateTime> }

  Type drives how repayments are interpreted in the rollup: `alquiler` and
  `prestamo` repayments default to yield (interest / rent), `plusvalia`
  repayments are typically the closure and lean toward principal.

  `status: "pending"` marks a project whose round closed but which Urbanitae
  hasn't yet listed under "Mis inversiones" (the investor entry is still
  being formalized). The money is committed, so it counts as outstanding;
  the page only shows a different pill. Clear it with `status: nil`.

  `forecast` is Urbanitae's payout estimate, copied by hand from the private
  area (see the urbanitae-ingest skill):

      %{"close_date" => "2027-05-14",        # expected final payout
        "first_close_date" => "2027-05-27",  # earliest estimate, kept across refreshes
        "extension_date" => "2027-11-14",    # optional: latest date the contract allows
        "to_receive" => 1274.4,              # gross, still to be paid out
        "recurring_amount" => 81.25,         # optional: instalments before the close,
        "recurring_months" => [1, 4, 7, 10], # part of to_receive
        "note" => "...",                     # what the project manager last reported
        "as_of" => "2026-11-07"}
  """

  @collection "urbanitae_projects"
  @types ~w(plusvalia alquiler prestamo)

  def types, do: @types

  def all do
    Mongo.find(:mongo, @collection, %{}) |> Enum.to_list()
  end

  def by_key(project_key) do
    Mongo.find_one(:mongo, @collection, %{"project_key" => project_key})
  end

  @doc """
  Upsert by project_key. Preserves captured_at on the initial insert;
  updates city/project/type/status on subsequent calls.
  """
  def upsert(%{project_key: pk} = doc) do
    now = DateTime.utc_now()
    fields = doc |> Map.take([:city, :project, :type, :status]) |> Map.put(:updated_at, now)

    {:ok, _} =
      Mongo.update_one(:mongo, @collection, %{"project_key" => pk}, %{
        "$set" => fields,
        "$setOnInsert" => %{"project_key" => pk, "captured_at" => now}
      }, upsert: true)

    :ok
  end

  @doc """
  Stores a project's payout forecast, keeping its earliest close date.
  """
  def put_forecast(project_key, forecast) do
    existing = by_key(project_key) || %{}

    {:ok, _} =
      Mongo.update_one(:mongo, @collection, %{"project_key" => project_key}, %{
        "$set" => %{
          "forecast" => merge_forecast(existing["forecast"], forecast),
          "updated_at" => DateTime.utc_now()
        }
      })

    :ok
  end

  def merge_forecast(nil, forecast) do
    Map.put_new(forecast, "first_close_date", forecast["close_date"])
  end

  def merge_forecast(%{"first_close_date" => first}, forecast) do
    Map.put(forecast, "first_close_date", first)
  end

  @doc """
  Projects that have a forecast, soonest payout first.
  """
  def forecasts do
    Mongo.find(:mongo, @collection, %{"forecast" => %{"$exists" => true}})
    |> Enum.sort_by(& &1["forecast"]["close_date"])
  end

  @doc """
  Whole calendar months the expected payout has moved since the first
  estimate. Positive means later.
  """
  def delay_months(%{"close_date" => close, "first_close_date" => first}) do
    month_index(close) - month_index(first)
  end

  @doc """
  Expected payouts per calendar month, from `today`'s month to the last payout,
  including the months with nothing due. A payout whose date has passed without
  being paid counts as due this month.

      [%{month: ~D[2026-11-01], amount: 7775.0, projects: [{"Julio Dinis", 6610.0}, ...]}, ...]
  """
  def monthly_payouts(projects, today) do
    current = Date.beginning_of_month(today)
    by_month = projects |> Enum.flat_map(&payments(&1, current)) |> Enum.group_by(&elem(&1, 0))
    last = by_month |> Map.keys() |> Enum.max(Date, fn -> current end)

    current
    |> months_until(Date.shift(last, month: 1))
    |> Enum.map(&month_row(&1, Map.get(by_month, &1, [])))
  end

  defp payments(%{"project" => name, "forecast" => forecast}, current) do
    close = forecast["close_date"] |> Date.from_iso8601!() |> Date.beginning_of_month()
    close = Enum.max([close, current], Date)
    instalments = instalments(forecast, current, close)
    paid = instalments |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    [{close, forecast["to_receive"] - paid} | instalments]
    |> Enum.map(fn {month, amount} -> {month, name, amount} end)
  end

  defp instalments(%{"recurring_amount" => amount, "recurring_months" => months}, current, close) do
    for month <- months_until(current, close), month.month in months, do: {month, amount}
  end

  defp instalments(_forecast, _current, _close), do: []

  defp months_until(from, to) do
    from
    |> Stream.iterate(&Date.shift(&1, month: 1))
    |> Enum.take_while(&(Date.compare(&1, to) == :lt))
  end

  defp month_row(month, payments) do
    projects = Enum.map(payments, fn {_month, name, amount} -> {name, Float.round(amount / 1, 2)} end)
    total = projects |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    %{month: month, amount: Float.round(total / 1, 2), projects: projects}
  end

  defp month_index(iso_date) do
    date = Date.from_iso8601!(iso_date)
    date.year * 12 + date.month
  end

  @doc """
  Returns `%{project_key => type_string}` for fast lookup during rollup.
  """
  def types_by_key do
    all()
    |> Enum.reduce(%{}, fn doc, acc -> Map.put(acc, doc["project_key"], doc["type"]) end)
  end

  @doc """
  Keys of the projects flagged `status: "pending"`.
  """
  def pending_keys do
    Mongo.find(:mongo, @collection, %{"status" => "pending"}, projection: %{project_key: 1})
    |> MapSet.new(& &1["project_key"])
  end
end
