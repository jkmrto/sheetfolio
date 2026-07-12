defmodule Sheetfolio.Checks.NestedCase do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      A `case` nested inside another `case` is hard to follow.

      Extract the inner `case` into a separate function with one clause
      per pattern instead.
      """
    ]

  @impl true
  def run(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:case, meta, args} = ast, issues, issue_meta) when is_list(args) do
    if Enum.any?(args, &contains_case?/1) do
      {ast, [issue_for(issue_meta, meta[:line]) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp contains_case?(ast) do
    ast
    |> Macro.prewalk(false, fn
      {:case, _, _} = node, _acc -> {node, true}
      node, acc -> {node, acc}
    end)
    |> elem(1)
  end

  defp issue_for(issue_meta, line) do
    format_issue(issue_meta,
      message: "Avoid case nested inside case; extract the inner case into a function with pattern-matched clauses.",
      trigger: "case",
      line_no: line
    )
  end
end
