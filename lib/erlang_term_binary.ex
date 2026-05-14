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
      clean_and_load(raw_binary)
  end

  def clean_and_load(raw_binary) when is_binary(raw_binary) do
    case rewrite_atoms_to_binaries(raw_binary) do
      {:ok, rewritten} ->
        {:ok, Plug.Crypto.non_executable_binary_to_term(rewritten, [:safe])}

      {:error, reason} ->
        error(reason, "Could not deserialize term from DB (ETF cleanup failed")
    end
  rescue
    e in ArgumentError ->
      error(e, "Could not deserialize term from DB (cleanup still resulted in invalid binary format)")
  end

  # Rewrite ETF bytes: known atoms kept as atoms, unknown atoms → BINARY_EXT strings.
  # This allows safe deserialization of terms containing atoms from old app versions.

  defp rewrite_atoms_to_binaries(<<131, rest::binary>>) do
    case rewrite_term(rest) do
      {rewritten, _} -> {:ok, <<131, rewritten::binary>>}
      :error -> {:error, "unsupported ETF tag"}
    end
  end

  defp rewrite_atoms_to_binaries(_), do: {:error, "missing ETF version byte"}

  defp rewrite_atom(name, rest) do
    atom_bytes =
      case maybe_to_atom_or_module(name) do
        atom when is_atom(atom) -> <<119, byte_size(name)::8, name::binary>>
        _string -> to_binary_ext(name)
      end

    {atom_bytes, rest}
  end

  # Duplicated from Bonfire.Common.Types to avoid adding it as a dependency.
  # Tries to return an existing atom or loaded module for the given string,
  # falling back to the string itself if neither exists.

  defp maybe_to_atom_or_module(k) when is_atom(k), do: k

  defp maybe_to_atom_or_module(k) when is_binary(k),
    do: maybe_to_module(k) || maybe_to_atom(k)

  defp maybe_to_module("Elixir." <> _ = str) do
    case maybe_to_atom(str) do
      atom when is_atom(atom) and not is_nil(atom) -> atom
      _ -> nil
    end
  end

  defp maybe_to_module(str) when is_binary(str), do: maybe_to_module("Elixir." <> str)
  defp maybe_to_module(atom) when is_atom(atom) and not is_nil(atom), do: atom
  defp maybe_to_module(_), do: nil

  defp maybe_to_atom("false"), do: false
  defp maybe_to_atom("nil"), do: nil
  defp maybe_to_atom("true"), do: true
  defp maybe_to_atom(""), do: nil

  defp maybe_to_atom(str) when is_binary(str) do
    try do
      String.to_existing_atom(str)
    rescue
      ArgumentError -> str
    end
  end

  defp maybe_to_atom(other), do: other

  # Atom tags (100, 115, 118, 119)
  defp rewrite_term(<<100, len::16, name::binary-size(len), rest::binary>>),
    do: rewrite_atom(name, rest)

  defp rewrite_term(<<115, len::8, name::binary-size(len), rest::binary>>),
    do: rewrite_atom(name, rest)

  defp rewrite_term(<<118, len::16, name::binary-size(len), rest::binary>>),
    do: rewrite_atom(name, rest)

  defp rewrite_term(<<119, len::8, name::binary-size(len), rest::binary>>),
    do: rewrite_atom(name, rest)

  # ATOM_CACHE_REF → empty binary (cache unavailable outside distribution)
  defp rewrite_term(<<82, _index::8, rest::binary>>), do: {to_binary_ext(""), rest}

  # Leaf types: pass through verbatim
  defp rewrite_term(<<97, v::8, r::binary>>), do: {<<97, v::8>>, r}
  defp rewrite_term(<<98, v::32, r::binary>>), do: {<<98, v::32>>, r}
  defp rewrite_term(<<70, v::float-64, r::binary>>), do: {<<70, v::float-64>>, r}
  defp rewrite_term(<<99, s::binary-size(31), r::binary>>), do: {<<99, s::binary>>, r}
  defp rewrite_term(<<106, r::binary>>), do: {<<106>>, r}
  defp rewrite_term(<<107, len::16, s::binary-size(len), r::binary>>), do: {<<107, len::16, s::binary>>, r}
  defp rewrite_term(<<109, len::32, d::binary-size(len), r::binary>>), do: {<<109, len::32, d::binary>>, r}
  defp rewrite_term(<<110, n::8, s::8, d::binary-size(n), r::binary>>), do: {<<110, n::8, s::8, d::binary>>, r}
  defp rewrite_term(<<111, n::32, s::8, d::binary-size(n), r::binary>>), do: {<<111, n::32, s::8, d::binary>>, r}

  # Compound types: recurse into children
  defp rewrite_term(<<104, arity::8, rest::binary>>) do
    case rewrite_n_terms(rest, arity) do
      {children, r} -> {<<104, arity::8, children::binary>>, r}
      :error -> :error
    end
  end

  defp rewrite_term(<<105, arity::32, rest::binary>>) do
    case rewrite_n_terms(rest, arity) do
      {children, r} -> {<<105, arity::32, children::binary>>, r}
      :error -> :error
    end
  end

  defp rewrite_term(<<108, len::32, rest::binary>>) do
    case rewrite_n_terms(rest, len + 1) do
      {elems, r} -> {<<108, len::32, elems::binary>>, r}
      :error -> :error
    end
  end

  defp rewrite_term(<<116, pairs::32, rest::binary>>) do
    case rewrite_n_terms(rest, pairs * 2) do
      {kv, r} -> {<<116, pairs::32, kv::binary>>, r}
      :error -> :error
    end
  end

  defp rewrite_term(_), do: :error

  defp rewrite_n_terms(binary, n) do
    Enum.reduce_while(1..n//1, {<<>>, binary}, fn _, {acc, rem} ->
      case rewrite_term(rem) do
        {bytes, rest} -> {:cont, {<<acc::binary, bytes::binary>>, rest}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp to_binary_ext(name) when is_binary(name),
    do: <<109, byte_size(name)::32, name::binary>>

  @doc """
  Converting the data structure to binary for storage.
  """
  def dump(term), do: {:ok, :erlang.term_to_binary(term)}
end
