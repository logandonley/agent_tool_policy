defmodule AgentToolPolicy.ActionGuardTest do
  use ExUnit.Case, async: true

  alias AgentToolPolicy.ActionEvaluator
  alias AgentToolPolicy.ActionGuard

  defmodule SafeEval do
    @behaviour ActionEvaluator
    @impl ActionEvaluator
    def evaluate(_action), do: %{verdict: :safe, reason: nil}
  end

  defmodule BlockEval do
    @behaviour ActionEvaluator
    @impl ActionEvaluator
    def evaluate(_action), do: %{verdict: :block, reason: "emails an external party"}
  end

  defmodule FlagEval do
    @behaviour ActionEvaluator
    @impl ActionEvaluator
    def evaluate(_action), do: %{verdict: :flag, reason: "worth a glance"}
  end

  defmodule ShadowBlockEval do
    @behaviour ActionEvaluator
    @impl ActionEvaluator
    def evaluate(_action), do: %{verdict: :block, reason: "shadow says block"}
    @impl ActionEvaluator
    def mode, do: :shadow
  end

  @action %{
    name: "outward__send",
    arguments: %{},
    class: %{surface: :outward, reversible: false, time_sensitive: false}
  }

  test "allows when every evaluator finds the action safe" do
    assert %{verdict: :allow} = ActionGuard.evaluate(@action, [SafeEval])
  end

  test "blocks when an enforce evaluator blocks (the block carries its reason)" do
    assert %{verdict: :block, reason: reason} =
             ActionGuard.evaluate(@action, [SafeEval, BlockEval])

    assert reason =~ "external party"
  end

  test "flags (does not block) when an evaluator only flags" do
    assert %{verdict: :flag} = ActionGuard.evaluate(@action, [SafeEval, FlagEval])
  end

  test "a shadow-mode evaluator can only flag, never block" do
    assert %{verdict: :flag} = ActionGuard.evaluate(@action, [ShadowBlockEval])
  end

  test "an empty evaluator list allows" do
    assert ActionGuard.evaluate(@action, []) == %{verdict: :allow, reason: nil}
  end

  test "an enforce block outranks an earlier flag and supplies the block reason" do
    assert ActionGuard.evaluate(@action, [FlagEval, BlockEval]) == %{
             verdict: :block,
             reason: "emails an external party"
           }
  end
end
