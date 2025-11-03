defmodule CarrierDroplet.Gmail.Client do
  @moduledoc """
  Gmail API client using Req for HTTP requests.
  """

  @gmail_api_base "https://gmail.googleapis.com/gmail/v1"
  @oauth_token_url "https://oauth2.googleapis.com/token"

  @doc """
  Refreshes an access token using a refresh token.
  """
  def refresh_access_token(refresh_token) do
    client_id = System.get_env("GOOGLE_CLIENT_ID")
    client_secret = System.get_env("GOOGLE_CLIENT_SECRET")

    body = %{
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: refresh_token,
      grant_type: "refresh_token"
    }

    case Req.post(@oauth_token_url, json: body) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response}

      {:ok, %{status: status, body: body}} ->
        {:error, "Token refresh failed with status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists messages from Gmail with optional query parameters.
  """
  def list_messages(access_token, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 100)
    query = Keyword.get(opts, :query, "")

    params = %{
      maxResults: max_results
    }

    params = if query != "", do: Map.put(params, :q, query), else: params

    Req.get("#{@gmail_api_base}/users/me/messages",
      auth: {:bearer, access_token},
      params: params
    )
    |> handle_response()
  end

  @doc """
  Gets a single message by ID.
  """
  def get_message(access_token, message_id) do
    Req.get("#{@gmail_api_base}/users/me/messages/#{message_id}",
      auth: {:bearer, access_token},
      params: %{format: "full"}
    )
    |> handle_response()
  end

  @doc """
  Modifies message labels (for archiving).
  """
  def modify_message(access_token, message_id, add_labels \\ [], remove_labels \\ []) do
    body = %{
      addLabelIds: add_labels,
      removeLabelIds: remove_labels
    }

    Req.post("#{@gmail_api_base}/users/me/messages/#{message_id}/modify",
      auth: {:bearer, access_token},
      json: body
    )
    |> handle_response()
  end

  @doc """
  Archives a message by removing the INBOX label.
  """
  def archive_message(access_token, message_id) do
    modify_message(access_token, message_id, [], ["INBOX"])
  end

  @doc """
  Marks a message as read by removing the UNREAD label.
  """
  def mark_as_read(access_token, message_id) do
    modify_message(access_token, message_id, [], ["UNREAD"])
  end

  @doc """
  Deletes a message permanently.
  """
  def delete_message(access_token, message_id) do
    Req.delete("#{@gmail_api_base}/users/me/messages/#{message_id}",
      auth: {:bearer, access_token}
    )
    |> handle_response()
  end

  @doc """
  Parses a Gmail message into a simplified format.
  """
  def parse_message(message) do
    headers = get_headers(message)

    %{
      gmail_message_id: message["id"],
      subject: get_header(headers, "Subject") || "(No Subject)",
      from_address: get_header(headers, "From") || "",
      to_address: get_header(headers, "To") || "",
      received_at: parse_date(get_header(headers, "Date")),
      original_content: get_body(message)
    }
  end

  # Private functions

  defp handle_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: 401}}) do
    {:error, :unauthorized}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    {:error, {status, body}}
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end

  defp get_headers(%{"payload" => %{"headers" => headers}}), do: headers
  defp get_headers(_), do: []

  defp get_header(headers, name) do
    headers
    |> Enum.find(fn h -> h["name"] == name end)
    |> case do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp get_body(%{"payload" => payload}) do
    extract_body(payload)
  end

  defp get_body(_), do: ""

  defp extract_body(%{"body" => %{"data" => data}}) when is_binary(data) and data != "" do
    Base.url_decode64!(data, padding: false)
  end

  defp extract_body(%{"parts" => parts}) when is_list(parts) do
    parts
    |> Enum.map(&extract_body/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp extract_body(_), do: ""

  defp parse_date(nil), do: DateTime.utc_now()

  defp parse_date(date_string) do
    case DateTimeParser.parse_datetime(date_string) do
      {:ok, datetime} -> datetime
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> DateTime.utc_now()
    end
  end
end
