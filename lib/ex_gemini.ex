defmodule ExGemini do
  @moduledoc """
  Documentation for `ExGemini`.
  """

  @default_opts [
    model: "gemini-2.0-flash",
    api_version: "v1beta"
  ]

  @valid_roles [:user, :model]

  @builtin_tools [:code_execution, :google_search]

  def new(opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)

    {
      %{
        contents: []
      },
      opts
    }
  end

  def set_system_instructions({request, meta}, instructions) do
    {Map.put(request, :system_instruction, %{
       parts: [
         %{
           text: instructions
         }
       ]
     }), meta}
  end

  def add_content({%{contents: contents} = request, meta}, new_content) do
    contents = contents ++ [new_content]
    {Map.put(request, :contents, contents), meta}
  end

  def add_part({request, meta}, role, part) when role in @valid_roles do
    add_content(
      {request, meta},
      %{
        role: Atom.to_string(role),
        parts: [part]
      }
    )
  end

  def add_text({request, meta}, role, text) when role in @valid_roles do
    add_part({request, meta}, role, %{
      text: text
    })
  end

  def add_function_response({request, meta}, name, result) do
    add_part({request, meta}, :user, %{
      functionResponse: %{
        name: name,
        # TODO: check if this needs to be in a map for some reason  
        response: %{"result" => result}
      }
    })
  end

  def add_tool({%{tools: tools} = request, meta}, :gemini, tool_name)
      when tool_name in @builtin_tools do
    {Map.put(
       request,
       :tools,
       tools ++
         [
           %{
             Atom.to_string(tool_name) => %{}
           }
         ]
     ), meta}
  end

  def add_tool({%{tools: tools} = request, meta}, module, tool_name) do
    new_tools =
      tools
      |> upsert(
        fn
          %{functionDeclarations: function_declarations} ->
            %{
              functionDeclarations:
                function_declarations ++ [apply(module, :registered_tools, [tool_name])]
            }

          _ ->
            false
        end,
        %{
          functionDeclarations: [apply(module, :registered_tools, [tool_name])]
        }
      )

    {_, new_meta} =
      Keyword.get_and_update(meta, :module_map, fn module_map ->
        new_module_map =
          case module_map do
            %{} -> Map.put(module_map, tool_name, module)
            _ -> %{tool_name => module}
          end

        {module_map, new_module_map}
      end)

    {Map.put(request, :tools, new_tools), new_meta}
  end

  def add_tool({request, meta}, module, tool_name) do
    add_tool(
      {Map.put(request, :tools, [
         # %{
         #   functionDeclarations: []
         # }
       ]), meta},
      module,
      tool_name
    )
  end

  def execute({request, meta}) do
    model = Keyword.fetch!(meta, :model)
    api_version = Keyword.fetch!(meta, :api_version)
    api_key = Application.get_env(:ex_gemini, ExGemini)[:api_key]

    url =
      "https://generativelanguage.googleapis.com/#{api_version}/models/#{model}:generateContent?key=#{api_key}"

    Req.post(url, json: request, headers: [{"Content-Type", "application/json"}])
    |> handle_response({request, meta})
  end

  defp handle_response(
         {:ok,
          %Req.Response{
            body: %{
              "candidates" => candidates
            }
          }},
         {request, meta}
       ) do
    with {:ok, %{"content" => %{"parts" => parts}}} <- Enum.fetch(candidates, 0),
         {:ok, last_part} <- Enum.fetch(parts, -1) do
      handle_response_part(last_part, {request, meta})
    else
      _ -> {:error, :unhandled_response}
    end
  end

  defp handle_response({:ok, %Req.Response{}} = r, _) do
    IO.inspect(r)
    {:error, :unhandled_response}
  end

  defp handle_response_part(%{"text" => text}, {response, meta}) do
    {:ok, text, add_text({response, meta}, :model, text)}
  end

  defp handle_response_part(
         %{
           "functionCall" => %{
             "args" => args,
             "name" => name
           }
         } = part,
         {response, meta}
       ) do
    with {:ok, module_map} <- Keyword.fetch(meta, :module_map),
         {:ok, module} <- Map.fetch(module_map, String.to_atom(name)),
         {true, res} <- apply(module, String.to_atom("ex_gemini_handle_#{name}"), [args]) do
      {response, meta}
      |> add_part(:model, part)
      |> add_function_response(name, res)
      |> execute()
    else
      {false, res} -> {:ok, res, {response, meta} |> add_part(:model, part)}
      _ -> {:error, :bad_function_call}
    end
  end

  defp upsert(list, match_and_transform_fn, default_item) do
    {found, result} =
      Enum.reduce(list, {false, []}, fn item, {found, acc} ->
        case match_and_transform_fn.(item) do
          nil -> {found, [item | acc]}
          false -> {found, [item | acc]}
          updated_item -> {true, [updated_item | acc]}
        end
      end)

    if found do
      Enum.reverse(result)
    else
      Enum.reverse([default_item | result])
    end
  end
end
