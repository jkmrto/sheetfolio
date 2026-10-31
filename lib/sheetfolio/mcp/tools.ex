defmodule Sheetfolio.Mcp.Tools do
  @moduledoc """
  The tools the MCP endpoint exposes. All of them are read-only: they read
  what the dashboard already shows (the Mongo snapshots and caches, the
  in-memory operation history) and never write anything or trigger a sync.

  Arguments are checked before anything is read, so a bad one costs no I/O.
  """

  alias Sheetfolio.AssetCategories
  alias Sheetfolio.Dividends
  alias Sheetfolio.EarningsServer
  alias Sheetfolio.OperationsServer
  alias Sheetfolio.Positions
  alias Sheetfolio.UrbanitaeTransactions
  alias Sheetfolio.WiseExpenses

  @date %{type: "string", format: "date", description: "YYYY-MM-DD"}
  @isin %{type: "string", description: "ISIN, or a synthetic id like URBANITAE or COINBASE-BTC"}
  @default_history_days 90
  @default_limit 100
  @max_limit 1000

  @definitions [
    %{
      name: "get_portfolio",
      description:
        "The latest daily portfolio snapshot: every position's units, invested amount, " <>
          "value and P&L in EUR with its category, totals, a breakdown by category, " <>
          "and the latest cash snapshot by source.",
      properties: %{}
    },
    %{
      name: "get_portfolio_history",
      description:
        "Daily portfolio totals (invested, value, cumulative realized P&L) between two dates, " <>
          "or one position's daily units, invested and value when an ISIN is given. " <>
          "Defaults to the last #{@default_history_days} days.",
      properties: %{from: @date, to: @date, isin: @isin}
    },
    %{
      name: "list_operations",
      description:
        "Broker operations (buys, sells, fund transfers) parsed from confirmation emails, " <>
          "newest first. `count` is the number matching before the limit.",
      properties: %{
        from: @date,
        to: @date,
        isin: @isin,
        tipo: %{
          type: "string",
          description: "Operation type, e.g. Compra, Venta, Suscripcion, Reembolso"
        },
        limit: %{
          type: "integer",
          minimum: 1,
          maximum: @max_limit,
          description: "Default #{@default_limit}"
        }
      }
    },
    %{
      name: "get_positions",
      description:
        "Positions rebuilt from the operation history with average-cost accounting: units held, " <>
          "cost basis, average cost, total bought and received, and realized P&L. No market values; " <>
          "use get_portfolio for those.",
      properties: %{
        include_closed: %{type: "boolean", description: "Include fully sold positions"}
      }
    },
    %{
      name: "get_realized_pnl",
      description:
        "One event per sale with proceeds, cost and realized P&L. `uncovered` units were sold " <>
          "beyond the recorded buy history and realize nothing.",
      properties: %{from: @date, to: @date, isin: @isin}
    },
    %{
      name: "get_cash_history",
      description:
        "Daily cash snapshots (total and per-source amounts in EUR). Defaults to the last #{@default_history_days} days.",
      properties: %{from: @date, to: @date}
    },
    %{
      name: "get_urbanitae",
      description:
        "Urbanitae real-estate crowdfunding: per-project invested, returned principal and yield, " <>
          "outstanding capital, net P&L and status, plus current totals.",
      properties: %{}
    },
    %{
      name: "get_dividends",
      description: "Dividends received, grouped by asset with every payment.",
      properties: %{}
    },
    %{
      name: "get_expenses",
      description:
        "Card and account spending from Wise, totalled by category and by month, with the " <>
          "most recent transactions (up to `limit`).",
      properties: %{
        from: @date,
        to: @date,
        category: %{type: "string", description: "e.g. Groceries, Eating out, Bills, Housing"},
        limit: %{
          type: "integer",
          minimum: 1,
          maximum: @max_limit,
          description: "Default #{@default_limit}"
        }
      }
    }
  ]

  @names Enum.map(@definitions, & &1.name)

  def definitions do
    Enum.map(@definitions, fn tool ->
      %{
        name: tool.name,
        description: tool.description,
        inputSchema: %{type: "object", properties: tool.properties, additionalProperties: false},
        annotations: %{readOnlyHint: true, openWorldHint: false}
      }
    end)
  end

  @doc "`{:ok, data}`, `{:error, message}` for a bad argument, or `:unknown`."
  def call(name, args) when name in @names and is_map(args), do: run(name, args)
  def call(name, _args) when name in @names, do: {:error, "arguments must be an object"}
  def call(_name, _args), do: :unknown

  # --- Tools ---

  defp run("get_portfolio", _args) do
    {:ok,
     %{portfolio: portfolio(latest("portfolio_snapshots")), cash: cash(latest("cash_snapshots"))}}
  end

  defp run("get_portfolio_history", args) do
    with {:ok, from, to} <- range(args),
         {:ok, isin} <- string(args, "isin") do
      {:ok,
       %{from: from, to: to, days: Enum.map(snapshots_between(from, to), &history_day(&1, isin))}}
    end
  end

  defp run("list_operations", args) do
    with {:ok, from, to} <- range(args, nil),
         {:ok, isin} <- string(args, "isin"),
         {:ok, tipo} <- string(args, "tipo"),
         {:ok, limit} <- limit(args) do
      operations =
        OperationsServer.get_operations(30_000)
        |> Enum.filter(
          &(within?(fecha_date(&1.fecha), from, to) and matches?(&1.isin, isin) and
              matches?(&1.tipo, tipo))
        )
        |> Enum.sort_by(&fecha_date(&1.fecha), {:desc, Date})

      {:ok, %{count: length(operations), operations: Enum.take(operations, limit)}}
    end
  end

  defp run("get_positions", args) do
    with {:ok, include_closed} <- boolean(args, "include_closed") do
      {eur_usd, eur_cad} = EarningsServer.get_fx_rates()

      positions =
        OperationsServer.get_operations(30_000)
        |> Positions.build(eur_usd, eur_cad)
        |> Map.values()
        |> Enum.filter(&(include_closed or &1.net_qty > 0.001))
        |> Enum.sort_by(& &1.cost_basis, :desc)
        |> Enum.map(&position/1)

      {:ok, %{positions: positions}}
    end
  end

  defp run("get_realized_pnl", args) do
    with {:ok, from, to} <- range(args, nil),
         {:ok, isin} <- string(args, "isin") do
      {eur_usd, eur_cad} = EarningsServer.get_fx_rates()

      events =
        OperationsServer.get_operations(30_000)
        |> Positions.realized_events(eur_usd, eur_cad)
        |> Enum.filter(&(within?(fecha_date(&1.fecha), from, to) and matches?(&1.isin, isin)))
        |> Enum.map(&realized_event/1)

      {:ok,
       %{
         total_realized: events |> Enum.map(& &1.realized) |> Enum.sum() |> round2(),
         events: events
       }}
    end
  end

  defp run("get_cash_history", args) do
    with {:ok, from, to} <- range(args) do
      days =
        "cash_snapshots"
        |> between(from, to)
        |> Enum.map(&%{date: &1["date"], total: &1["total"], sources: clean(&1["sources"] || [])})

      {:ok, %{from: from, to: to, days: days}}
    end
  end

  defp run("get_urbanitae", _args) do
    transactions = UrbanitaeTransactions.all()

    {outstanding, earnings} =
      UrbanitaeTransactions.state_at(transactions, Date.to_iso8601(Date.utc_today()))

    {:ok,
     %{
       outstanding: round2(outstanding),
       earnings: round2(earnings),
       projects: UrbanitaeTransactions.rollup_by_project(transactions)
     }}
  end

  defp run("get_dividends", _args) do
    dividends = Dividends.all()
    {:ok, %{total: Dividends.total(dividends), by_asset: clean(Dividends.by_asset(dividends))}}
  end

  defp run("get_expenses", args) do
    with {:ok, from, to} <- range(args, nil),
         {:ok, category} <- string(args, "category"),
         {:ok, limit} <- limit(args) do
      expenses =
        Enum.filter(WiseExpenses.list(), fn expense ->
          iso_within?(expense.date, from, to) and matches?(expense.category, category)
        end)

      {:ok,
       %{
         total: expenses |> Enum.map(& &1.amount) |> Enum.sum() |> round2(),
         by_category: total_by(expenses, & &1.category),
         by_month: total_by(expenses, &String.slice(&1.date, 0, 7)),
         count: length(expenses),
         transactions: Enum.take(expenses, limit)
       }}
    end
  end

  # --- Shaping ---

  defp portfolio(nil), do: nil

  defp portfolio(snapshot) do
    categories = AssetCategories.get()
    positions = snapshot["positions"] || []

    %{
      date: snapshot["date"],
      total_invested: snapshot["total_invested"],
      total_value: snapshot["total_value"],
      total_realized: snapshot["total_realized"],
      partial: snapshot["partial"],
      by_category: AssetCategories.breakdown(positions, categories),
      positions: Enum.map(positions, &snapshot_position(&1, categories))
    }
  end

  defp snapshot_position(position, categories) do
    %{
      isin: position["isin"],
      asset: position["asset"],
      category: AssetCategories.category_for(position["isin"], categories),
      units: position["units"],
      invested: position["invested"],
      value: position["value"],
      pnl: pnl(position["value"], position["invested"]),
      stale_price: position["stale_price"]
    }
  end

  defp pnl(value, invested) when is_number(value) and is_number(invested),
    do: round2(value - invested)

  defp pnl(_value, _invested), do: nil

  defp cash(nil), do: nil

  defp cash(snapshot),
    do: %{
      date: snapshot["date"],
      total: snapshot["total"],
      sources: clean(snapshot["sources"] || [])
    }

  defp history_day(snapshot, nil) do
    Map.take(snapshot, ["date", "total_invested", "total_value", "total_realized"])
  end

  defp history_day(snapshot, isin) do
    position = Enum.find(snapshot["positions"] || [], &(&1["isin"] == isin)) || %{}

    %{
      date: snapshot["date"],
      units: position["units"],
      invested: position["invested"],
      value: position["value"]
    }
  end

  defp position(asset) do
    %{
      isin: asset.isin,
      asset: asset.asset,
      units: asset.net_qty,
      cost_basis: round2(asset.cost_basis),
      average_cost: if(asset.net_qty > 0.001, do: round2(asset.cost_basis / asset.net_qty)),
      total_bought: round2(asset.total_bought),
      total_received: round2(asset.total_received),
      realized: round2(asset.realized)
    }
  end

  defp realized_event(event) do
    %{
      fecha: event.fecha,
      isin: event.isin,
      asset: event.asset,
      tipo: event.tipo,
      units: event.qty,
      uncovered: event.uncovered,
      proceeds: round2(event.proceeds),
      cost: round2(event.cost),
      realized: round2(event.realized)
    }
  end

  defp total_by(expenses, key) do
    expenses
    |> Enum.group_by(key, & &1.amount)
    |> Map.new(fn {group, amounts} -> {group, amounts |> Enum.sum() |> round2()} end)
  end

  # Mongo documents carry a BSON ObjectId, which JSON can't encode and no
  # client needs.
  defp clean(%DateTime{} = datetime), do: datetime

  defp clean(map) when is_map(map),
    do: map |> Map.drop(["_id", :_id]) |> Map.new(fn {k, v} -> {k, clean(v)} end)

  defp clean(list) when is_list(list), do: Enum.map(list, &clean/1)
  defp clean(value), do: value

  defp round2(number), do: Float.round(number * 1.0, 2)

  # --- Reading ---

  defp latest(collection), do: Mongo.find_one(:mongo, collection, %{}, sort: %{date: -1})

  defp snapshots_between(from, to), do: between("portfolio_snapshots", from, to)

  defp between(collection, from, to) do
    query = %{date: %{"$gte" => Date.to_iso8601(from), "$lte" => Date.to_iso8601(to)}}
    :mongo |> Mongo.find(collection, query, sort: %{date: 1}) |> Enum.to_list()
  end

  defp fecha_date(fecha) do
    [day, month, year] = fecha |> String.split("/") |> Enum.map(&String.to_integer/1)
    Date.new!(year, month, day)
  end

  defp within?(date, from, to) do
    (is_nil(from) or Date.compare(date, from) != :lt) and
      (is_nil(to) or Date.compare(date, to) != :gt)
  end

  defp iso_within?(date, from, to) do
    (is_nil(from) or date >= Date.to_iso8601(from)) and
      (is_nil(to) or date <= Date.to_iso8601(to))
  end

  defp matches?(_value, nil), do: true
  defp matches?(value, wanted), do: String.downcase(to_string(value)) == String.downcase(wanted)

  # --- Arguments ---

  # Snapshot ranges default to the recent past; event lists default to everything.
  defp range(args),
    do: range(args, Date.add(Date.utc_today(), -@default_history_days), Date.utc_today())

  defp range(args, nil), do: range(args, nil, nil)

  defp range(args, default_from, default_to) do
    with {:ok, from} <- date(args, "from", default_from),
         {:ok, to} <- date(args, "to", default_to) do
      {:ok, from, to}
    end
  end

  defp date(args, key, default), do: parse_date(Map.get(args, key), key, default)

  defp parse_date(nil, _key, default), do: {:ok, default}

  defp parse_date(value, key, _default) when is_binary(value),
    do: iso_date(Date.from_iso8601(value), key)

  defp parse_date(_value, key, _default), do: {:error, "#{key} must be a YYYY-MM-DD string"}

  defp iso_date({:ok, date}, _key), do: {:ok, date}
  defp iso_date(_error, key), do: {:error, "#{key} must be a YYYY-MM-DD string"}

  defp string(args, key), do: string_value(Map.get(args, key), key)

  defp string_value(nil, _key), do: {:ok, nil}
  defp string_value(value, _key) when is_binary(value), do: {:ok, value}
  defp string_value(_value, key), do: {:error, "#{key} must be a string"}

  defp boolean(args, key), do: boolean_value(Map.get(args, key), key)

  defp boolean_value(nil, _key), do: {:ok, false}
  defp boolean_value(value, _key) when is_boolean(value), do: {:ok, value}
  defp boolean_value(_value, key), do: {:error, "#{key} must be a boolean"}

  defp limit(args), do: limit_value(Map.get(args, "limit"))

  defp limit_value(nil), do: {:ok, @default_limit}
  defp limit_value(n) when is_integer(n) and n >= 1 and n <= @max_limit, do: {:ok, n}
  defp limit_value(_n), do: {:error, "limit must be an integer between 1 and #{@max_limit}"}
end
