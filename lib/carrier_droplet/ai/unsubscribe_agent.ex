defmodule CarrierDroplet.AI.UnsubscribeAgent do
  @moduledoc """
  AI agent for finding and processing unsubscribe links in emails.
  """

  @doc """
  Finds unsubscribe links in email content using AI.
  Returns a list of potential unsubscribe URLs.
  """
  def find_unsubscribe_links(email_content) do
    api_key = System.get_env("OPENAI_API_KEY")

    if api_key == nil do
      {:error, :no_api_key}
    else
      prompt = """
      You are an email unsubscribe assistant. Analyze the following email content and extract any unsubscribe links.

      Email content:
      #{email_content}

      Please respond with ONLY the unsubscribe URLs, one per line. If there are no unsubscribe links, respond with "NONE".
      Look for:
      - Links containing "unsubscribe"
      - Links in email footers
      - Preference center links
      - List management links

      URLs:
      """

      case call_openai(api_key, prompt) do
        {:ok, response} ->
          parse_urls(response)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Attempts to unsubscribe from an email by visiting the unsubscribe link.
  This is a simplified version - in production, you might want to use a headless browser.
  """
  def unsubscribe(email_content) do
    case find_unsubscribe_links(email_content) do
      {:ok, []} ->
        {:error, :no_unsubscribe_link}

      {:ok, [url | _rest]} ->
        # Visit the unsubscribe URL
        case Req.get(url, redirect: true) do
          {:ok, %{status: status}} when status in 200..299 ->
            {:ok, url}

          {:ok, %{status: status}} ->
            {:error, {:http_error, status}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp call_openai(api_key, prompt) do
    body = %{
      model: "gpt-4o-mini",
      messages: [
        %{
          role: "user",
          content: prompt
        }
      ],
      temperature: 0.3,
      max_tokens: 500
    }

    case Req.post("https://api.openai.com/v1/chat/completions",
           auth: {:bearer, api_key},
           json: body
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        {:ok, content}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_urls(response) do
    response = String.trim(response)

    if response == "NONE" do
      {:ok, []}
    else
      urls =
        response
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(fn line ->
          String.starts_with?(line, "http://") or String.starts_with?(line, "https://")
        end)

      {:ok, urls}
    end
  end
end
