defmodule SymphonyElixir.Tracker.Local do
  @moduledoc """
  File-backed tracker adapter for local development without Linear.

  The board file is JSON with an `issues` list. Symphony updates the same file
  when agents create comments or move issue state, which makes the file a simple
  local queue and audit log.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.Config
  alias SymphonyElixir.Linear.Issue

  @spec fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues do
    fetch_issues_by_states(Config.settings!().tracker.active_states)
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names) do
    with {:ok, board} <- read_board() do
      states =
        state_names
        |> Enum.map(&normalize_state/1)
        |> MapSet.new()

      issues =
        board
        |> board_issues()
        |> Enum.filter(fn %Issue{state: state} -> MapSet.member?(states, normalize_state(state)) end)

      {:ok, issues}
    end
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) do
    with {:ok, board} <- read_board() do
      wanted_ids = MapSet.new(issue_ids)

      issues =
        board
        |> board_issues()
        |> Enum.filter(fn %Issue{id: id} -> MapSet.member?(wanted_ids, id) end)

      {:ok, issues}
    end
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    update_board(fn board ->
      comments = Map.get(board, "comments", [])

      comment = %{
        "issue_id" => issue_id,
        "body" => body,
        "created_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      }

      Map.put(board, "comments", comments ++ [comment])
    end)
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name)
      when is_binary(issue_id) and is_binary(state_name) do
    update_board(fn board ->
      issues =
        board
        |> Map.get("issues", [])
        |> Enum.map(fn
          %{"id" => ^issue_id} = issue ->
            issue
            |> Map.put("state", state_name)
            |> Map.put("updated_at", DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601())

          issue ->
            issue
        end)

      Map.put(board, "issues", issues)
    end)
  end

  defp update_board(fun) when is_function(fun, 1) do
    with {:ok, board} <- read_board(),
         updated_board <- fun.(board),
         :ok <- write_board(updated_board) do
      :ok
    end
  end

  defp read_board do
    with path when is_binary(path) <- tracker_path(),
         {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body),
         true <- is_map(decoded) do
      {:ok, decoded}
    else
      nil -> {:error, :missing_local_tracker_path}
      {:error, reason} -> {:error, reason}
      false -> {:error, :invalid_local_tracker_board}
      {:ok, _decoded} -> {:error, :invalid_local_tracker_board}
    end
  end

  defp write_board(board) when is_map(board) do
    with path when is_binary(path) <- tracker_path(),
         :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, encoded} <- Jason.encode(board, pretty: true) do
      File.write(path, encoded <> "\n")
    else
      nil -> {:error, :missing_local_tracker_path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp board_issues(board) when is_map(board) do
    board
    |> Map.get("issues", [])
    |> Enum.map(&issue_from_map/1)
    |> Enum.filter(&match?(%Issue{}, &1))
  end

  defp issue_from_map(%{} = attrs) do
    identifier = string_value(attrs, "identifier") || string_value(attrs, "id")

    %Issue{
      id: string_value(attrs, "id") || identifier,
      identifier: identifier,
      title: string_value(attrs, "title") || "",
      description: string_value(attrs, "description"),
      priority: integer_value(attrs, "priority"),
      state: string_value(attrs, "state") || "Todo",
      branch_name: string_value(attrs, "branch_name"),
      url: string_value(attrs, "url"),
      assignee_id: string_value(attrs, "assignee_id"),
      labels: list_of_strings(attrs, "labels"),
      blocked_by: Map.get(attrs, "blocked_by", []),
      assigned_to_worker: Map.get(attrs, "assigned_to_worker", true) != false,
      created_at: datetime_value(attrs, "created_at"),
      updated_at: datetime_value(attrs, "updated_at")
    }
  end

  defp issue_from_map(_attrs), do: nil

  defp tracker_path do
    Config.settings!().tracker.path
  end

  defp string_value(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) -> value
      value when is_integer(value) -> Integer.to_string(value)
      value when is_atom(value) -> Atom.to_string(value)
      _ -> nil
    end
  end

  defp integer_value(attrs, key) do
    case Map.get(attrs, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp list_of_strings(attrs, key) do
    case Map.get(attrs, key) do
      values when is_list(values) ->
        values
        |> Enum.map(&to_string/1)
        |> Enum.map(&String.downcase/1)

      _ ->
        []
    end
  end

  defp datetime_value(attrs, key) do
    with value when is_binary(value) <- Map.get(attrs, key),
         {:ok, datetime, _offset} <- DateTime.from_iso8601(value) do
      datetime
    else
      _ -> nil
    end
  end

  defp normalize_state(state) when is_binary(state) do
    state
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_state(_state), do: ""
end
