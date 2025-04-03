# ExGemini

Wrapper for Gemini LLM text generation and function calling

## Installation


```elixir
def deps do
  [
    {:ex_gemini, git: "https://github.com/gavtang/ex_gemini.git"}
  ]
end
```

## Configuration

Ensure API key is set, for example in config/runtime.exs

```elixir
import Config

config :ex_gemini, ExGemini, api_key: System.get_env("GEMINI_API_KEY")

```

## Examples

### Basic Completion

```elixir
import ExGemini

def complete(text) do
  new()
  |> add_text(:user, text)
  |> execute()
  |> case do
    {:ok, res, _} -> res
    _ -> :error
  end
end

```

### Tool Use
Specify the tool. The following usage of the `deftool` macro defines a normal Elixir function `get_weather` and
a `ex_gemini_handle_get_weather` that will be called if Gemini responds with a function call

```elixir
defmodule Example do
  use ExGemini.ToolHelper

  deftool get_weather(lat, long),
    description: "",
    reply: true, # Optional, defaults to true
    schema: %{
      lat: %{
        type: "number",
        description: "latitude of weather location"
      },
      long: %{
        type: "number",
        description: "longitude for weather location"
      }
    } do
    # function implementation omitted
    end
end

```

`get_weather` can now be added to a request using ExGemini.add_tool

```elixir
import ExGemini

def demo() do
  new()
  |> add_text(:user, "What's the weather like at 37.422160, -122.084274")
  |> add_tool(Example, :get_weather)
  |> execute()
  |> case do
    {:ok, res, _} -> res
    _ -> :error
  end
end

```


