# AgentToolPolicy

`AgentToolPolicy` provides capability masks for AI agent tool calls. It also provides
deterministic pre-dispatch policy. The library has no runtime dependencies. The
caller owns application catalogs, persistence, classification, execution, and audits.

This library is not an execution sandbox, authorization provider, credential store,
or model classifier.

## Installation

Add the Hex package to `mix.exs`:

```elixir
def deps do
  [
    {:agent_tool_policy, "~> 0.1.0"}
  ]
end
```

Or pin the tagged Git source:

```elixir
def deps do
  [
    {:agent_tool_policy,
     git: "https://github.com/logandonley/agent_tool_policy.git", tag: "v0.1.0"}
  ]
end
```

## Tool-access masks

The caller supplies the tool universe and a baseline function. A mask narrows each
integration or system scope to all tools, live read tools, or an explicit set.

```elixir
alias AgentToolPolicy.Access

universe = [
  %{
    kind: :integration,
    scope: "mail",
    tools: [
      %{name: "mail__list", read: true},
      %{name: "mail__send", read: false}
    ]
  }
]

baseline = fn _scope -> :all end
stored = [%{"kind" => "integration", "scope" => "mail", "level" => "read"}]
allowed = stored |> Access.parse() |> Access.resolve(universe, baseline)
# => MapSet.new(["mail__list"])
```

Use the resolved `MapSet` to filter advertised tool specifications. Use it again to
authorize each dispatch. Filtering advertised tools is not enough. A model or caller
can still propose a hidden tool by name.

`resolve/3` fails closed when it encounters malformed stored entries. It does not
require a validation call. An invalid entry denies its named scope. A malformed
non-map entry denies the entire universe.

Write paths should still validate masks. Call `AgentToolPolicy.Access.validate/2`,
then `AgentToolPolicy.Access.normalize/3` and `AgentToolPolicy.Access.dump/1` before
persistence.

The library passes the opaque `credential_id` field through unchanged. It does not
resolve or authorize credentials.

## Autonomous-action policy

The caller classifies an action using plain data:

```elixir
class = %{surface: :outward, reversible: false, time_sensitive: true}
```

`ActionPolicy.decide/1` applies deterministic precedence to the class, caller-owned
posture, allowlist result, and optional guard result:

```elixir
alias AgentToolPolicy.ActionPolicy

ActionPolicy.decide(%{
  class: class,
  posture: :safe,
  allowlisted?: false
})
# => :gate
```

Applications select evaluator modules explicitly and pass them to
`ActionGuard.evaluate/2`:

```elixir
alias AgentToolPolicy.{ActionGuard, ActionPolicy}

action = %{name: "mail__send", arguments: %{}, class: class, ctx: %{org_id: "org-1"}}
finding = ActionGuard.evaluate(action, [MyApp.OutboundSafetyEvaluator])

guard = if finding.verdict == :block, do: :block, else: :allow

ActionPolicy.decide(%{
  class: class,
  posture: :auto,
  allowlisted?: false,
  guard: guard
})
```

A shadow evaluator's block becomes a flag. Enforced blocks outrank flags. Flags
outrank allows. The guard retains the first reason at the winning severity. The
caller owns evaluator selection, configuration, failure containment, and evaluator
safety.

## Responsibility boundary

The caller owns tool catalogs, principal baselines, and credential authorization.
The caller defines action classifications and allowlist policy. The caller selects
and configures evaluators. The caller also handles evaluator failures. The caller
controls persistence, receipts, approvals, and undo execution. The caller provides
audit events, telemetry, and dispatch enforcement.

The library does not recover from malformed action-policy input. It does not catch
evaluator exceptions. It does not normalize malformed evaluator results. These
failures propagate to the caller.

## License

MIT License. See the repository's `LICENSE` file.
