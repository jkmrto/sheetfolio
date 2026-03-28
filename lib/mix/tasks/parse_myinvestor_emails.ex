defmodule Mix.Tasks.ParseMyinvestorEmails do
  use Mix.Task

  @shortdoc "Dry run: fetch and parse all MyInvestor operation emails"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("Fetching MyInvestor operation emails...\n")

    {:ok, operations} = Sheetfolio.MyinvestorEmails.fetch_all()
    Mix.shell().info("Found #{length(operations)} emails\n")

    Enum.each(operations, &print_result/1)

    Mix.shell().info("\nDone. #{length(operations)} parsed successfully.")
  end

  defp print_result(data) do
    check = validate_amounts(data.cantidad, data.precio, data.importe_without_comision)

    Mix.shell().info("""
    [OK]
      Fecha:    #{data.fecha}
      Asset:    #{data.asset}
      ISIN:     #{data.isin}
      Tipo:     #{data.tipo}
      Cantidad: #{data.cantidad}
      Precio:   #{data.precio}
      Importe:  #{data.importe_without_comision}
      Comisión: #{data.comision}
      Neto:     #{data.importe_with_comision}
      Check:    #{check}
    """)
  end

  defp validate_amounts(cantidad, precio, importe) do
    with {q, _} <- Float.parse(String.replace(cantidad, ",", "")),
         {p, _} <- Float.parse(String.replace(precio, ~r/[^\d.,]/, "") |> String.replace(",", "")),
         {t, _} <- Float.parse(String.replace(importe, ~r/[^\d.,]/, "") |> String.replace(",", "")) do
      expected = Float.round(q * p, 2)
      diff = abs(expected - t)
      if diff < 0.10, do: "✓ #{expected} ≈ #{t}", else: "✗ expected #{expected}, got #{t} (diff: #{diff})"
    else
      _ -> "? could not validate"
    end
  end
end
