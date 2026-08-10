defmodule AgentToolPolicy.ActionGuard do
  @moduledoc """
  This module aggregates caller-selected `AgentToolPolicy.ActionEvaluator` findings.

  Evaluators run in list order. Enforced blocks outrank flags. Flags outrank allows.
  A shadow block becomes a flag. The guard retains the first reason at the winning
  severity.
  """

  alias AgentToolPolicy.ActionEvaluator

  @type verdict :: %{verdict: :allow | :flag | :block, reason: String.t() | nil}

  @doc "Evaluates an action with the supplied evaluator modules."
  @spec evaluate(ActionEvaluator.action(), [module()]) :: verdict()
  def evaluate(action, evaluators) do
    evaluators
    |> Enum.map(fn evaluator -> clamp(mode(evaluator), evaluator.evaluate(action)) end)
    |> aggregate()
  end

  defp aggregate(findings) do
    cond do
      finding = Enum.find(findings, &(&1.verdict == :block)) ->
        %{verdict: :block, reason: finding.reason}

      finding = Enum.find(findings, &(&1.verdict == :flag)) ->
        %{verdict: :flag, reason: finding.reason}

      true ->
        %{verdict: :allow, reason: nil}
    end
  end

  defp clamp(:shadow, %{verdict: :block} = finding), do: %{finding | verdict: :flag}
  defp clamp(_mode, finding), do: finding

  defp mode(evaluator) do
    if function_exported?(evaluator, :mode, 0), do: evaluator.mode(), else: :enforce
  end
end
