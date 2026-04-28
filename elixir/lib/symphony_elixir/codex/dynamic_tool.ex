defmodule SymphonyElixir.Codex.DynamicTool do
  @moduledoc """
  Executes client-side tool calls requested by Codex app-server turns.
  """

  alias SymphonyElixir.{Linear.Client, Linear.Issue, Tracker}

  @linear_graphql_tool "linear_graphql"
  @local_tracker_tool "local_tracker"
  @linear_graphql_description """
  Execute a raw GraphQL query or mutation against Linear using Symphony's configured auth.
  """
  @local_tracker_description """
  Read or update Symphony's configured local JSON tracker board.
  """
  @linear_graphql_input_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["query"],
    "properties" => %{
      "query" => %{
        "type" => "string",
        "description" => "GraphQL query or mutation document to execute against Linear."
      },
      "variables" => %{
        "type" => ["object", "null"],
        "description" => "Optional GraphQL variables object.",
        "additionalProperties" => true
      }
    }
  }
  @local_tracker_input_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["action"],
    "properties" => %{
      "action" => %{
        "type" => "string",
        "enum" => ["list_issues", "comment", "update_state"],
        "description" => "Local tracker operation to perform."
      },
      "issue_id" => %{
        "type" => "string",
        "description" => "Issue id for comment or update_state."
      },
      "body" => %{
        "type" => "string",
        "description" => "Comment body for comment."
      },
      "state" => %{
        "type" => "string",
        "description" => "Target issue state for update_state."
      }
    }
  }

  @spec execute(String.t() | nil, term(), keyword()) :: map()
  def execute(tool, arguments, opts \\ []) do
    case tool do
      @linear_graphql_tool ->
        execute_linear_graphql(arguments, opts)

      @local_tracker_tool ->
        execute_local_tracker(arguments)

      other ->
        failure_response(%{
          "error" => %{
            "message" => "Unsupported dynamic tool: #{inspect(other)}.",
            "supportedTools" => supported_tool_names()
          }
        })
    end
  end

  @spec tool_specs() :: [map()]
  def tool_specs do
    [
      %{
        "name" => @linear_graphql_tool,
        "description" => @linear_graphql_description,
        "inputSchema" => @linear_graphql_input_schema
      },
      %{
        "name" => @local_tracker_tool,
        "description" => @local_tracker_description,
        "inputSchema" => @local_tracker_input_schema
      }
    ]
  end

  defp execute_linear_graphql(arguments, opts) do
    linear_client = Keyword.get(opts, :linear_client, &Client.graphql/3)

    with {:ok, query, variables} <- normalize_linear_graphql_arguments(arguments),
         {:ok, response} <- linear_client.(query, variables, []) do
      graphql_response(response)
    else
      {:error, reason} ->
        failure_response(tool_error_payload(reason))
    end
  end

  defp execute_local_tracker(arguments) do
    with {:ok, action, arguments} <- normalize_local_tracker_arguments(arguments),
         {:ok, payload} <- run_local_tracker_action(action, arguments) do
      dynamic_tool_response(true, encode_payload(payload))
    else
      {:error, reason} ->
        failure_response(local_tracker_error_payload(reason))
    end
  end

  defp normalize_local_tracker_arguments(arguments) when is_map(arguments) do
    case Map.get(arguments, "action") || Map.get(arguments, :action) do
      action when action in ["list_issues", "comment", "update_state"] ->
        {:ok, action, arguments}

      action when is_binary(action) ->
        {:error, {:unsupported_local_tracker_action, action}}

      _ ->
        {:error, :missing_local_tracker_action}
    end
  end

  defp normalize_local_tracker_arguments(_arguments), do: {:error, :invalid_local_tracker_arguments}

  defp run_local_tracker_action("list_issues", _arguments) do
    with {:ok, issues} <- Tracker.fetch_candidate_issues() do
      {:ok, %{"issues" => Enum.map(issues, &issue_payload/1)}}
    end
  end

  defp run_local_tracker_action("comment", arguments) do
    with {:ok, issue_id} <- required_string(arguments, "issue_id"),
         {:ok, body} <- required_string(arguments, "body"),
         :ok <- Tracker.create_comment(issue_id, body) do
      {:ok, %{"ok" => true}}
    end
  end

  defp run_local_tracker_action("update_state", arguments) do
    with {:ok, issue_id} <- required_string(arguments, "issue_id"),
         {:ok, state} <- required_string(arguments, "state"),
         :ok <- Tracker.update_issue_state(issue_id, state) do
      {:ok, %{"ok" => true}}
    end
  end

  defp required_string(arguments, field) do
    value = Map.get(arguments, field) || Map.get(arguments, String.to_atom(field))

    case value do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, {:missing_local_tracker_field, field}}
          trimmed -> {:ok, trimmed}
        end

      _ ->
        {:error, {:missing_local_tracker_field, field}}
    end
  end

  defp issue_payload(%Issue{} = issue) do
    %{
      "id" => issue.id,
      "identifier" => issue.identifier,
      "title" => issue.title,
      "description" => issue.description,
      "priority" => issue.priority,
      "state" => issue.state,
      "branch_name" => issue.branch_name,
      "url" => issue.url,
      "labels" => issue.labels,
      "blocked_by" => issue.blocked_by
    }
  end

  defp normalize_linear_graphql_arguments(arguments) when is_binary(arguments) do
    case String.trim(arguments) do
      "" -> {:error, :missing_query}
      query -> {:ok, query, %{}}
    end
  end

  defp normalize_linear_graphql_arguments(arguments) when is_map(arguments) do
    case normalize_query(arguments) do
      {:ok, query} ->
        case normalize_variables(arguments) do
          {:ok, variables} ->
            {:ok, query, variables}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_linear_graphql_arguments(_arguments), do: {:error, :invalid_arguments}

  defp normalize_query(arguments) do
    case Map.get(arguments, "query") || Map.get(arguments, :query) do
      query when is_binary(query) ->
        case String.trim(query) do
          "" -> {:error, :missing_query}
          trimmed -> {:ok, trimmed}
        end

      _ ->
        {:error, :missing_query}
    end
  end

  defp normalize_variables(arguments) do
    case Map.get(arguments, "variables") || Map.get(arguments, :variables) || %{} do
      variables when is_map(variables) -> {:ok, variables}
      _ -> {:error, :invalid_variables}
    end
  end

  defp graphql_response(response) do
    success =
      case response do
        %{"errors" => errors} when is_list(errors) and errors != [] -> false
        %{errors: errors} when is_list(errors) and errors != [] -> false
        _ -> true
      end

    dynamic_tool_response(success, encode_payload(response))
  end

  defp failure_response(payload) do
    dynamic_tool_response(false, encode_payload(payload))
  end

  defp dynamic_tool_response(success, output) when is_boolean(success) and is_binary(output) do
    %{
      "success" => success,
      "output" => output,
      "contentItems" => [
        %{
          "type" => "inputText",
          "text" => output
        }
      ]
    }
  end

  defp encode_payload(payload) when is_map(payload) or is_list(payload) do
    Jason.encode!(payload, pretty: true)
  end

  defp encode_payload(payload), do: inspect(payload)

  defp tool_error_payload(:missing_query) do
    %{
      "error" => %{
        "message" => "`linear_graphql` requires a non-empty `query` string."
      }
    }
  end

  defp tool_error_payload(:invalid_arguments) do
    %{
      "error" => %{
        "message" => "`linear_graphql` expects either a GraphQL query string or an object with `query` and optional `variables`."
      }
    }
  end

  defp tool_error_payload(:invalid_variables) do
    %{
      "error" => %{
        "message" => "`linear_graphql.variables` must be a JSON object when provided."
      }
    }
  end

  defp tool_error_payload(:missing_linear_api_token) do
    %{
      "error" => %{
        "message" => "Symphony is missing Linear auth. Set `linear.api_key` in `WORKFLOW.md` or export `LINEAR_API_KEY`."
      }
    }
  end

  defp tool_error_payload({:linear_api_status, status}) do
    %{
      "error" => %{
        "message" => "Linear GraphQL request failed with HTTP #{status}.",
        "status" => status
      }
    }
  end

  defp tool_error_payload({:linear_api_request, reason}) do
    %{
      "error" => %{
        "message" => "Linear GraphQL request failed before receiving a successful response.",
        "reason" => inspect(reason)
      }
    }
  end

  defp tool_error_payload(reason) do
    %{
      "error" => %{
        "message" => "Linear GraphQL tool execution failed.",
        "reason" => inspect(reason)
      }
    }
  end

  defp local_tracker_error_payload(:missing_local_tracker_action) do
    %{
      "error" => %{
        "message" => "`local_tracker` requires an action."
      }
    }
  end

  defp local_tracker_error_payload(:invalid_local_tracker_arguments) do
    %{
      "error" => %{
        "message" => "`local_tracker` expects an object with an action."
      }
    }
  end

  defp local_tracker_error_payload({:unsupported_local_tracker_action, action}) do
    %{
      "error" => %{
        "message" => "Unsupported local tracker action: #{action}."
      }
    }
  end

  defp local_tracker_error_payload({:missing_local_tracker_field, field}) do
    %{
      "error" => %{
        "message" => "`local_tracker` action is missing required field `#{field}`."
      }
    }
  end

  defp local_tracker_error_payload(reason) do
    %{
      "error" => %{
        "message" => "Local tracker tool execution failed.",
        "reason" => inspect(reason)
      }
    }
  end

  defp supported_tool_names do
    Enum.map(tool_specs(), & &1["name"])
  end
end
