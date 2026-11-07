defmodule ImportUrbanitaeForecasts do
  @moduledoc """
  Stores payout forecasts on `urbanitae_projects` from a JSON list of
  `{"project_key": ..., "forecast": {...}}`. Dry-run unless `--commit`.
  See the urbanitae-ingest skill.

  Uses `--no-start` so it connects to Mongo without booting the snapshot
  recorders and Gmail syncs:

      mix run --no-start scripts/import_urbanitae_forecasts.exs forecasts.json --commit
  """

  alias Sheetfolio.UrbanitaeProjects

  def run([path | flags]) do
    connect()
    rows = path |> File.read!() |> Jason.decode!()
    Enum.each(rows, &show/1)

    if "--commit" in flags do
      Enum.each(rows, &UrbanitaeProjects.put_forecast(&1["project_key"], &1["forecast"]))
      IO.puts("Wrote #{length(rows)} forecasts")
    else
      IO.puts("Dry run. Pass --commit to write #{length(rows)} forecasts")
    end
  end

  defp show(%{"project_key" => key, "forecast" => forecast}) do
    known = if UrbanitaeProjects.by_key(key), do: "", else: "  UNKNOWN PROJECT"
    IO.puts("#{forecast["close_date"]}  #{forecast["to_receive"]}  #{key}#{known}")
  end

  defp connect do
    {:ok, _} = Application.ensure_all_started(:mongodb_driver)

    {:ok, _} =
      Mongo.start_link(
        name: :mongo,
        url: System.fetch_env!("MONGODB_URI"),
        pool_size: 1,
        ssl_opts: [
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
      )
  end
end

ImportUrbanitaeForecasts.run(System.argv())
