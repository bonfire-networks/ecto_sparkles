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

  By default this function does not restrict atoms, except if compiled in prod env, then the [:safe] option is set, so only existing (and loaded) atoms will be deserialized.
  """
  if Application.compile_env!(:ecto_sparkles, :env)==:prod do
    IO.puts("EctoSparkles.ErlangTermBinary: will be used in safe mode")
    def load(raw_binary) when is_binary(raw_binary) do
      {:ok, Plug.Crypto.non_executable_binary_to_term(raw_binary, [:safe])} 
    rescue 
      e in ArgumentError -> 
        # FIXME: find another approach 
        error(e, "!!! Could not deserialize term from DB, falling back to unsafe")
        {:ok, Plug.Crypto.non_executable_binary_to_term(raw_binary) |> info()} 
    end
  else
    IO.puts("EctoSparkles.ErlangTermBinary: will be used in unsafe mode")
    def load(raw_binary) when is_binary(raw_binary),
      do: {:ok, Plug.Crypto.non_executable_binary_to_term(raw_binary)} 
  end

  @doc """
  Converting the data structure to binary for storage.
  """
  def dump(term), do: {:ok, :erlang.term_to_binary(term)}
end
