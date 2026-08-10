defmodule AgentToolPolicy.ActionPolicy do
  @moduledoc """
  This module provides deterministic pre-dispatch policy for caller-classified agent
  tool actions.

  The caller supplies the action class, autonomy posture, allowlist result, and
  optional guard result. This module returns `:allow` for internal work. It returns
  `:act` or `:gate` for outward work.
  """

  @type action_class :: %{
          surface: :internal | :outward,
          reversible: boolean(),
          time_sensitive: boolean()
        }
  @type posture :: :safe | :auto
  @type guard :: :allow | :block
  @type verdict :: :allow | :act | :gate
  @type input :: %{
          required(:class) => action_class(),
          required(:posture) => posture(),
          required(:allowlisted?) => boolean(),
          optional(:guard) => guard()
        }

  @doc "Decides the pre-dispatch verdict for a classified action."
  @spec decide(input()) :: verdict()
  def decide(%{class: %{surface: :internal}}), do: :allow

  def decide(%{class: %{surface: :outward}, allowlisted?: true}), do: :act

  def decide(%{class: %{surface: :outward, reversible: reversible?}, posture: :safe}),
    do: if(reversible?, do: :act, else: :gate)

  def decide(%{class: %{surface: :outward}, posture: :auto} = input),
    do: if(Map.get(input, :guard) == :block, do: :gate, else: :act)
end
