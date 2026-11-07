defmodule Sheetfolio.HoldingsCheck do
  @moduledoc """
  Checks the units replayed from the emails against an independent count.

  The `Participaciones` sheet holds units per asset on the date in its last row,
  so the replay is cut at that date rather than compared with today: the sheet
  is only updated now and then, and everything bought since would otherwise read
  as a difference.

  Units below zero need no sheet at all, since a position can't be short: they
  mean a buy is missing from the history.
  """

  alias Sheetfolio.GoogleSheetsClient
  alias Sheetfolio.JobRuns
  alias Sheetfolio.Positions

  @sheet "Participaciones"
  @job "holdings_check"

  # The sheet rounds to whole units, while fund units carry decimals.
  @tolerance 1.0

  # Where the sheet identifies an asset differently from the emails.
  @aliases %{
    "ES0165265001" => "N5396",
    "XAD6.DE" => "DE000A1E0HS6",
    "US8629453007" => "US8629451027",
    "PNG.V" => "CA50077N1024"
  }

  # Closed positions whose early buys never reached Gmail. Listed with their
  # shortfall so a change, or a new one, still shows up.
  @known_gaps %{
    "ES0110407097" => -2.30,
    "IE00B04GQR24" => -55.48,
    "IE0007471927" => -3.48,
    "IE0032126645" => -14.90
  }
  @gap_tolerance 0.01

  def run(operations) do
    spreadsheet_id = Application.fetch_env!(:sheetfolio, :spreadsheet_id)

    case GoogleSheetsClient.get_all_values(spreadsheet_id, @sheet) do
      {:ok, %{"values" => [_names, _isins, _units | _] = rows}} -> record(summary(check(rows, operations)))
      other -> JobRuns.failure(@job, "Couldn't read the sheet: #{inspect(other)}")
    end
  end

  defp record(nil), do: JobRuns.success(@job)
  defp record(summary), do: JobRuns.failure(@job, summary)

  @doc """
  Compares the sheet's rows with the operations:

      %{as_of: "08/03/2026",
        differences: [%{name, isin, sheet, replay}],
        negative: [%{asset, isin, units}]}
  """
  def check([[_ | names], [_ | isins] | [_ | _] = data], operations) do
    [as_of | units] = List.last(data)
    replayed = operations |> up_to(as_of) |> Positions.build(1.0, 1.0)

    %{
      as_of: as_of,
      differences: [names, isins, units] |> Enum.zip() |> Enum.flat_map(&difference(&1, replayed)),
      negative: negative(Positions.build(operations, 1.0, 1.0))
    }
  end

  @doc "One line for the data health panel, or `nil` when everything agrees."
  def summary(%{differences: [], negative: []}), do: nil

  def summary(%{as_of: as_of, differences: differences, negative: negative}) do
    lines =
      Enum.map(differences, &"#{&1.name} sheet #{&1.sheet} vs #{Float.round(&1.replay, 2)}") ++
        Enum.map(negative, &"#{&1.asset} at #{Float.round(&1.units, 2)} units")

    "As of #{as_of}: " <> Enum.join(lines, "; ")
  end

  defp up_to(operations, fecha) do
    limit = Positions.date_sort_key(fecha)
    Enum.filter(operations, &(Positions.date_sort_key(&1.fecha) <= limit))
  end

  defp difference({name, isin, units}, replayed) do
    id = String.trim(isin)
    position = Map.get(replayed, Map.get(@aliases, id, id), %{net_qty: 0.0})

    case {id, parse_units(units)} do
      {"", _} -> []
      {_, :error} -> []
      {_, {sheet, _}} when abs(sheet - position.net_qty) < @tolerance -> []
      {_, {sheet, _}} -> [%{name: name, isin: id, sheet: sheet, replay: position.net_qty}]
    end
  end

  # Always Spanish here: "1.844" is 1844 units and "0,02" is a fraction.
  defp parse_units(units) do
    units |> String.replace(".", "") |> String.replace(",", ".") |> Float.parse()
  end

  defp negative(positions) do
    positions
    |> Map.values()
    |> Enum.filter(&(&1.net_qty < -@gap_tolerance and not known_gap?(&1)))
    |> Enum.map(&%{asset: &1.asset, isin: &1.isin, units: &1.net_qty})
  end

  defp known_gap?(%{isin: isin, net_qty: units}) do
    case @known_gaps do
      %{^isin => known} -> abs(units - known) < @gap_tolerance
      _other -> false
    end
  end
end
