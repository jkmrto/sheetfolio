defmodule Mix.Tasks.WiseOperations do
  use Mix.Task

  @shortdoc "Dry run: fetch Wise balances and operations (mix wise_operations [days], default 30)"

  alias Sheetfolio.WiseClient

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:req)

    days =
      case args do
        [n] -> String.to_integer(n)
        [] -> 30
      end

    since = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-days, :day)

    {:ok, profiles} = WiseClient.profiles()

    Enum.each(profiles, fn profile ->
      Mix.shell().info("Profile #{profile["id"]} (#{profile["type"]})")
      print_balances(profile["id"])
      print_activities(profile["id"], since)
    end)
  end

  defp print_balances(profile_id) do
    {:ok, balances} = WiseClient.balances(profile_id)

    Mix.shell().info("\nBalances:")

    Enum.each(balances, fn balance ->
      amount = balance["amount"]
      Mix.shell().info("  #{amount["value"]} #{amount["currency"]}")
    end)
  end

  defp print_activities(profile_id, since) do
    {:ok, activities} = WiseClient.activities(profile_id, since)

    Mix.shell().info("\n#{length(activities)} operations since #{DateTime.to_date(since)}:\n")
    Enum.each(activities, &print_activity/1)
  end

  defp print_activity(activity) do
    Mix.shell().info("""
      Date:    #{activity["createdOn"]}
      Type:    #{activity["type"]}
      Status:  #{activity["status"]}
      Amount:  #{activity["primaryAmount"]}#{secondary(activity["secondaryAmount"])}
      Title:   #{strip_tags(activity["title"])}
    """)
  end

  defp secondary(""), do: ""
  defp secondary(amount), do: " (#{strip_tags(amount)})"

  defp strip_tags(nil), do: ""
  defp strip_tags(text), do: String.replace(text, ~r/<[^>]*>/, "")
end
