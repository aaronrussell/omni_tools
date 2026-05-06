defmodule Omni.ToolsTest do
  use ExUnit.Case
  doctest Omni.Tools

  test "greets the world" do
    assert Omni.Tools.hello() == :world
  end
end
