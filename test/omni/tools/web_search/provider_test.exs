defmodule Omni.Tools.WebSearch.ProviderTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.WebSearch.Provider
  alias Omni.Tools.WebSearch.TestProvider

  describe "validate!/1" do
    test "accepts a valid {module, opts} tuple" do
      assert {TestProvider, [api_key: "test"]} =
               Provider.validate!({TestProvider, api_key: "test"})
    end

    test "accepts a bare module" do
      assert {TestProvider, []} = Provider.validate!(TestProvider)
    end

    test "raises for a module that cannot be loaded" do
      assert_raise ArgumentError, ~r/could not load provider module/, fn ->
        Provider.validate!({NoSuchModule, []})
      end
    end

    test "raises for a module that does not implement search/2" do
      assert_raise ArgumentError, ~r/must implement search\/2/, fn ->
        Provider.validate!({String, []})
      end
    end

    test "raises for invalid input" do
      assert_raise ArgumentError, ~r/expected a provider module/, fn ->
        Provider.validate!("not a module")
      end
    end
  end
end
