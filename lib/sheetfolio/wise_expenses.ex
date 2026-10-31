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

  # Share of a title's history its dominant category needs before a new
  # activity with that title inherits it.
  @agreement 0.8
  @note_agreement 0.6

  # "Other" is what Wise's own GENERAL shows as, so filing a row there by hand
  # stores that.
  @codes @labels |> Map.new(fn {code, label} -> {label, code} end) |> Map.put("Other", "GENERAL")

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
    Mongo.find(:mongo, @collection, %{status: "COMPLETED", excluded: false, positive: false},
      sort: %{date: -1}
    )
    |> Enum.map(fn doc ->
      %{
        id: doc["_id"],
        date: String.slice(doc["date"] || "", 0, 10),
        title: doc["title"],
        note: doc["note"] || "",
        category: Map.get(@labels, doc["category"], "Other"),
        uncategorized: is_nil(doc["category"]),
        guessed: doc["guessed"] == true,
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

    inference = inference()

    activities
    |> Enum.reject(&(known[&1["id"]] == {&1["status"], @schema_version}))
    |> Task.async_stream(&store(profile["id"], &1, inference),
      max_concurrency: 10,
      timeout: 60_000
    )
    |> Stream.run()

    fill_uncategorized()
  end

  @doc """
  Files an activity under `label`, overriding whatever Wise or a guess gave
  it, which also makes it something later guesses learn from. Other
  uncategorized ones follow if that settles their merchant or note (see
  `infer/3`).
  """
  def categorize(id, label) when is_map_key(@codes, label) do
    Mongo.update_one(:mongo, @collection, %{_id: id}, %{
      "$set" => %{category: @codes[label], guessed: false}
    })

    fill_uncategorized()
  end

  @doc """
  The key two titles are matched on: Wise spells the same merchant with
  varying case and spacing ("Escuela infantil Sol y Luna" and "Escuela
  Infantil SolYLuna"), so only letters and digits count.
  """
  def title_key(nil), do: ""
  def title_key(title), do: title |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]/u, "")

  # What a guess may learn from: outgoing activities whose category came from
  # Wise or from a person, never another guess.
  defp inference do
    docs =
      Mongo.find(
        :mongo,
        @collection,
        %{category: %{"$ne" => nil}, positive: false, guessed: %{"$ne" => true}},
        sort: %{date: 1},
        projection: %{title: 1, note: 1, category: 1, excluded: 1}
      )
      |> Enum.to_list()

    %{
      titles: title_categories(docs),
      notes: note_model(Enum.filter(docs, &(&1["note"] not in [nil, ""])))
    }
  end

  @doc """
  The category, insights flag and guessed mark for an activity Wise gave no
  detail for. A merchant whose history agrees decides it outright; otherwise
  the transfer note, if any, is guessed from (see `guess_from_note/2`), and
  the result is marked as a guess so it can be corrected.
  """
  def infer(title, note, %{titles: titles, notes: notes}) do
    case Map.fetch(titles, title_key(title)) do
      {:ok, known} -> Map.put(known, :guessed, false)
      :error -> note_guess(guess_from_note(note || "", notes))
    end
  end

  # Only a guess that lands in a category of its own is worth showing; GENERAL
  # and the like would only file it under Other with a question mark.
  defp note_guess(category) when is_map_key(@labels, category),
    do: %{category: category, excluded: false, guessed: true}

  defp note_guess(_category), do: %{category: nil, excluded: false, guessed: false}

  @doc """
  The category and insights flag an activity stored without a detail takes
  from earlier outgoing activities with the same title, keyed by
  `title_key/1`. A title gets an entry only when one category covers at least
  80% of its history: Wise files a few of a merchant's payments oddly (one
  Lidl trip in 190), but a transfer's title is the recipient, not the
  purpose, so transfers to one person spread across every category and any
  pick would be a guess. The insights flag is the latest activity's.
  """
  def title_categories(docs) do
    docs
    |> Enum.group_by(&title_key(&1["title"]))
    |> Enum.flat_map(fn {key, group} -> dominant_category(key, group) end)
    |> Map.new()
  end

  defp dominant_category(key, group) do
    {category, count} =
      group |> Enum.frequencies_by(& &1["category"]) |> Enum.max_by(&elem(&1, 1))

    if count / length(group) >= @agreement,
      do: [{key, %{category: category, excluded: List.last(group)["excluded"] == true}}],
      else: []
  end

  @months ~w(enero febrero marzo abril mayo junio julio agosto septiembre setiembre octubre noviembre diciembre)
  @stopwords ~w(del las los con por para una mes)

  @doc """
  The words a transfer note is matched on: lowercased, accents stripped,
  month names and filler dropped, and cut to five letters, which is a crude
  stem that still lets "restaurante" meet "restaurantes" and "ticker" meet
  "ticket".
  """
  def note_tokens(note) do
    note
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.split(~r/[^a-z]+/, trim: true)
    |> Enum.reject(&(String.length(&1) < 3 or &1 in @months or &1 in @stopwords))
    |> Enum.map(&String.slice(&1, 0, 5))
    |> Enum.uniq()
  end

  @doc """
  How often each note word was filed under each category, from activities
  whose category Wise or a person gave: `%{word => %{category => count}}`.
  """
  def note_model(docs) do
    for doc <- docs, word <- note_tokens(doc["note"] || ""), reduce: %{} do
      model ->
        Map.update(
          model,
          word,
          %{doc["category"] => 1},
          &Map.update(&1, doc["category"], 1, fn n -> n + 1 end)
        )
    end
  end

  @doc """
  The category a transfer's note points to, or nil. Every known word casts
  one vote, split across the categories it has been filed under; the winner
  needs #{trunc(@note_agreement * 100)}% of the votes, so a note whose words
  pull different ways stays uncategorized.
  """
  def guess_from_note(note, model) do
    note
    |> note_tokens()
    |> Enum.flat_map(&word_votes(model[&1]))
    |> Enum.reduce(%{}, fn {category, vote}, acc ->
      Map.update(acc, category, vote, &(&1 + vote))
    end)
    |> winner()
  end

  defp word_votes(nil), do: []

  defp word_votes(counts) do
    total = counts |> Map.values() |> Enum.sum()
    Enum.map(counts, fn {category, n} -> {category, n / total} end)
  end

  defp winner(votes) when map_size(votes) == 0, do: nil

  defp winner(votes) do
    {category, vote} = Enum.max_by(votes, &elem(&1, 1))
    if vote / Enum.sum(Map.values(votes)) >= @note_agreement, do: category
  end

  @doc """
  Gives every uncategorized activity whatever `infer/3` now makes of it, e.g.
  after a manual categorization settled its merchant.
  """
  def fill_uncategorized do
    inference = inference()

    Mongo.find(:mongo, @collection, %{category: nil}, projection: %{title: 1, note: 1})
    |> Enum.map(&{&1["_id"], infer(&1["title"], &1["note"], inference)})
    |> Enum.reject(fn {_id, inferred} -> is_nil(inferred.category) end)
    |> Enum.each(fn {id, inferred} ->
      Mongo.update_one(:mongo, @collection, %{_id: id}, %{"$set" => inferred})
    end)
  end

  defp store(profile_id, activity, inference) do
    profile_id
    |> WiseClient.activity(activity["id"])
    |> to_doc(activity, inference)
    |> then(
      &Mongo.update_one(:mongo, @collection, %{_id: activity["id"]}, %{"$set" => &1},
        upsert: true
      )
    )
  end

  defp to_doc({:ok, detail}, _activity, _inference) do
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
      guessed: false,
      v: @schema_version
    }
  end

  # Wise refuses activity details without SCA (403, x-2fa-approval REJECTED),
  # which a personal token can't provide. The list entry has no category or
  # insights flag, so infer them from the title and the transfer note.
  defp to_doc({:error, _reason}, activity, inference) do
    title = strip_tags(activity["title"])
    note = note(activity)
    date = activity["createdOn"]
    inferred = infer(title, note, inference)

    %{
      status: activity["status"],
      type: activity["type"],
      category: inferred.category,
      title: title,
      note: note,
      date: date,
      month: String.slice(date, 0, 7) <> "-01",
      amount: amount_eur(activity),
      positive: String.contains?(activity["primaryAmount"], "<positive>"),
      excluded: inferred.excluded,
      guessed: inferred.guessed,
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
