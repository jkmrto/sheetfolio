defmodule Sheetfolio.OperationHistoryTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.OperationHistory
  alias Sheetfolio.SyntheticOperations

  defp op(attrs) do
    Map.merge(
      %{
        fecha: "01/01/2020",
        asset: "SOMETHING",
        isin: "XX0000000000",
        tipo: "Compra",
        cantidad: "1",
        precio: "1 EUR",
        importe_without_comision: "1 EUR",
        comision: "",
        importe_with_comision: "1 EUR",
        traspaso: false
      },
      attrs
    )
  end

  # Regression: 6386c4a dropped the synthetic operations, which silently
  # changed realized P&L. They live in Mongo now, so the operations are passed
  # in rather than read: what's guarded here is that they still reach the
  # history at all.
  test "appends the synthetic operations missing from Gmail" do
    gmail = [op(%{isin: "FROM0000GMAIL"})]
    synthetic = [op(%{fecha: "28/10/2024", isin: "FR0000447823", tipo: "Reembolso"})]

    patched = OperationHistory.patch(gmail, synthetic)

    assert patched == gmail ++ synthetic
  end

  test "applies a per-{fecha, isin} override to the matching operation" do
    ops = [op(%{fecha: "09/01/2026", isin: "US8629451027", cantidad: "1", precio: "1 USD"})]

    [patched | _] = OperationHistory.patch(ops, [])

    assert patched.cantidad == "141"
    assert patched.precio == "19.85 USD"
  end

  test "leaves operations without an override untouched" do
    original = op(%{})

    assert [^original | _] = OperationHistory.patch([original], [])
  end

  test "drops operations an override marks skip" do
    skipped = op(%{skip: true})
    kept = op(%{isin: "YY0000000000"})

    patched = OperationHistory.patch([skipped, kept], [])

    refute Enum.any?(patched, &(&1[:skip] == true))
    assert Enum.any?(patched, &(&1.isin == "YY0000000000"))
  end
end
