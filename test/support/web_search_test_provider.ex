defmodule Omni.Tools.WebSearch.TestProvider do
  @behaviour Omni.Tools.WebSearch.Provider

  @impl true
  def search(_query, opts) do
    case Keyword.get(opts, :respond_with) do
      nil ->
        {:ok,
         [
           %{url: "https://example.com/1", title: "First Result", snippet: "The first snippet"},
           %{url: "https://example.com/2", title: "Second Result", snippet: "The second snippet"}
         ]}

      :empty ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}

      results when is_list(results) ->
        {:ok, results}
    end
  end
end
