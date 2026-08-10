defmodule AgentToolPolicy.AccessTest do
  use ExUnit.Case, async: true

  alias AgentToolPolicy.Access, as: ToolAccess

  defp universe do
    [
      %{
        kind: :integration,
        scope: "slack",
        tools: [
          %{name: "slack__list_messages", read: true},
          %{name: "slack__post_message", read: false}
        ]
      },
      %{
        kind: :system,
        scope: "workflow",
        tools: [
          %{name: "validate_workflow", read: true},
          %{name: "create_workflow", read: false}
        ]
      }
    ]
  end

  defp all_baseline(_scope), do: :all

  describe "resolve/3" do
    test "empty tool_access resolves to the full universe (unrestricted)" do
      assert ToolAccess.resolve([], universe(), &all_baseline/1) ==
               MapSet.new(
                 ~w(slack__list_messages slack__post_message validate_workflow create_workflow)
               )
    end

    test "level :none drops every tool in that scope" do
      allowed =
        ToolAccess.resolve(
          [%{kind: :integration, scope: "slack", level: :none, extra: []}],
          universe(),
          &all_baseline/1
        )

      refute "slack__list_messages" in allowed
      refute "slack__post_message" in allowed
      assert "validate_workflow" in allowed
      assert "create_workflow" in allowed
    end

    test "level :read keeps only the scope's read tools" do
      allowed =
        ToolAccess.resolve(
          [%{kind: :integration, scope: "slack", level: :read, extra: []}],
          universe(),
          &all_baseline/1
        )

      assert "slack__list_messages" in allowed
      refute "slack__post_message" in allowed
    end

    test "level :read plus extra writes adds those writes back on top of the live read set" do
      access = [
        %{kind: :integration, scope: "slack", level: :read, extra: ["slack__post_message"]}
      ]

      allowed = ToolAccess.resolve(access, universe(), &all_baseline/1)
      assert "slack__list_messages" in allowed
      assert "slack__post_message" in allowed
    end

    test "level :none plus extra expresses a fully-custom set" do
      access = [
        %{kind: :integration, scope: "slack", level: :none, extra: ["slack__post_message"]}
      ]

      allowed = ToolAccess.resolve(access, universe(), &all_baseline/1)
      refute "slack__list_messages" in allowed
      assert "slack__post_message" in allowed
    end

    test "a :read mask is live — a newly-introduced read tool is included automatically" do
      access = [%{kind: :integration, scope: "slack", level: :read, extra: []}]

      grown =
        Enum.map(universe(), fn
          %{scope: "slack"} = scope ->
            %{scope | tools: scope.tools ++ [%{name: "slack__search", read: true}]}

          scope ->
            scope
        end)

      assert "slack__search" in ToolAccess.resolve(access, grown, &all_baseline/1)
    end

    test "an unmentioned scope falls back to its per-scope baseline" do
      baseline = fn
        %{kind: :integration} -> :all
        %{kind: :system} -> :none
      end

      allowed = ToolAccess.resolve([], universe(), baseline)
      assert "slack__list_messages" in allowed
      assert "slack__post_message" in allowed
      refute "validate_workflow" in allowed
      refute "create_workflow" in allowed
    end

    test "the workflow Staple slug and the workflow built-in group do not collide (kind-discriminated)" do
      universe = [
        %{
          kind: :integration,
          scope: "workflow",
          tools: [%{name: "workflow__schedule", read: false}]
        },
        %{kind: :system, scope: "workflow", tools: [%{name: "create_workflow", read: false}]}
      ]

      access = [%{kind: :system, scope: "workflow", level: :none, extra: []}]
      allowed = ToolAccess.resolve(access, universe, &all_baseline/1)
      assert "workflow__schedule" in allowed
      refute "create_workflow" in allowed
    end

    test "an explicit scope entry takes precedence over the baseline" do
      access = [%{kind: :integration, scope: "slack", level: :read, extra: []}]
      allowed = ToolAccess.resolve(access, universe(), &all_baseline/1)
      assert "slack__list_messages" in allowed
      refute "slack__post_message" in allowed
    end

    test "a corrupted (parse-sentinel) level fails closed — the scope is denied, not crashed" do
      access =
        ToolAccess.parse([%{"kind" => "integration", "scope" => "slack", "level" => "evil"}])

      allowed = ToolAccess.resolve(access, universe(), &all_baseline/1)
      refute "slack__list_messages" in allowed
      refute "slack__post_message" in allowed
      assert "validate_workflow" in allowed
    end

    test "a corrupted (parse-sentinel) kind fails closed for the scope it names" do
      access =
        ToolAccess.parse([
          %{"kind" => "evil", "scope" => "slack", "level" => "none", "extra" => []}
        ])

      allowed = ToolAccess.resolve(access, universe(), &all_baseline/1)
      refute "slack__list_messages" in allowed
      refute "slack__post_message" in allowed
      assert "validate_workflow" in allowed
    end

    test "a non-map mask entry (no scope to attribute) fails closed for EVERY scope" do
      assert ToolAccess.parse([42])
             |> ToolAccess.resolve(universe(), &all_baseline/1) == MapSet.new()
    end

    test "a non-list extra does not crash runtime resolve (coerced to empty)" do
      access =
        ToolAccess.parse([
          %{"kind" => "integration", "scope" => "slack", "level" => "read", "extra" => "oops"}
        ])

      allowed = ToolAccess.resolve(access, universe(), &all_baseline/1)
      assert "slack__list_messages" in allowed
      refute "slack__post_message" in allowed
    end

    test "a credential_id on an entry is accepted but ignored on the agent surface" do
      access = [
        %{kind: :integration, scope: "slack", credential_id: "cred-123", level: :read, extra: []}
      ]

      allowed = ToolAccess.resolve(access, universe(), &all_baseline/1)
      assert "slack__list_messages" in allowed
      refute "slack__post_message" in allowed
    end
  end

  describe "validate/2" do
    test "an empty mask is valid" do
      assert ToolAccess.validate([], universe()) == :ok
    end

    test "well-formed entries over known scopes and tools are valid" do
      access = [
        %{kind: :integration, scope: "slack", level: :read, extra: ["slack__post_message"]},
        %{kind: :system, scope: "workflow", level: :none, extra: []}
      ]

      assert ToolAccess.validate(access, universe()) == :ok
    end

    test "rejects an unknown scope" do
      access = [%{kind: :integration, scope: "nope", level: :all, extra: []}]

      assert ToolAccess.validate(access, universe()) ==
               {:error, "unknown scope: integration/nope"}
    end

    test "rejects a scope whose kind doesn't match the universe (workflow collision)" do
      universe = [
        %{kind: :system, scope: "workflow", tools: [%{name: "create_workflow", read: false}]}
      ]

      access = [%{kind: :integration, scope: "workflow", level: :all, extra: []}]

      assert ToolAccess.validate(access, universe) ==
               {:error, "unknown scope: integration/workflow"}
    end

    test "rejects an extra tool that is out of the scope's universe" do
      access = [%{kind: :integration, scope: "slack", level: :read, extra: ["slack__nuke"]}]

      assert ToolAccess.validate(access, universe()) ==
               {:error, "tools not in scope slack: slack__nuke"}
    end

    test "rejects an extra tool that belongs to a different scope" do
      access = [%{kind: :integration, scope: "slack", level: :read, extra: ["create_workflow"]}]

      assert ToolAccess.validate(access, universe()) ==
               {:error, "tools not in scope slack: create_workflow"}
    end

    test "rejects a bad level" do
      access = [%{kind: :integration, scope: "slack", level: :sometimes, extra: []}]
      assert ToolAccess.validate(access, universe()) == {:error, "invalid level: :sometimes"}
    end

    test "rejects a bad kind" do
      access = [%{kind: :wat, scope: "slack", level: :all, extra: []}]
      assert ToolAccess.validate(access, universe()) == {:error, "invalid kind: :wat"}
    end
  end

  describe "parse/1" do
    test "parses the stored jsonb shape (string keys/values) into the internal shape" do
      stored = [
        %{
          "kind" => "integration",
          "scope" => "slack",
          "level" => "read",
          "extra" => ["slack__post_message"]
        }
      ]

      assert ToolAccess.parse(stored) == [
               %{
                 kind: :integration,
                 scope: "slack",
                 level: :read,
                 extra: ["slack__post_message"]
               }
             ]
    end

    test "carries credential_id through and defaults a missing extra to []" do
      stored = [
        %{"kind" => "integration", "scope" => "slack", "level" => "all", "credential_id" => "c1"}
      ]

      assert ToolAccess.parse(stored) == [
               %{
                 kind: :integration,
                 scope: "slack",
                 level: :all,
                 extra: [],
                 credential_id: "c1"
               }
             ]
    end

    test "maps unknown kind/level to a sentinel validate rejects (no atom exhaustion)" do
      parsed = ToolAccess.parse([%{"kind" => "evil", "scope" => "slack", "level" => "sneaky"}])
      assert ToolAccess.validate(parsed, universe()) == {:error, "invalid level: :__invalid__"}
    end

    test "an already-atomized mask passes through unchanged (idempotent)" do
      access = [%{kind: :integration, scope: "slack", level: :read, extra: []}]
      assert ToolAccess.parse(access) == access
    end
  end

  describe "dump/1" do
    test "renders the internal shape to the stored jsonb shape (string keys/values)" do
      access = [
        %{kind: :integration, scope: "slack", level: :read, extra: ["slack__post_message"]}
      ]

      assert ToolAccess.dump(access) == [
               %{
                 "kind" => "integration",
                 "scope" => "slack",
                 "level" => "read",
                 "extra" => ["slack__post_message"]
               }
             ]
    end

    test "round-trips with parse" do
      access = [
        %{kind: :system, scope: "workflow", level: :none, extra: []},
        %{kind: :integration, scope: "slack", credential_id: "c1", level: :all, extra: []}
      ]

      assert access |> ToolAccess.dump() |> ToolAccess.parse() == access
    end
  end

  describe "fold/2" do
    defp select(kind, scope, names), do: %{kind: kind, scope: scope, tools: names}

    test "a fully-selected scope folds to level :all" do
      selection = [select(:integration, "slack", ~w(slack__list_messages slack__post_message))]

      assert ToolAccess.fold(selection, universe()) ==
               [%{kind: :integration, scope: "slack", level: :all, extra: []}]
    end

    test "exactly the read tools fold to level :read" do
      selection = [select(:integration, "slack", ~w(slack__list_messages))]

      assert ToolAccess.fold(selection, universe()) ==
               [%{kind: :integration, scope: "slack", level: :read, extra: []}]
    end

    test "all reads plus some-but-not-all writes fold to read + extra (live read, explicit writes)" do
      universe = [
        %{
          kind: :integration,
          scope: "gh",
          tools: [
            %{name: "gh__list", read: true},
            %{name: "gh__create", read: false},
            %{name: "gh__delete", read: false}
          ]
        }
      ]

      assert ToolAccess.fold([select(:integration, "gh", ~w(gh__list gh__create))], universe) ==
               [%{kind: :integration, scope: "gh", level: :read, extra: ["gh__create"]}]
    end

    test "read tools minus one fold to an explicit none + extra (not live)" do
      universe = [
        %{
          kind: :integration,
          scope: "gh",
          tools: [
            %{name: "gh__list", read: true},
            %{name: "gh__get", read: true},
            %{name: "gh__create", read: false}
          ]
        }
      ]

      assert ToolAccess.fold([select(:integration, "gh", ~w(gh__list))], universe) ==
               [%{kind: :integration, scope: "gh", level: :none, extra: ["gh__list"]}]
    end

    test "an empty selection folds to level :none with no extra" do
      assert ToolAccess.fold([select(:integration, "slack", [])], universe()) ==
               [%{kind: :integration, scope: "slack", level: :none, extra: []}]
    end

    test "round-trips: resolving a folded selection yields the same selected set" do
      universe = [
        %{
          kind: :integration,
          scope: "gh",
          tools: [
            %{name: "gh__list", read: true},
            %{name: "gh__get", read: true},
            %{name: "gh__create", read: false}
          ]
        }
      ]

      for names <- [
            ~w(),
            ~w(gh__list),
            ~w(gh__list gh__get),
            ~w(gh__list gh__get gh__create),
            ~w(gh__list gh__create)
          ] do
        folded = ToolAccess.fold([select(:integration, "gh", names)], universe)
        assert ToolAccess.resolve(folded, universe, fn _scope -> :all end) == MapSet.new(names)
      end
    end

    test "preserves credential_id on a lent selection (Slice B forward-compat)" do
      selection = [
        %{
          kind: :integration,
          scope: "slack",
          credential_id: "cred-1",
          tools: ~w(slack__list_messages)
        }
      ]

      assert ToolAccess.fold(selection, universe()) == [
               %{
                 kind: :integration,
                 scope: "slack",
                 credential_id: "cred-1",
                 level: :read,
                 extra: []
               }
             ]
    end
  end

  describe "normalize/3" do
    defp agent_baseline(_scope), do: :all

    test "re-canonicalizes a naive mask to the most-live form" do
      access = [
        %{kind: :integration, scope: "slack", level: :none, extra: ["slack__list_messages"]}
      ]

      assert ToolAccess.normalize(access, universe(), &agent_baseline/1) ==
               [%{kind: :integration, scope: "slack", level: :read, extra: []}]
    end

    test "prunes a scope that equals the baseline (keeps storage minimal)" do
      access = [%{kind: :integration, scope: "slack", level: :all, extra: []}]
      assert ToolAccess.normalize(access, universe(), &agent_baseline/1) == []
    end

    test "drops an entry whose scope isn't in the universe (defensive)" do
      access = [%{kind: :integration, scope: "ghost", level: :none, extra: []}]
      assert ToolAccess.normalize(access, universe(), &agent_baseline/1) == []
    end

    test "is idempotent on an already-normalized mask" do
      access = [%{kind: :integration, scope: "slack", level: :read, extra: []}]
      once = ToolAccess.normalize(access, universe(), &agent_baseline/1)
      assert ToolAccess.normalize(once, universe(), &agent_baseline/1) == once
    end
  end
end
