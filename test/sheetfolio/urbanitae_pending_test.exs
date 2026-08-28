defmodule Sheetfolio.UrbanitaePendingTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.UrbanitaePending

  @projects [
    %{
      "project_key" => "valencia-perez-galdos",
      "city" => "Valencia",
      "project" => "Pérez Galdós"
    },
    %{"project_key" => "lisboa-tomas-ribeiro", "city" => "Lisboa", "project" => "Tomás Ribeiro"}
  ]

  defp distribution(date, project, kind, city \\ nil) do
    %{kind: :distribution, date: date, city: city, project: project, repayment_kind: kind}
  end

  defp repayment(date, key, amount) do
    %{"date" => date, "kind" => "repayment", "project_key" => key, "amount" => amount}
  end

  defp investment(date, key, amount) do
    %{"date" => date, "kind" => "investment", "project_key" => key, "amount" => amount}
  end

  test "a distribution with no repayment recorded is pending" do
    events = [distribution("2026-10-30", "Pérez Galdós", "yield")]

    assert [item] = UrbanitaePending.list(events, [], @projects)

    assert item == %{
             type: :repayment,
             date: "2026-10-30",
             city: "Valencia",
             project: "Pérez Galdós",
             project_key: "valencia-perez-galdos",
             amount: nil,
             repayment_kind: "yield"
           }
  end

  test "ingesting the repayment clears it, whatever the amount turns out to be" do
    events = [distribution("2026-10-30", "Pérez Galdós", "yield")]
    transactions = [repayment("2026-10-30", "valencia-perez-galdos", 81.25)]

    assert UrbanitaePending.list(events, transactions, @projects) == []
  end

  test "a repayment on a different date doesn't clear it" do
    events = [distribution("2026-10-30", "Pérez Galdós", "yield")]
    transactions = [repayment("2026-07-31", "valencia-perez-galdos", 81.25)]

    assert [%{type: :repayment, date: "2026-10-30"}] =
             UrbanitaePending.list(events, transactions, @projects)
  end

  test "a funding close whose investment isn't recorded is pending, with the amount" do
    events = [
      %{
        kind: :funded,
        date: "2026-08-21",
        city: "Lisboa",
        project: "Tomás Ribeiro",
        amount: 1000.00
      }
    ]

    assert [%{type: :investment, amount: 1000.00, project_key: "lisboa-tomas-ribeiro"}] =
             UrbanitaePending.list(events, [], @projects)
  end

  test "a funding close is cleared by an investment of the same total, on any date" do
    events = [
      %{
        kind: :funded,
        date: "2026-08-21",
        city: "Lisboa",
        project: "Tomás Ribeiro",
        amount: 1000.00
      }
    ]

    transactions = [investment("2026-08-20", "lisboa-tomas-ribeiro", 1000.00)]

    assert UrbanitaePending.list(events, transactions, @projects) == []
  end

  test "an email naming a project we don't know is flagged as such" do
    events = [distribution("2026-09-15", "Francos IV", "yield")]

    assert [%{type: :unknown_project, project: "Francos IV", project_key: nil}] =
             UrbanitaePending.list(events, [], @projects)
  end

  test "items come back most recent first" do
    events = [
      distribution("2026-01-28", "Pérez Galdós", "yield"),
      distribution("2026-10-30", "Pérez Galdós", "yield")
    ]

    assert [%{date: "2026-10-30"}, %{date: "2026-01-28"}] =
             UrbanitaePending.list(events, [], @projects)
  end
end
