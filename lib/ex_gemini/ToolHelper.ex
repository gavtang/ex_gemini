defmodule ExGemini.ToolHelper do
  defstruct [:name, :schema, :module, :function]

  defmacro __using__(_) do
    quote do
      import ExGemini.ToolHelper
      @before_compile ExGemini.ToolHelper
      Module.register_attribute(__MODULE__, :tools, accumulate: true)
    end
  end

  defmacro deftool(call, opts \\ [], expr) do
    {name, _context, args} =
      case call do
        {:when, _, [{name, context, args} | _]} -> {name, context, args}
        {name, context, args} -> {name, context, args}
      end

    description = Keyword.get(opts, :description, Atom.to_string(name))
    schema = Keyword.get(opts, :schema, [])
    reply = Keyword.get(opts, :reply, true)

    args = args || []

    {eval_schema, _binding} = Code.eval_quoted(schema)

    schema_defined_keys = Enum.map(eval_schema, fn {key, _} -> key end)

    {required, optional} =
      args
      |> Enum.map(fn {key, _, extra} ->
        case key do
          :\\ ->
            {opt_key, _, _} = Enum.at(extra, 0)
            default = Enum.at(extra, 1)
            {:optional, opt_key, default}

          _ ->
            {:required, key, nil}
        end
      end)
      |> Enum.split_with(fn {type, _key, _default} -> type == :required end)
      |> then(fn {required, optional} ->
        {
          Enum.map(required, fn {_, key, _} -> key end),
          Enum.map(optional, fn {_, key, default} -> {key, default} end)
        }
      end)

    optional_keys = Keyword.keys(optional)

    missing_keys = required -- schema_defined_keys

    if length(missing_keys) > 0 do
      raise CompileError,
        description:
          "Missing Schema: all required variables must have schema definitions: #{Enum.join(missing_keys, ", ")}",
        file: __CALLER__.file,
        line: __CALLER__.line
    end

    extra_keys = schema_defined_keys -- (required ++ optional_keys)

    function_declaration = %{
      name: Atom.to_string(name),
      description: description,
      parameters: %{
        type: "object",
        properties: eval_schema,
        required: Enum.map(required, &Atom.to_string/1)
      }
    }

    handler_name = String.to_atom("ex_gemini_handle_#{name}")

    quote do
      def unquote(call), unquote(expr)

      def unquote(handler_name)(params_map) do
        params =
          Enum.reduce(
            params_map,
            unquote(required)
            |> Keyword.new(fn key -> {key, nil} end)
            |> Enum.concat(unquote(optional)),
            # replace default params and nils
            fn {k, v}, acc ->
              Keyword.replace(acc, String.to_atom(k), v)
            end
          )

        if Enum.any?(params, fn {_, v} -> v == nil end) do
          {:ex_gemini_error, {:missing_params, Enum.filter(params, fn {_, v} -> v == nil end)}}
        else
          {unquote(reply), apply(__MODULE__, unquote(name), Enum.map(params, fn {_, v} -> v end))}
        end
      end

      if length(unquote(extra_keys)) > 0 do
        IO.warn(
          "Extra Schema Params: extraneous fields are defined in schema: #{Enum.join(unquote(extra_keys), ", ")}"
        )
      end

      @tools unquote(Macro.escape(function_declaration))
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def registered_tools, do: @tools

      def registered_tools(key) do
        Enum.find(@tools, fn %{name: name} -> name == Atom.to_string(key) end)
      end
    end
  end
end
