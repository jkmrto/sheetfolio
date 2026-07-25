defmodule Sheetfolio.WiseExpenses do
  @moduledoc """
  Monthly Wise spending per category, using Wise's native activity categories.
  The activities list endpoint carries no category, so each activity's detail
  is fetched once and cached in Mongo; a cached activity is refetched when its
  listed status changes (e.g. PENDING -> COMPLETED). Incoming amounts and
  activities Wise excludes from insights (own-account transfers, investments)
  are ignored.
  """

  alias Sheetfolio.WiseClient

  @collection "wise_activities"
  @since ~D[2024-01-01]

  # Bump to force a full detail refetch on next sync (docs store their version).
  @schema_version 2

  @labels %{
    "GROCERIES" => "Groceries",
    "EATING_OUT" => "Eating out",
    "BILLS" => "Bills",
    "HOUSING" => "Housing",
    "SHOPPING" => "Shopping",
    "TRANSPORT" => "Transport",
    "TRIPS" => "Trips",
    "FAMILY" => "Family",
    "PERSONAL_CARE" => "Personal care",
    "ENTERTAINMENT" => "Entertainment"
  }

  @colors %{
    "Groceries" => "#2a78d6",
    "Eating out" => "#1baf7a",
    "Bills" => "#eda100",
    "Housing" => "#008300",
    "Shopping" => "#4a3aa7",
    "Transport" => "#e34948",
    "Trips" => "#e87ba4",
    "Family" => "#eb6834",
    "Personal care" => "#0aa2c0",
    "Entertainment" => "#9333ea",
    "Other" => "#9c8400"
  }

  def categories do
    [
      "Groceries",
      "Eating out",
      "Bills",
      "Housing",
      "Shopping",
      "Transport",
      "Trips",
      "Family",
      "Personal care",
      "Entertainment",
      "Other"
    ]
  end

  def color(category), do: @colors[category]

  @doc "All spending activities, most recent first."
  def list do
    Mongo.find(:mongo, @collection, %{status: "COMPLETED", excluded: false, positive: false}, sort: %{date: -1})
    |> Enum.map(fn doc ->
      %{
        date: String.slice(doc["date"] || "", 0, 10),
        title: doc["title"],
        note: doc["note"] || "",
        category: Map.get(@labels, doc["category"], "Other"),
        amount: doc["amount"]
      }
    end)
  end

  def years do
    Enum.map(Date.utc_today().year..@since.year//-1, &Integer.to_string/1)
  end

  @doc """
  Returns `{months, totals}`: the sorted list of month ISO dates since 2024 and
  a map of `%{{month, category} => total_eur}`.
  """
  def monthly_by_category do
    sync()

    totals =
      Mongo.find(:mongo, @collection, %{status: "COMPLETED", excluded: false, positive: false})
      |> Enum.group_by(&{&1["month"], Map.get(@labels, &1["category"], "Other")}, & &1["amount"])
      |> Map.new(fn {key, amounts} -> {key, amounts |> Enum.sum() |> Float.round(2)} end)

    {months(), totals}
  end

  defp sync do
    {:ok, [profile | _]} = WiseClient.profiles()
    since = DateTime.new!(@since, ~T[00:00:00], "Etc/UTC")
    {:ok, activities} = WiseClient.activities(profile["id"], since)

    known =
      Mongo.find(:mongo, @collection, %{}, projection: %{status: 1, v: 1})
      |> Map.new(&{&1["_id"], {&1["status"], &1["v"]}})

    activities
    |> Enum.reject(&(known[&1["id"]] == {&1["status"], @schema_version}))
    |> Task.async_stream(&store(profile["id"], &1["id"]), max_concurrency: 10, timeout: 60_000)
    |> Stream.run()
  end

  defp store(profile_id, activity_id) do
    {:ok, detail} = WiseClient.activity(profile_id, activity_id)

    # Activity details have no createdOn; scheduled ones also lack visibleOn.
    date = detail["visibleOn"] || detail["finishedOn"] || detail["willStartOn"] || ""

    doc = %{
      status: detail["status"],
      type: detail["type"],
      category: detail["category"],
      title: String.replace(detail["title"], ~r/<[^>]*>/, ""),
      note: note(detail),
      date: date,
      month: String.slice(date, 0, 7) <> "-01",
      amount: amount_eur(detail),
      positive: String.contains?(detail["primaryAmount"], "<positive>"),
      excluded: detail["isExcludedFromInsights"] == true,
      v: @schema_version
    }

    {:ok, _} = Mongo.update_one(:mongo, @collection, %{_id: activity_id}, %{"$set" => doc}, upsert: true)
  end

  defp months do
    Date.utc_today()
    |> Date.beginning_of_month()
    |> Stream.iterate(&Date.shift(&1, month: -1))
    |> Enum.take_while(&(Date.compare(&1, @since) != :lt))
    |> Enum.reverse()
    |> Enum.map(&Date.to_iso8601/1)
  end

  # The user-entered reference of a bank transfer ("Gym julio", ...).
  defp note(%{"type" => "TRANSFER", "resource" => %{"id" => transfer_id}}) do
    case WiseClient.transfer(transfer_id) do
      {:ok, %{"reference" => reference}} when is_binary(reference) -> reference
      _ -> ""
    end
  end

  defp note(_detail), do: ""

  defp amount_eur(activity) do
    [activity["primaryAmount"], activity["secondaryAmount"]]
    |> Enum.find_value(0.0, fn amount ->
      case Regex.run(~r/^([\d,.]+) EUR$/, amount) do
        [_, number] -> number |> String.replace(",", "") |> Float.parse() |> elem(0)
        nil -> nil
      end
    end)
  end
end
