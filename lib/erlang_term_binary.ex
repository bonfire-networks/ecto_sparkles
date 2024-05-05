defmodule EctoSparkles.ErlangTermBinary do
  @moduledoc """
  A custom Ecto type for handling the serialization of arbitrary
  data types stored as binary data in the database. Requires the
  underlying DB field to be a binary.
  """
  use Ecto.Type
  import Untangle

  def type, do: :binary

  @doc """
  Provides custom casting rules for params. Nothing changes here.
  We only need to handle deserialization.
  """
  def cast(:any, term), do: {:ok, term}
  def cast(term), do: {:ok, term}

  @doc """
  Convert the raw binary value from the database back to
  the desired term.

  Uses `Plug.Crypto.non_executable_binary_to_term/2` - a restricted version of `:erlang.binary_to_term/2` that forbids executable terms, such as anonymous functions.

  This function restricts atoms, with the [:safe] option set, so only existing (and loaded) atoms will be deserialized.
  """
    def load(raw_binary) when is_binary(raw_binary) do
      {:ok, Plug.Crypto.non_executable_binary_to_term(raw_binary, [:safe])} 
    rescue 
      e in ArgumentError -> 
        # FIXME: find a workaround for an atom saved in DB in a previous version of the app, when it not longer exists in the currently compiled version 
        error(e, "!!! Could not deserialize term from DB")
        # {:ok, Plug.Crypto.non_executable_binary_to_term(raw_binary) |> info()} 
    end


  @doc """
  Converting the data structure to binary for storage.
  """
  def dump(term), do: {:ok, :erlang.term_to_binary(term)}
end
