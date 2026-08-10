defmodule AgentToolPolicy.Access do
  @moduledoc """
  This module provides pure capability-mask semantics for caller-provided agent tool
  universes.

  Each entry identifies an integration or system scope. It selects `:all`, `:read`,
  or `:none`. The entry can add explicit tool names. Callers build universes and
  control credentials, persistence, and baselines.

  Resolution fails closed for malformed stored entries. Use the resulting `MapSet`
  to advertise tools and authorize dispatch.
  """

  @type level :: :all | :read | :none
  @type kind :: :integration | :system

  @typedoc "A parsed mask entry. The `credential_id` and `extra` fields are optional."
  @type entry :: %{
          required(:kind) => kind(),
          required(:scope) => String.t(),
          required(:level) => level(),
          optional(:credential_id) => String.t() | nil,
          optional(:extra) => [String.t()]
        }

  @type tool_access :: [entry()]

  @typedoc "A maskable scope with a read or write classification for each tool."
  @type scope :: %{
          kind: kind(),
          scope: String.t(),
          tools: [%{name: String.t(), read: boolean()}]
        }

  @type universe :: [scope()]

  @typedoc "A scope identity with `kind` and `scope` fields. It does not contain tools."
  @type scope_ref :: %{kind: kind(), scope: String.t()}

  @typedoc "The per-scope default level when a mask has no entry for a scope."
  @type baseline :: (scope_ref() -> level())

  @doc """
  Returns the allowed tool names over `universe`.

  Each scope resolves independently through its matching entry or the caller's
  baseline. The union is the `MapSet` to use for advertisement and dispatch.
  """
  @spec resolve(tool_access(), universe(), baseline()) :: MapSet.t(String.t())
  def resolve(tool_access, universe, baseline) when is_function(baseline, 1) do
    for scope <- universe, reduce: MapSet.new() do
      acc -> MapSet.union(acc, resolve_scope(scope, tool_access, baseline))
    end
  end

  defp resolve_scope(scope, tool_access, baseline) do
    cond do
      entry = entry_for(tool_access, scope) ->
        expand(scope, entry.level, Map.get(entry, :extra, []))

      corrupt_for_scope?(tool_access, scope) ->
        expand(scope, :none, [])

      true ->
        expand(scope, baseline.(scope_ref(scope)), [])
    end
  end

  defp corrupt_for_scope?(tool_access, scope) do
    Enum.any?(tool_access, fn
      %{kind: :__invalid__, scope: nil} -> true
      %{kind: :__invalid__, scope: corrupt_scope} -> corrupt_scope == scope.scope
      _entry -> false
    end)
  end

  defp expand(scope, level, extra) do
    in_scope = MapSet.new(scope.tools, & &1.name)
    extra_set = MapSet.intersection(in_scope, MapSet.new(safe_extra(extra)))

    scope.tools
    |> Enum.filter(&keep_at_level?(&1, level))
    |> MapSet.new(& &1.name)
    |> MapSet.union(extra_set)
  end

  defp keep_at_level?(_tool, :all), do: true
  defp keep_at_level?(tool, :read), do: tool.read
  defp keep_at_level?(_tool, _none), do: false

  defp safe_extra(extra) when is_list(extra), do: Enum.filter(extra, &is_binary/1)
  defp safe_extra(_extra), do: []

  defp scope_ref(%{kind: kind, scope: scope}), do: %{kind: kind, scope: scope}

  defp entry_for(tool_access, scope) do
    Enum.find(tool_access, &(&1.kind == scope.kind and &1.scope == scope.scope))
  end

  @valid_levels [:all, :read, :none]

  @doc """
  Parses the string-keyed stored representation into the atom-keyed policy shape.

  Unknown kinds and levels become the `:__invalid__` sentinel without creating
  atoms. Non-map entries also become an invalid sentinel. `resolve/3` treats these
  sentinels as denials. `validate/2` reports them.
  """
  @spec parse([map()] | tool_access()) :: tool_access()
  def parse(tool_access) when is_list(tool_access), do: Enum.map(tool_access, &parse_entry/1)

  defp parse_entry(%{kind: _} = entry), do: entry

  defp parse_entry(entry) when is_map(entry) do
    base = %{
      kind: parse_kind(entry["kind"]),
      scope: entry["scope"],
      level: parse_level(entry["level"]),
      extra: entry["extra"] || []
    }

    case entry["credential_id"] do
      nil -> base
      credential_id -> Map.put(base, :credential_id, credential_id)
    end
  end

  defp parse_entry(_entry),
    do: %{kind: :__invalid__, scope: nil, level: :__invalid__, extra: []}

  defp parse_kind("integration"), do: :integration
  defp parse_kind("system"), do: :system
  defp parse_kind(_kind), do: :__invalid__

  defp parse_level("all"), do: :all
  defp parse_level("read"), do: :read
  defp parse_level("none"), do: :none
  defp parse_level(_level), do: :__invalid__

  @doc "Renders a parsed mask to the string-keyed stored representation."
  @spec dump(tool_access()) :: [map()]
  def dump(tool_access) when is_list(tool_access), do: Enum.map(tool_access, &dump_entry/1)

  defp dump_entry(entry) do
    base = %{
      "kind" => Atom.to_string(entry.kind),
      "scope" => entry.scope,
      "level" => Atom.to_string(entry.level),
      "extra" => Map.get(entry, :extra, [])
    }

    case Map.get(entry, :credential_id) do
      nil -> base
      credential_id -> Map.put(base, "credential_id", credential_id)
    end
  end

  @doc """
  Validates that each mask entry is well-formed and belongs to `universe`.
  """
  @spec validate(tool_access(), universe()) :: :ok | {:error, String.t()}
  def validate(tool_access, universe) when is_list(tool_access) do
    Enum.reduce_while(tool_access, :ok, fn entry, :ok ->
      case validate_entry(entry, universe) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_entry(%{level: level}, _universe) when level not in @valid_levels,
    do: {:error, "invalid level: #{inspect(level)}"}

  defp validate_entry(%{kind: kind}, _universe) when kind not in [:integration, :system],
    do: {:error, "invalid kind: #{inspect(kind)}"}

  defp validate_entry(%{kind: kind, scope: scope} = entry, universe) do
    case Enum.find(universe, &(&1.kind == kind and &1.scope == scope)) do
      nil ->
        {:error, "unknown scope: #{kind}/#{scope}"}

      universe_scope ->
        validate_extra(Map.get(entry, :extra, []), universe_scope)
    end
  end

  defp validate_entry(_entry, _universe), do: {:error, "malformed tool_access entry"}

  defp validate_extra(extra, universe_scope) when is_list(extra) do
    names = MapSet.new(universe_scope.tools, & &1.name)

    case Enum.reject(extra, &MapSet.member?(names, &1)) do
      [] ->
        :ok

      unknown ->
        {:error, "tools not in scope #{universe_scope.scope}: #{Enum.join(unknown, ", ")}"}
    end
  end

  defp validate_extra(_extra, _universe_scope),
    do: {:error, "extra must be a list of tool names"}

  @typedoc "Selected tool names for each scope. Editors use this type as working state."
  @type selection :: [
          %{
            required(:kind) => kind(),
            required(:scope) => String.t(),
            required(:tools) => [String.t()],
            optional(:credential_id) => String.t() | nil
          }
        ]

  @doc """
  Folds a per-scope selection into the most permissive equivalent mask.

  A full scope becomes `:all`. All reads with optional writes become `:read`. Other
  selections become `:none` with sorted `extra` values.
  """
  @spec fold(selection(), universe()) :: tool_access()
  def fold(selection, universe) do
    Enum.map(selection, &fold_scope(&1, universe))
  end

  defp fold_scope(%{kind: kind, scope: scope, tools: selected} = selection, universe) do
    {level, extra} =
      case Enum.find(universe, &(&1.kind == kind and &1.scope == scope)) do
        nil -> {:none, Enum.sort(selected)}
        universe_scope -> fold_level(universe_scope, selected)
      end

    base = %{kind: kind, scope: scope, level: level, extra: extra}

    case Map.get(selection, :credential_id) do
      nil -> base
      credential_id -> Map.put(base, :credential_id, credential_id)
    end
  end

  @doc """
  Canonicalizes a mask and drops entries equal to their caller-supplied baseline.

  `normalize/3` never removes a credential-bearing entry because it matches the baseline.
  """
  @spec normalize(tool_access(), universe(), baseline()) :: tool_access()
  def normalize(tool_access, universe, baseline) when is_function(baseline, 1) do
    tool_access
    |> Enum.map(&entry_to_selection(&1, universe))
    |> Enum.reject(&is_nil/1)
    |> fold(universe)
    |> Enum.reject(&baseline_entry?(&1, baseline))
  end

  defp entry_to_selection(entry, universe) do
    case Enum.find(universe, &(&1.kind == entry.kind and &1.scope == entry.scope)) do
      nil ->
        nil

      scope ->
        selection = %{
          kind: entry.kind,
          scope: entry.scope,
          tools: scope |> expand(entry.level, Map.get(entry, :extra, [])) |> MapSet.to_list()
        }

        case Map.get(entry, :credential_id) do
          nil -> selection
          credential_id -> Map.put(selection, :credential_id, credential_id)
        end
    end
  end

  defp baseline_entry?(%{credential_id: _credential_id}, _baseline), do: false

  defp baseline_entry?(entry, baseline) do
    entry.extra == [] and entry.level == baseline.(scope_ref(entry))
  end

  defp fold_level(universe_scope, selected) do
    all = MapSet.new(universe_scope.tools, & &1.name)
    reads = universe_scope.tools |> Enum.filter(& &1.read) |> MapSet.new(& &1.name)
    selection = MapSet.intersection(all, MapSet.new(selected))

    cond do
      MapSet.equal?(selection, all) ->
        {:all, []}

      not Enum.empty?(reads) and MapSet.subset?(reads, selection) ->
        {:read, selection |> MapSet.difference(reads) |> Enum.sort()}

      true ->
        {:none, Enum.sort(selection)}
    end
  end
end
