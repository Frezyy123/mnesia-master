defmodule MnesiaMasterTest do
  use ExUnit.Case
  doctest MnesiaMaster

  test "greets the world" do
    assert MnesiaMaster.hello() == :world
  end
end
