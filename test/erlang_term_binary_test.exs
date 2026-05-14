defmodule EctoSparkles.ErlangTermBinaryTest do
  use ExUnit.Case, async: true
  alias EctoSparkles.ErlangTermBinary

  # ETF binaries generated in IEx via:
  #   :erlang.term_to_binary(term) |> inspect(limit: :infinity, binaries: :as_binaries)
  # Validity is guaranteed by construction (produced by term_to_binary).
  # zzz_* atom names are never referenced as literals in code, guaranteeing
  # they are absent from the atom table at test time.

  describe "load/1 happy path: primitives and stdlib structs" do
    test "integer 42" do
      assert {:ok, 42} = ErlangTermBinary.load(<<131, 97, 42>>)
    end

    test "negative integer -42" do
      assert {:ok, -42} = ErlangTermBinary.load(<<131, 98, 255, 255, 255, 214>>)
    end

    test "float 3.14" do
      assert {:ok, 3.14} = ErlangTermBinary.load(<<131, 70, 64, 9, 30, 184, 81, 235, 133, 31>>)
    end

    test "bignum" do
      assert {:ok, 99_999_999_999_999_999_999} =
               ErlangTermBinary.load(<<131, 110, 9, 0, 255, 255, 15, 99, 45, 94, 199, 107, 5>>)
    end

    test "charlist ~c\"hello\"" do
      assert {:ok, ~c"hello"} =
               ErlangTermBinary.load(<<131, 107, 0, 5, 104, 101, 108, 108, 111>>)
    end

    test "empty map, list, tuple" do
      assert {:ok, %{}} = ErlangTermBinary.load(<<131, 116, 0, 0, 0, 0>>)
      assert {:ok, []} = ErlangTermBinary.load(<<131, 106>>)
      assert {:ok, {}} = ErlangTermBinary.load(<<131, 104, 0>>)
    end

    test "{:error, string} tagged tuple" do
      assert {:ok, {:error, "something went wrong"}} =
               ErlangTermBinary.load(
                 <<131, 104, 2, 119, 5, 101, 114, 114, 111, 114, 109, 0, 0, 0, 20, 115, 111,
                   109, 101, 116, 104, 105, 110, 103, 32, 119, 101, 110, 116, 32, 119, 114, 111,
                   110, 103>>
               )
    end

    test "{:ok, map} tagged tuple" do
      assert {:ok, {:ok, %{id: 1}}} =
               ErlangTermBinary.load(
                 <<131, 104, 2, 119, 2, 111, 107, 116, 0, 0, 0, 1, 119, 2, 105, 100, 97, 1>>
               )
    end

    test "Range struct 1..10//1" do
      assert {:ok, 1..10//1} =
               ErlangTermBinary.load(
                 <<131, 116, 0, 0, 0, 4, 119, 5, 102, 105, 114, 115, 116, 97, 1, 119, 4, 108,
                   97, 115, 116, 97, 10, 119, 4, 115, 116, 101, 112, 97, 1, 119, 10, 95, 95,
                   115, 116, 114, 117, 99, 116, 95, 95, 119, 12, 69, 108, 105, 120, 105, 114,
                   46, 82, 97, 110, 103, 101>>
               )
    end

    test "URI struct" do
      assert {:ok, %URI{host: "example.com", scheme: "https"}} =
               ErlangTermBinary.load(
                 <<131, 116, 0, 0, 0, 9, 119, 4, 112, 111, 114, 116, 119, 3, 110, 105, 108,
                   119, 6, 115, 99, 104, 101, 109, 101, 109, 0, 0, 0, 5, 104, 116, 116, 112,
                   115, 119, 4, 112, 97, 116, 104, 119, 3, 110, 105, 108, 119, 4, 104, 111, 115,
                   116, 109, 0, 0, 0, 11, 101, 120, 97, 109, 112, 108, 101, 46, 99, 111, 109,
                   119, 10, 95, 95, 115, 116, 114, 117, 99, 116, 95, 95, 119, 10, 69, 108, 105,
                   120, 105, 114, 46, 85, 82, 73, 119, 8, 102, 114, 97, 103, 109, 101, 110, 116,
                   119, 3, 110, 105, 108, 119, 5, 113, 117, 101, 114, 121, 119, 3, 110, 105,
                   108, 119, 9, 97, 117, 116, 104, 111, 114, 105, 116, 121, 119, 3, 110, 105,
                   108, 119, 8, 117, 115, 101, 114, 105, 110, 102, 111, 119, 3, 110, 105, 108>>
               )
    end

    test "Date struct ~D[2024-01-01]" do
      assert {:ok, ~D[2024-01-01]} =
               ErlangTermBinary.load(
                 <<131, 116, 0, 0, 0, 5, 119, 8, 99, 97, 108, 101, 110, 100, 97, 114, 119, 19,
                   69, 108, 105, 120, 105, 114, 46, 67, 97, 108, 101, 110, 100, 97, 114, 46, 73,
                   83, 79, 119, 5, 109, 111, 110, 116, 104, 97, 1, 119, 10, 95, 95, 115, 116,
                   114, 117, 99, 116, 95, 95, 119, 11, 69, 108, 105, 120, 105, 114, 46, 68, 97,
                   116, 101, 119, 3, 100, 97, 121, 97, 1, 119, 4, 121, 101, 97, 114, 98, 0, 0,
                   7, 232>>
               )
    end

    test "DateTime struct ~U[2024-01-01 00:00:00Z]" do
      assert {:ok, ~U[2024-01-01 00:00:00Z]} =
               ErlangTermBinary.load(
                 <<131, 116, 0, 0, 0, 13, 119, 11, 109, 105, 99, 114, 111, 115, 101, 99, 111,
                   110, 100, 104, 2, 97, 0, 97, 0, 119, 6, 115, 101, 99, 111, 110, 100, 97, 0,
                   119, 8, 99, 97, 108, 101, 110, 100, 97, 114, 119, 19, 69, 108, 105, 120, 105,
                   114, 46, 67, 97, 108, 101, 110, 100, 97, 114, 46, 73, 83, 79, 119, 5, 109,
                   111, 110, 116, 104, 97, 1, 119, 10, 95, 95, 115, 116, 114, 117, 99, 116, 95,
                   95, 119, 15, 69, 108, 105, 120, 105, 114, 46, 68, 97, 116, 101, 84, 105, 109,
                   101, 119, 3, 100, 97, 121, 97, 1, 119, 4, 121, 101, 97, 114, 98, 0, 0, 7,
                   232, 119, 6, 109, 105, 110, 117, 116, 101, 97, 0, 119, 4, 104, 111, 117, 114,
                   97, 0, 119, 9, 116, 105, 109, 101, 95, 122, 111, 110, 101, 109, 0, 0, 0, 7,
                   69, 116, 99, 47, 85, 84, 67, 119, 9, 122, 111, 110, 101, 95, 97, 98, 98, 114,
                   109, 0, 0, 0, 3, 85, 84, 67, 119, 10, 117, 116, 99, 95, 111, 102, 102, 115,
                   101, 116, 97, 0, 119, 10, 115, 116, 100, 95, 111, 102, 102, 115, 101, 116,
                   97, 0>>
               )
    end
  end

  describe "load/1 happy path (safe decode succeeds, no rewrite needed)" do
    test "roundtrip: dump then load preserves known atoms" do
      original = %{id: 1, name: "alice", status: :active}
      {:ok, dumped} = ErlangTermBinary.dump(original)
      assert {:ok, ^original} = ErlangTermBinary.load(dumped)
    end

    test ":ok" do
      assert {:ok, :ok} = ErlangTermBinary.load(<<131, 119, 2, 111, 107>>)
    end

    test "nil" do
      assert {:ok, nil} = ErlangTermBinary.load(<<131, 119, 3, 110, 105, 108>>)
    end

    test "true" do
      assert {:ok, true} = ErlangTermBinary.load(<<131, 119, 4, 116, 114, 117, 101>>)
    end

    test "false" do
      assert {:ok, false} = ErlangTermBinary.load(<<131, 119, 5, 102, 97, 108, 115, 101>>)
    end

    test "known module Enum" do
      assert {:ok, Enum} =
               ErlangTermBinary.load(<<131, 119, 11, 69, 108, 105, 120, 105, 114, 46, 69, 110, 117, 109>>)
    end


    test "plain string" do
      assert {:ok, "just a string"} =
               ErlangTermBinary.load(
                 <<131, 109, 0, 0, 0, 13, 106, 117, 115, 116, 32, 97, 32, 115, 116, 114, 105,
                   110, 103>>
               )
    end

    test "plain binary" do
      assert {:ok, <<1, 2, 3>>} =
               ErlangTermBinary.load(<<131, 109, 0, 0, 0, 3, 1, 2, 3>>)
    end
  end

  describe "load/1 fallback: unknown atoms → strings, known atoms stay atoms" do
    test "single unknown atom becomes string" do
      assert {:ok, "zzz_unknown_atom_bonfire_etf_test"} =
               ErlangTermBinary.load(
                 <<131, 119, 33, 122, 122, 122, 95, 117, 110, 107, 110, 111, 119, 110, 95, 97,
                   116, 111, 109, 95, 98, 111, 110, 102, 105, 114, 101, 95, 101, 116, 102, 95,
                   116, 101, 115, 116>>
               )
    end

    test "unknown module becomes string" do
      assert {:ok, "Elixir.Zzz.Unknown.Module.BonfireEtfTest"} =
               ErlangTermBinary.load(
                 <<131, 119, 40, 69, 108, 105, 120, 105, 114, 46, 90, 122, 122, 46, 85, 110,
                   107, 110, 111, 119, 110, 46, 77, 111, 100, 117, 108, 101, 46, 66, 111, 110,
                   102, 105, 114, 101, 69, 116, 102, 84, 101, 115, 116>>
               )
    end

    test "another unknown module becomes string" do
      assert {:ok, "Elixir.Zzz.Unknown.BonfireEtfTest.SubModule"} =
               ErlangTermBinary.load(
                 <<131, 119, 43, 69, 108, 105, 120, 105, 114, 46, 90, 122, 122, 46, 85, 110,
                   107, 110, 111, 119, 110, 46, 66, 111, 110, 102, 105, 114, 101, 69, 116, 102,
                   84, 101, 115, 116, 46, 83, 117, 98, 77, 111, 100, 117, 108, 101>>
               )
    end

    test "keyword list: unknown atom key becomes string, value preserved" do
      # [zzz_unknown_key_bonfire_etf_test: 42] → [{"zzz_unknown_key_bonfire_etf_test", 42}]
      assert {:ok, [{"zzz_unknown_key_bonfire_etf_test", 42}]} =
               ErlangTermBinary.load(
                 <<131, 108, 0, 0, 0, 1, 104, 2, 119, 32, 122, 122, 122, 95, 117, 110, 107,
                   110, 111, 119, 110, 95, 107, 101, 121, 95, 98, 111, 110, 102, 105, 114, 101,
                   95, 101, 116, 102, 95, 116, 101, 115, 116, 97, 42, 106>>
               )
    end

    test "keyword list: two unknown atom keys become strings" do
      # [zzz_unknown_key_bonfire_etf_test: "hello", zzz_another_unknown_bonfire_etf_test: 99]
      assert {:ok,
              [
                {"zzz_unknown_key_bonfire_etf_test", "hello"},
                {"zzz_another_unknown_bonfire_etf_test", 99}
              ]} =
               ErlangTermBinary.load(
                 <<131, 108, 0, 0, 0, 2, 104, 2, 119, 32, 122, 122, 122, 95, 117, 110, 107,
                   110, 111, 119, 110, 95, 107, 101, 121, 95, 98, 111, 110, 102, 105, 114, 101,
                   95, 101, 116, 102, 95, 116, 101, 115, 116, 109, 0, 0, 0, 5, 104, 101, 108,
                   108, 111, 104, 2, 119, 36, 122, 122, 122, 95, 97, 110, 111, 116, 104, 101,
                   114, 95, 117, 110, 107, 110, 111, 119, 110, 95, 98, 111, 110, 102, 105, 114,
                   101, 95, 101, 116, 102, 95, 116, 101, 115, 116, 97, 99, 106>>
               )
    end

    test "map: unknown atom key becomes string" do
      # %{zzz_unknown_key_bonfire_etf_test: "value"} → %{"zzz_unknown_key_bonfire_etf_test" => "value"}
      assert {:ok, %{"zzz_unknown_key_bonfire_etf_test" => "value"}} =
               ErlangTermBinary.load(
                 <<131, 116, 0, 0, 0, 1, 119, 32, 122, 122, 122, 95, 117, 110, 107, 110, 111,
                   119, 110, 95, 107, 101, 121, 95, 98, 111, 110, 102, 105, 114, 101, 95, 101,
                   116, 102, 95, 116, 101, 115, 116, 109, 0, 0, 0, 5, 118, 97, 108, 117, 101>>
               )
    end

    test "map: two unknown atom keys become strings" do
      # %{zzz_another_unknown_bonfire_etf_test: 2, zzz_unknown_bonfire_etf_test: 1}
      assert {:ok,
              %{
                "zzz_another_unknown_bonfire_etf_test" => 2,
                "zzz_unknown_bonfire_etf_test" => 1
              }} =
               ErlangTermBinary.load(
                 <<131, 116, 0, 0, 0, 2, 119, 36, 122, 122, 122, 95, 97, 110, 111, 116, 104,
                   101, 114, 95, 117, 110, 107, 110, 111, 119, 110, 95, 98, 111, 110, 102, 105,
                   114, 101, 95, 101, 116, 102, 95, 116, 101, 115, 116, 97, 2, 119, 28, 122,
                   122, 122, 95, 117, 110, 107, 110, 111, 119, 110, 95, 98, 111, 110, 102, 105,
                   114, 101, 95, 101, 116, 102, 95, 116, 101, 115, 116, 97, 1>>
               )
    end

    test "map: string key with unknown atom value" do
      # %{"key" => :zzz_unknown_atom_bonfire_etf_test}
      assert {:ok, %{"key" => "zzz_unknown_atom_bonfire_etf_test"}} =
               ErlangTermBinary.load(
                 <<131, 116, 0, 0, 0, 1, 109, 0, 0, 0, 3, 107, 101, 121, 119, 33, 122, 122,
                   122, 95, 117, 110, 107, 110, 111, 119, 110, 95, 97, 116, 111, 109, 95, 98,
                   111, 110, 102, 105, 114, 101, 95, 101, 116, 102, 95, 116, 101, 115, 116>>
               )
    end

    test "tuple: unknown atom becomes string, other elements preserved" do
      # {:zzz_unknown_bonfire_etf_test, 1, "hello"} → {"zzz_unknown_bonfire_etf_test", 1, "hello"}
      assert {:ok, {"zzz_unknown_bonfire_etf_test", 1, "hello"}} =
               ErlangTermBinary.load(
                 <<131, 104, 3, 119, 28, 122, 122, 122, 95, 117, 110, 107, 110, 111, 119, 110,
                   95, 98, 111, 110, 102, 105, 114, 101, 95, 101, 116, 102, 95, 116, 101, 115,
                   116, 97, 1, 109, 0, 0, 0, 5, 104, 101, 108, 108, 111>>
               )
    end

    test "list: unknown atoms become strings, :ok stays atom" do
      # [:zzz_unknown_bonfire_etf_test, :ok, :zzz_another_unknown_bonfire_etf_test]
      assert {:ok, ["zzz_unknown_bonfire_etf_test", :ok, "zzz_another_unknown_bonfire_etf_test"]} =
               ErlangTermBinary.load(
                 <<131, 108, 0, 0, 0, 3, 119, 28, 122, 122, 122, 95, 117, 110, 107, 110, 111,
                   119, 110, 95, 98, 111, 110, 102, 105, 114, 101, 95, 101, 116, 102, 95, 116,
                   101, 115, 116, 119, 2, 111, 107, 119, 36, 122, 122, 122, 95, 97, 110, 111,
                   116, 104, 101, 114, 95, 117, 110, 107, 110, 111, 119, 110, 95, 98, 111, 110,
                   102, 105, 114, 101, 95, 101, 116, 102, 95, 116, 101, 115, 116, 106>>
               )
    end

    test "complex map: unknown atoms/modules become strings, known atoms stay" do
      # %{verb: :zzz_unknown_verb, object_type: Zzz.Unknown.Module.BonfireEtfTest,
      #   scope: :zzz_unknown_scope, opts: [visible: true, role: :zzz_unknown_role]}
      assert {:ok, result} =
               ErlangTermBinary.load(
                 <<131, 116, 0, 0, 0, 4, 119, 5, 115, 99, 111, 112, 101, 119, 34, 122, 122,
                   122, 95, 117, 110, 107, 110, 111, 119, 110, 95, 115, 99, 111, 112, 101, 95,
                   98, 111, 110, 102, 105, 114, 101, 95, 101, 116, 102, 95, 116, 101, 115, 116,
                   119, 4, 111, 112, 116, 115, 108, 0, 0, 0, 2, 104, 2, 119, 7, 118, 105, 115,
                   105, 98, 108, 101, 119, 4, 116, 114, 117, 101, 104, 2, 119, 4, 114, 111, 108,
                   101, 119, 33, 122, 122, 122, 95, 117, 110, 107, 110, 111, 119, 110, 95, 114,
                   111, 108, 101, 95, 98, 111, 110, 102, 105, 114, 101, 95, 101, 116, 102, 95,
                   116, 101, 115, 116, 106, 119, 4, 118, 101, 114, 98, 119, 33, 122, 122, 122,
                   95, 117, 110, 107, 110, 111, 119, 110, 95, 118, 101, 114, 98, 95, 98, 111,
                   110, 102, 105, 114, 101, 95, 101, 116, 102, 95, 116, 101, 115, 116, 119, 11,
                   111, 98, 106, 101, 99, 116, 95, 116, 121, 112, 101, 119, 40, 69, 108, 105,
                   120, 105, 114, 46, 90, 122, 122, 46, 85, 110, 107, 110, 111, 119, 110, 46,
                   77, 111, 100, 117, 108, 101, 46, 66, 111, 110, 102, 105, 114, 101, 69, 116,
                   102, 84, 101, 115, 116>>
               )

      assert result["zzz_unknown_verb_bonfire_etf_test"] == nil
      assert Map.get(result, :verb) == "zzz_unknown_verb_bonfire_etf_test"
      assert Map.get(result, :object_type) == "Elixir.Zzz.Unknown.Module.BonfireEtfTest"
      assert Map.get(result, :scope) == "zzz_unknown_scope_bonfire_etf_test"
      assert is_list(Map.get(result, :opts))
    end

    test "struct with unknown module: __struct__ key kept as atom, value becomes string" do
      # %{__struct__: Zzz.Unknown.OldConfig.BonfireEtfTest, ok: "example.com", error: 443}
      assert {:ok, result} =
               ErlangTermBinary.load(
                 <<131, 116, 0, 0, 0, 3, 119, 5, 101, 114, 114, 111, 114, 98, 0, 0, 1, 187,
                   119, 2, 111, 107, 109, 0, 0, 0, 11, 101, 120, 97, 109, 112, 108, 101, 46, 99,
                   111, 109, 119, 10, 95, 95, 115, 116, 114, 117, 99, 116, 95, 95, 119, 43, 69,
                   108, 105, 120, 105, 114, 46, 90, 122, 122, 46, 85, 110, 107, 110, 111, 119,
                   110, 46, 79, 108, 100, 67, 111, 110, 102, 105, 103, 46, 66, 111, 110, 102,
                   105, 114, 101, 69, 116, 102, 84, 101, 115, 116>>
               )

      refute is_struct(result)
      assert result.__struct__ == "Elixir.Zzz.Unknown.OldConfig.BonfireEtfTest"
      assert result.ok == "example.com"
      assert result.error == 443
    end

    test "deeply nested map: unknown atom at leaf becomes string" do
      # %{ok: %{error: %{ok: :zzz_deep_unknown_bonfire_etf_test}}}
      assert {:ok, %{ok: %{error: %{ok: "zzz_deep_unknown_bonfire_etf_test"}}}} =
               ErlangTermBinary.load(
                 <<131, 116, 0, 0, 0, 1, 119, 2, 111, 107, 116, 0, 0, 0, 1, 119, 5, 101, 114,
                   114, 111, 114, 116, 0, 0, 0, 1, 119, 2, 111, 107, 119, 33, 122, 122, 122, 95,
                   100, 101, 101, 112, 95, 117, 110, 107, 110, 111, 119, 110, 95, 98, 111, 110,
                   102, 105, 114, 101, 95, 101, 116, 102, 95, 116, 101, 115, 116>>
               )
    end

    test "mixed keyword list + nested map: unknown atom value becomes string, known keys preserved" do
      # [ok: %{true: 5432, error: "localhost"}, error: [false: 300, ok: :zzz_unknown_strategy_bonfire_etf_test]]
      assert {:ok, result} =
               ErlangTermBinary.load(
                 <<131, 108, 0, 0, 0, 2, 104, 2, 119, 2, 111, 107, 116, 0, 0, 0, 2, 119, 4,
                   116, 114, 117, 101, 98, 0, 0, 21, 56, 119, 5, 101, 114, 114, 111, 114, 109,
                   0, 0, 0, 9, 108, 111, 99, 97, 108, 104, 111, 115, 116, 104, 2, 119, 5, 101,
                   114, 114, 111, 114, 108, 0, 0, 0, 2, 104, 2, 119, 5, 102, 97, 108, 115, 101,
                   98, 0, 0, 1, 44, 104, 2, 119, 2, 111, 107, 119, 37, 122, 122, 122, 95, 117,
                   110, 107, 110, 111, 119, 110, 95, 115, 116, 114, 97, 116, 101, 103, 121, 95,
                   98, 111, 110, 102, 105, 114, 101, 95, 101, 116, 102, 95, 116, 101, 115, 116,
                   106, 106>>
               )

      assert [{:ok, _inner_map}, {:error, inner_list}] = result
      assert {:ok, "zzz_unknown_strategy_bonfire_etf_test"} = List.keyfind!(inner_list, :ok, 0)
    end

    test "config-like struct with unknown module and unknown atom value" do
      # %{__struct__: Zzz.Unknown.OldConfig.BonfireEtfTest, ok: :zzz_unknown_timeout_type_bonfire_etf_test, error: 10}
      assert {:ok, result} =
               ErlangTermBinary.load(
                 <<131, 116, 0, 0, 0, 3, 119, 5, 101, 114, 114, 111, 114, 97, 10, 119, 2, 111,
                   107, 119, 41, 122, 122, 122, 95, 117, 110, 107, 110, 111, 119, 110, 95, 116,
                   105, 109, 101, 111, 117, 116, 95, 116, 121, 112, 101, 95, 98, 111, 110, 102,
                   105, 114, 101, 95, 101, 116, 102, 95, 116, 101, 115, 116, 119, 10, 95, 95,
                   115, 116, 114, 117, 99, 116, 95, 95, 119, 43, 69, 108, 105, 120, 105, 114,
                   46, 90, 122, 122, 46, 85, 110, 107, 110, 111, 119, 110, 46, 79, 108, 100, 67,
                   111, 110, 102, 105, 103, 46, 66, 111, 110, 102, 105, 114, 101, 69, 116, 102,
                   84, 101, 115, 116>>
               )

      refute is_struct(result)
      assert result.__struct__ == "Elixir.Zzz.Unknown.OldConfig.BonfireEtfTest"
      assert result.ok == "zzz_unknown_timeout_type_bonfire_etf_test"
      assert result.error == 10
    end
  end
end
