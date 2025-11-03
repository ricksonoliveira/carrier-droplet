defmodule CarrierDroplet.AI.Client do
  @moduledoc """
  AI client for email categorization and summarization using OpenAI API.
  """

  @openai_api_base "https://api.openai.com/v1"

  @doc """
  Categorizes an email based on available categories.
  Returns the category ID that best matches the email.
  """
  def categorize_email(email_content, categories) do
    api_key = get_api_key()

    if api_key == nil do
      {:error, :no_api_key}
    else
      prompt = build_categorization_prompt(email_content, categories)

      case call_openai(api_key, prompt) do
        {:ok, response} ->
          parse_categorization_response(response, categories)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Generates a summary of an email.
  """
  def summarize_email(email_content) do
    api_key = get_api_key()

    if api_key == nil do
      {:error, :no_api_key}
    else
      prompt = """
      Please provide a concise 1-2 sentence summary of the following email:

      #{email_content}

      Summary:
      """

      case call_openai(api_key, prompt) do
        {:ok, response} ->
          {:ok, String.trim(response)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Private functions

  defp get_api_key do
    System.get_env("OPENAI_API_KEY")
  end

  defp build_categorization_prompt(email_content, categories) do
    categories_text =
      categories
      |> Enum.map(fn cat ->
        "ID: #{cat.id}, Name: #{cat.name}, Description: #{cat.description}"
      end)
      |> Enum.join("\n")

    """
    You are an email categorization assistant. Given an email and a list of categories, determine which category best fits the email.

    Categories:
    #{categories_text}

    Email content:
    #{email_content}

    Please respond with ONLY the category ID number that best matches this email. If none of the categories are a good fit, respond with "NONE".
    """
  end

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

    case Req.post("#{@openai_api_base}/chat/completions",
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

  defp parse_categorization_response(response, categories) do
    response = String.trim(response)

    cond do
      response == "NONE" ->
        {:ok, nil}

      true ->
        # Try to parse as integer
        case Integer.parse(response) do
          {category_id, _} ->
            # Verify the category exists
            if Enum.any?(categories, fn cat -> cat.id == category_id end) do
              {:ok, category_id}
            else
              {:ok, nil}
            end

          :error ->
            {:ok, nil}
        end
    end
  end
end
