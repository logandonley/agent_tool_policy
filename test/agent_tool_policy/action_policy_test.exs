defmodule AgentToolPolicy.ActionPolicyTest do
  use ExUnit.Case, async: true

  alias AgentToolPolicy.ActionPolicy

  defp internal, do: %{surface: :internal, reversible: false, time_sensitive: false}
  defp reversible_outward, do: %{surface: :outward, reversible: true, time_sensitive: false}
  defp irreversible_outward, do: %{surface: :outward, reversible: false, time_sensitive: false}

  describe "internal work" do
    test "runs free regardless of posture" do
      assert ActionPolicy.decide(%{class: internal(), posture: :safe, allowlisted?: false}) ==
               :allow

      assert ActionPolicy.decide(%{class: internal(), posture: :auto, allowlisted?: false}) ==
               :allow
    end
  end

  describe "safe posture" do
    test "an irreversible outward action gates" do
      assert ActionPolicy.decide(%{
               class: irreversible_outward(),
               posture: :safe,
               allowlisted?: false
             }) == :gate
    end

    test "a reversible outward action acts" do
      assert ActionPolicy.decide(%{
               class: reversible_outward(),
               posture: :safe,
               allowlisted?: false
             }) == :act
    end
  end

  describe "allowlist" do
    test "an allowlisted outward action acts even in safe posture" do
      assert ActionPolicy.decide(%{
               class: irreversible_outward(),
               posture: :safe,
               allowlisted?: true
             }) == :act
    end

    test "an allowlisted auto action acts even when a supplied guard blocks" do
      assert ActionPolicy.decide(%{
               class: irreversible_outward(),
               posture: :auto,
               allowlisted?: true,
               guard: :block
             }) == :act
    end
  end

  describe "auto posture" do
    test "an outward action the Action Guard allows acts" do
      assert ActionPolicy.decide(%{
               class: irreversible_outward(),
               posture: :auto,
               allowlisted?: false,
               guard: :allow
             }) == :act
    end

    test "an outward action the Action Guard blocks gates" do
      assert ActionPolicy.decide(%{
               class: irreversible_outward(),
               posture: :auto,
               allowlisted?: false,
               guard: :block
             }) == :gate
    end

    test "an outward action acts when guard is omitted" do
      assert ActionPolicy.decide(%{
               class: irreversible_outward(),
               posture: :auto,
               allowlisted?: false
             }) == :act
    end
  end
end
