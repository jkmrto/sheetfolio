defmodule RederiveWiseCategories do
  @moduledoc """
  Re-derives the category of every Wise activity stored from the list entry
  (Wise refuses details since October 2026), using only the activities stored
  before then, which carry Wise's own category. A title with no dominant
  category comes out uncategorized, to be filed on /expenses.

  Dry run by default; pass --apply to write.

  Run with: set -a && . ./.env && set +a && mix run scripts/rederive_wise_categories.exs [--apply]
  """

  @collection "wise_activities"
  @since "2026-10-01"

  def run(apply?) do
    by_title =
      Mongo.find(
        :mongo,
        @collection,
        %{date: %{"$lt" => @since}, category: %{"$ne" => nil}, positive: false}, sort: %{date: 1})
      |> Sheetfolio.WiseExpenses.title_categories()

    changes =
      Mongo.find(:mongo, @collection, %{date: %{"$gte" => @since}, positive: false},
        sort: %{date: 1}
      )
      |> Enum.map(
        &{&1,
         Map.get(by_title, Sheetfolio.WiseExpenses.title_key(&1["title"]), %{
           category: nil,
           excluded: false
         })}
      )
      |> Enum.reject(fn {doc, derived} ->
        doc["category"] == derived.category and doc["excluded"] == true == derived.excluded
      end)

    for {doc, derived} <- changes do
      IO.puts(
        "#{String.slice(doc["date"], 0, 10)}  #{doc["title"]}  #{doc["amount"]}: #{inspect(doc["category"])} -> #{inspect(derived.category)}"
      )

      if apply?,
        do: Mongo.update_one(:mongo, @collection, %{_id: doc["_id"]}, %{"$set" => derived})
    end

    IO.puts(
      "#{length(changes)} activities #{if apply?, do: "updated", else: "would change (dry run)"}"
    )
  end
end

RederiveWiseCategories.run("--apply" in System.argv())
