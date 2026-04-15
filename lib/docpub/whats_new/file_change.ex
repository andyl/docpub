defmodule Docpub.WhatsNew.FileChange do
  @moduledoc """
  A single file change between two git commits.
  """

  defstruct [
    :path,
    :previous_path,
    :change,
    :last_commit_sha,
    :last_commit_author,
    :last_commit_date,
    :lines_added,
    :lines_removed
  ]

  @type change :: :added | :modified | :renamed | :deleted

  @type t :: %__MODULE__{
          path: String.t(),
          previous_path: String.t() | nil,
          change: change(),
          last_commit_sha: String.t(),
          last_commit_author: String.t(),
          last_commit_date: DateTime.t(),
          lines_added: non_neg_integer(),
          lines_removed: non_neg_integer()
        }
end
