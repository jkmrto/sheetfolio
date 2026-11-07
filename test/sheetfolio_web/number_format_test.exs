defmodule SheetfolioWeb.NumberFormatTest do
  use ExUnit.Case, async: true

  alias SheetfolioWeb.NumberFormat, as: Format

  test "amounts use dots for thousands and a comma for decimals" do
    assert Format.eur(1_234_567.89) == "1.234.567,89 €"
    assert Format.eur(999) == "999,00 €"
    assert Format.eur(1000.5) == "1.000,50 €"
    assert Format.eur(-1234.5) == "-1.234,50 €"
  end

  test "rounding up carries into the whole part" do
    assert Format.eur(1.999) == "2,00 €"
    assert Format.eur(999.999) == "1.000,00 €"
  end

  test "a tiny negative is not shown as negative zero" do
    assert Format.eur(-0.001) == "0,00 €"
  end

  test "gains carry their sign" do
    assert Format.signed_eur(1234.5) == "+1.234,50 €"
    assert Format.signed_eur(-1234.5) == "-1.234,50 €"
    assert Format.signed_pct(1234.5) == "+1.234,50%"
    assert Format.signed_pct(-3.2) == "-3,20%"
  end

  test "number takes its decimals" do
    assert Format.number(6281.25, 0) == "6.281"
    assert Format.number(59.8123, 1) == "59,8"
    assert Format.number(0.12345678, 8) == "0,12345678"
  end

  test "units keep only the decimals they need" do
    assert Format.qty(1234.5) == "1.234,5"
    assert Format.qty(0.1234) == "0,1234"
    assert Format.qty(100.0) == "100"
  end

  test "a missing value shows a dash" do
    assert Format.eur(nil) == "—"
    assert Format.signed_eur(nil) == "—"
    assert Format.pct(nil) == "—"
    assert Format.signed_pct(nil) == "—"
    assert Format.qty(nil) == "—"
  end

  test "text from an email keeps its unit and decimals" do
    assert Format.text("1499.91 EUR") == "1.499,91 EUR"
    assert Format.text("1234.5678") == "1.234,5678"
    assert Format.text("84.63 USD") == "84,63 USD"
    assert Format.text("10,058.56 EUR") == "10.058,56 EUR"
    assert Format.text("1,418.996") == "1.418,996"
  end

  test "text that isn't a plain number is left alone" do
    assert Format.text("") == ""
    assert Format.text("n/a") == "n/a"
    assert Format.text(nil) == nil
  end
end
