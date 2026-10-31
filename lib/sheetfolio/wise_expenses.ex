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

  @codes Map.new(@labels, fn {code, label} -> {label, code} end)

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
        id: doc["_id"],
        date: String.slice(doc["date"] || "", 0, 10),
        title: doc["title"],
        note: doc["note"] || "",
        category: Map.get(@labels, doc["category"], "Other"),
        uncategorized: is_nil(doc["category"]),
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
    stored_monthly_by_category()
  end

  @doc "`monthly_by_category/0` from what is already stored, without asking Wise."
  def stored_monthly_by_category do
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

    by_title = categorized_titles()

    activities
    |> Enum.reject(&(known[&1["id"]] == {&1["status"], @schema_version}))
    |> Task.async_stream(&store(profile["id"], &1, by_title), max_concurrency: 10, timeout: 60_000)
    |> Stream.run()

    fill_uncategorized()
  end

  @doc """
  Files an uncategorized activity under `label`, along with every other
  uncategorized one with the same title. Later activities from that merchant
  then inherit it through the title match in `to_doc/3`.
  """
  def categorize(id, label) when is_map_key(@codes, label) do
    case Mongo.find_one(:mongo, @collection, %{_id: id}) do
      nil -> :ok
      doc -> set_category(uncategorized_ids(title_key(doc["title"])), @codes[label])
    end
  end

  defp uncategorized_ids(key) do
    Mongo.find(:mongo, @collection, %{category: nil}, projection: %{title: 1})
    |> Enum.filter(&(title_key(&1["title"]) == key))
    |> Enum.map(& &1["_id"])
  end

  defp set_category(ids, code) do
    Mongo.update_many(:mongo, @collection, %{_id: %{"$in" => ids}}, %{"$set" => %{category: code}})
    :ok
  end

  @doc """
  The key two titles are matched on: Wise spells the same merchant with
  varying case and spacing ("Escuela infantil Sol y Luna" and "Escuela
  Infantil SolYLuna"), so only letters and digits count.
  """
  def title_key(nil), do: ""
  def title_key(title), do: title |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]/u, "")

  # Latest category and insights flag per title, for activities stored
  # without a detail.
  defp categorized_titles do
    Mongo.find(:mongo, @collection, %{category: %{"$ne" => nil}}, sort: %{date: 1}, projection: %{title: 1, category: 1, excluded: 1})
    |> Map.new(&{title_key(&1["title"]), %{category: &1["category"], excluded: &1["excluded"] == true}})
  end

  # An activity stored before its merchant had any categorized match gets one
  # as soon as a match exists, e.g. after a manual categorization.
  defp fill_uncategorized do
    by_title = categorized_titles()

    Mongo.find(:mongo, @collection, %{category: nil}, projection: %{title: 1})
    |> Enum.filter(&Map.has_key?(by_title, title_key(&1["title"])))
    |> Enum.each(fn doc ->
      Mongo.update_one(:mongo, @collection, %{_id: doc["_id"]}, %{"$set" => by_title[title_key(doc["title"])]})
    end)
  end

  defp store(profile_id, activity, by_title) do
    profile_id
    |> WiseClient.activity(activity["id"])
    |> to_doc(activity, by_title)
    |> then(&Mongo.update_one(:mongo, @collection, %{_id: activity["id"]}, %{"$set" => &1}, upsert: true))
  end

  defp to_doc({:ok, detail}, _activity, _by_title) do
    # Activity details have no createdOn; scheduled ones also lack visibleOn.
    date = detail["visibleOn"] || detail["finishedOn"] || detail["willStartOn"] || ""

    %{
      status: detail["status"],
      type: detail["type"],
      category: detail["category"],
      title: strip_tags(detail["title"]),
      note: note(detail),
      date: date,
      month: String.slice(date, 0, 7) <> "-01",
      amount: amount_eur(detail),
      positive: String.contains?(detail["primaryAmount"], "<positive>"),
      excluded: detail["isExcludedFromInsights"] == true,
      v: @schema_version
    }
  end

  # Wise refuses activity details without SCA (403, x-2fa-approval REJECTED),
  # which a personal token can't provide. The list entry has no category or
  # insights flag, so take them from the latest stored activity with the same title.
  defp to_doc({:error, _reason}, activity, by_title) do
    title = strip_tags(activity["title"])
    date = activity["createdOn"]
    previous = Map.get(by_title, title_key(title), %{category: nil, excluded: false})

    %{
      status: activity["status"],
      type: activity["type"],
      category: previous.category,
      title: title,
      note: note(activity),
      date: date,
      month: String.slice(date, 0, 7) <> "-01",
      amount: amount_eur(activity),
      positive: String.contains?(activity["primaryAmount"], "<positive>"),
      excluded: previous.excluded,
      v: @schema_version
    }
  end

  defp strip_tags(title), do: String.replace(title, ~r/<[^>]*>/, "")

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
