defmodule Docpub.WhatsNew.Summary do
  @moduledoc """
  Structured change summary between two vault commits.
  """

  alias Docpub.WhatsNew.FileChange

  defstruct kind: :no_baseline,
            from_commit: nil,
            to_commit: nil,
            from_date: nil,
            to_date: nil,
            files: [],
            counts: %{added: 0, modified: 0, renamed: 0, deleted: 0}

  @type kind :: :diff | :empty | :no_baseline

  @type t :: %__MODULE__{
          kind: kind(),
          from_commit: String.t() | nil,
          to_commit: String.t() | nil,
          from_date: DateTime.t() | nil,
          to_date: DateTime.t() | nil,
          files: [FileChange.t()],
          counts: %{added: integer, modified: integer, renamed: integer, deleted: integer}
        }

  @doc """
  Builds the counts map from a list of file changes.
  """
  @spec counts_from([FileChange.t()]) :: map()
  def counts_from(files) do
    base = %{added: 0, modified: 0, renamed: 0, deleted: 0}

    Enum.reduce(files, base, fn %FileChange{change: c}, acc ->
      Map.update!(acc, c, &(&1 + 1))
    end)
  end
end
