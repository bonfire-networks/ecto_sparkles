defmodule EctoSparkles.ErlangTermBinary do
  @moduledoc """
  A custom Ecto type for handling the serialization of arbitrary
  data types stored as binary data in the database. Requires the
  underlying DB field to be a binary.
  """
  use Ecto.Type

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
  """
  def load(raw_binary) when is_binary(raw_binary),
    do: {:ok, :erlang.binary_to_term(raw_binary)}

  @doc """
  Converting the data structure to binary for storage.
  """
  def dump(term), do: {:ok, :erlang.term_to_binary(term)}
end
