defmodule AgentToolPolicy.ActionEvaluator do
  @moduledoc """
  This behaviour defines caller-selected inspectors for pending agent tool actions.

  Evaluators can implement `mode/0` as `:enforce` or `:shadow`. An enforced block
  can gate execution. A shadow block becomes a flag. `mode/0` is optional.
  `AgentToolPolicy.ActionGuard` uses `:enforce` by default.
  """

  @typedoc "This type represents an action under review. The caller-defined `ctx` remains opaque."
  @type action :: %{
          required(:name) => String.t(),
          required(:arguments) => map(),
          required(:class) => AgentToolPolicy.ActionPolicy.action_class(),
          optional(:ctx) => map()
        }

  @typedoc "A finding includes a verdict and an optional reason."
  @type finding :: %{verdict: :safe | :flag | :block, reason: String.t() | nil}

  @callback evaluate(action()) :: finding()
  @callback mode() :: :shadow | :enforce

  @optional_callbacks mode: 0
end
