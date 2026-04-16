defmodule Docpub.WhatsNew.Hunk do
  @moduledoc """
  A contiguous range of changed lines in the new (post-image) version of a file.

  `kind` is `:added` when the hunk has no corresponding old-side lines (pure
  addition), `:modified` otherwise.
  """

  defstruct [:kind, :start_line, :end_line]

  @type kind :: :added | :modified

  @type t :: %__MODULE__{
          kind: kind(),
          start_line: pos_integer(),
          end_line: pos_integer()
        }
end
