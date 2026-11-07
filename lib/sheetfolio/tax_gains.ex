defmodule Sheetfolio.TaxGains do
  @moduledoc """
  Realized gains the way the IRPF counts them: oldest units sold first.

  `Positions` uses average cost, which is the right measure for the dashboard
  but not for the return, so the two give different yearly figures. Over a
  position that was fully sold they add up to the same total; only the year each
  gain lands in differs.

  A traspaso is not a sale: the source's oldest lots move to the destination
  keeping their cost and acquisition date. Units sold beyond the recorded buys
  have no known cost, so as in `Positions` they realize nothing and are reported
  as uncovered.

  This is an estimate to prepare the return from, not the figure to file. It
  doesn't apply the two-month rule on losses, and USD and CAD amounts convert at
  the day's market rate rather than what the broker charged.
  """

  alias Sheetfolio.Positions

  @dust 1.0e-9

  @doc """
  One entry per year, newest first:

      %{year, proceeds, cost, gain, uncovered, sales: [%{fecha, asset, isin, tipo,
        qty, uncovered, proceeds, cost, gain}]}
  """
  def by_year(operations, eur_usd, eur_cad) do
    operations
    |> sales(eur_usd, eur_cad)
    |> Enum.group_by(&year/1)
    |> Enum.map(&summarize/1)
    |> Enum.sort_by(& &1.year, :desc)
  end

  @doc "Every sale with its FIFO cost, oldest first."
  def sales(operations, eur_usd, eur_cad) do
    {sales, _lots} = replay(operations, eur_usd, eur_cad)
    sales
  end

  @doc "The cost still held per ISIN, for reconciling with `Positions`."
  def open_cost(operations, eur_usd, eur_cad) do
    {_sales, lots} = replay(operations, eur_usd, eur_cad)
    Map.new(lots, fn {isin, held} -> {isin, Enum.reduce(held, 0.0, &(&1.cost + &2))} end)
  end

  defp replay(operations, eur_usd, eur_cad) do
    {sales, state} =
      operations
      |> Positions.in_settlement_order()
      |> Enum.reduce({[], %{lots: %{}, moved: %{}}}, &step(&1, &2, eur_usd, eur_cad))

    {Enum.reverse(sales), state.lots}
  end

  defp summarize({year, sales}) do
    %{
      year: year,
      proceeds: sum(sales, :proceeds),
      cost: sum(sales, :cost),
      gain: sum(sales, :gain),
      uncovered: Enum.count(sales, &(&1.uncovered > 0.001)),
      sales: sales
    }
  end

  defp sum(sales, key), do: Enum.reduce(sales, 0.0, &(Map.fetch!(&1, key) + &2))

  defp year(%{fecha: fecha}), do: fecha |> Positions.date_sort_key() |> elem(0)

  defp step(op, {sales, state}, eur_usd, eur_cad) do
    qty = Positions.parse_cantidad(op.cantidad)
    {rate_usd, rate_cad} = Positions.rates_for(op, eur_usd, eur_cad)
    amount = Positions.amount_in_eur(op.importe_with_comision, op.precio, qty, rate_usd, rate_cad)

    cond do
      Positions.buy?(op.tipo) -> {sales, buy(state, op, qty, amount)}
      Positions.traspaso?(op) -> {sales, move_out(state, op, qty, amount)}
      true -> sell(sales, state, op, qty, amount)
    end
  end

  defp buy(state, op, qty, amount) do
    add_lots(state, op.isin, incoming_lots(state, op, qty, amount))
  end

  # Each incoming leg takes its share of what left, by value, because MyInvestor
  # can split one traspaso into several subscriptions.
  defp incoming_lots(state, op, qty, amount) do
    case moved_out(state, op) do
      %{lots: lots, units: units, proceeds: proceeds} when units > 0 and proceeds > 0 ->
        Enum.map(lots, &%{date: &1.date, qty: qty * &1.qty / units, cost: &1.cost * amount / proceeds})

      _unseen_source ->
        [%{date: op.fecha, qty: qty, cost: amount}]
    end
  end

  defp moved_out(state, op) do
    if Positions.traspaso?(op), do: Map.get(state.moved, {op.traspaso_from, op.traspaso_to})
  end

  defp move_out(state, op, qty, amount) do
    {taken, left, uncovered} = take(lots_of(state, op.isin), qty)
    assumed = if qty > 0 and uncovered > @dust, do: [%{date: op.fecha, qty: uncovered, cost: uncovered * amount / qty}], else: []
    moved = %{lots: taken ++ assumed, units: qty, proceeds: amount}

    %{state | lots: Map.put(state.lots, op.isin, left), moved: Map.put(state.moved, {op.traspaso_from, op.traspaso_to}, moved)}
  end

  defp sell(sales, state, op, qty, amount) do
    {taken, left, uncovered} = take(lots_of(state, op.isin), qty)
    covered = qty - uncovered
    cost = Enum.reduce(taken, 0.0, &(&1.cost + &2))
    proceeds = if qty > 0, do: amount * covered / qty, else: 0.0

    sale = %{
      fecha: op.fecha, asset: op.asset, isin: op.isin, tipo: op.tipo,
      qty: qty, uncovered: uncovered, proceeds: proceeds, cost: cost, gain: proceeds - cost
    }

    {[sale | sales], %{state | lots: Map.put(state.lots, op.isin, left)}}
  end

  defp lots_of(state, isin), do: Map.get(state.lots, isin, [])

  defp add_lots(state, isin, lots) do
    held = (lots_of(state, isin) ++ lots) |> Enum.sort_by(&Positions.date_sort_key(&1.date))
    %{state | lots: Map.put(state.lots, isin, held)}
  end

  # Takes `qty` units from the oldest lots: `{taken, left, units short}`.
  defp take(lots, qty), do: take(lots, qty, [])

  defp take(lots, qty, taken) when qty <= @dust, do: {Enum.reverse(taken), lots, 0.0}
  defp take([], qty, taken), do: {Enum.reverse(taken), [], qty}

  defp take([%{qty: held} = lot | rest], qty, taken) when held <= qty + @dust do
    take(rest, qty - held, [lot | taken])
  end

  defp take([lot | rest], qty, taken) do
    share = qty / lot.qty
    part = %{lot | qty: qty, cost: lot.cost * share}
    kept = %{lot | qty: lot.qty - qty, cost: lot.cost * (1 - share)}

    {Enum.reverse([part | taken]), [kept | rest], 0.0}
  end
end
