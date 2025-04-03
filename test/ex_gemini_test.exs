defmodule ExGeminiTest do
  use ExUnit.Case
  doctest ExGemini

  test "greets the world" do
    assert ExGemini.hello() == :world
  end
end
