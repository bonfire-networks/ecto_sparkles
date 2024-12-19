defmodule EctoSparkles.JSONSerdeData do
  @moduledoc """
  A custom Ecto type for handling the serialization of arbitrary data types stored as JSON data in the database. Requires the underlying DB field to be a map / JSONB field.
  """
  use Ecto.Type
  # import Untangle

  def type, do: :map

  @doc """
  Provides custom casting rules for params. Nothing changes here.
  We only need to handle deserialization.
  """
  def cast(:any, term), do: {:ok, term}
  def cast(term), do: {:ok, term}

  @doc """
  Convert the JSON binary value from the database back to the desired term.
  """
  def load(raw_json) when is_binary(raw_json) do
    JsonSerde.deserialize(raw_json)
    # |> debug("deserialized #{raw_json}")
  end
  def load(json_data) do
    JsonSerde.Deserializer.deserialize(json_data, json_data)
    # |> debug("deserialized #{inspect json_data}")
  end

  @doc """
  Converting the data structure to a JSON binary for storage.
  """
  def dump(term), do: JsonSerde.serialize(term)
end
