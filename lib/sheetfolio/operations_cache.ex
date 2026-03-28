defmodule Sheetfolio.OperationsCache do
  use Agent

  require Logger

  @headers ["Fecha", "Asset", "ISIN", "Tipo", "Cantidad", "Precio", "Importe", "Comisión", "Importe Neto"]

  def start_link(_opts) do
    Agent.start_link(fn -> load() end, name: __MODULE__)
  end

  def get, do: Agent.get(__MODULE__, & &1)

  def reload, do: Agent.update(__MODULE__, fn _ -> load() end)

  defp load do
    case Sheetfolio.MyinvestorEmails.fetch_all() do
      {:ok, operations} ->
        rows =
          operations
          |> Enum.sort_by(&parse_date(&1.fecha), {:desc, Date})
          |> Enum.map(&to_row/1)

        %{headers: @headers, rows: rows}

      {:error, reason} ->
        Logger.error("[OperationsCache] Failed to fetch emails: #{inspect(reason)}")
        %{headers: @headers, rows: []}
    end
  end

  defp to_row(data) do
    [
      data.fecha,
      data.asset,
      data.isin,
      data.tipo,
      data.cantidad,
      data.precio,
      data.importe_without_comision,
      data.comision,
      data.importe_with_comision
    ]
  end

  defp parse_date(date_str) do
    case String.split(date_str, "/") do
      [d, m, y] ->
        Date.new!(String.to_integer(y), String.to_integer(m), String.to_integer(d))

      _ ->
        ~D[1970-01-01]
    end
  end
end
