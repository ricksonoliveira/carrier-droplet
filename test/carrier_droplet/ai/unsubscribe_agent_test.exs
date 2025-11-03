defmodule CarrierDroplet.AI.UnsubscribeAgentTest do
  use ExUnit.Case, async: false
  use Mimic

  alias CarrierDroplet.AI.UnsubscribeAgent

  setup :set_mimic_global

  describe "find_unsubscribe_links/1 with mocked API" do
    test "successfully finds unsubscribe link" do
      email_content = """
      Hello,

      This is a newsletter.

      To unsubscribe, click here: https://example.com/unsubscribe?id=123

      Thanks!
      """

      # Mock response returns URLs one per line
      mock_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => "https://example.com/unsubscribe?id=123"
              }
            }
          ]
        }
      }

      Req
      |> expect(:post, fn _url, _opts ->
        {:ok, mock_response}
      end)

      System.put_env("OPENAI_API_KEY", "test-key")

      result = UnsubscribeAgent.find_unsubscribe_links(email_content)

      assert {:ok, links} = result
      assert is_list(links)
      assert "https://example.com/unsubscribe?id=123" in links

      System.delete_env("OPENAI_API_KEY")
    end

    test "finds multiple unsubscribe links" do
      email_content = """
      Unsubscribe here: https://example.com/unsubscribe
      Or here: https://example.com/preferences
      """

      # Mock response returns URLs one per line
      mock_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => """
                https://example.com/unsubscribe
                https://example.com/preferences
                """
              }
            }
          ]
        }
      }

      Req
      |> expect(:post, fn _url, _opts ->
        {:ok, mock_response}
      end)

      System.put_env("OPENAI_API_KEY", "test-key")

      result = UnsubscribeAgent.find_unsubscribe_links(email_content)

      assert {:ok, links} = result
      assert length(links) == 2

      System.delete_env("OPENAI_API_KEY")
    end

    test "returns empty list when no unsubscribe link found" do
      email_content = """
      Hello,

      This is a personal email with no unsubscribe link.

      Best regards,
      John
      """

      # AI returns "NONE" when no links found
      mock_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => "NONE"
              }
            }
          ]
        }
      }

      Req
      |> expect(:post, fn _url, _opts ->
        {:ok, mock_response}
      end)

      System.put_env("OPENAI_API_KEY", "test-key")

      result = UnsubscribeAgent.find_unsubscribe_links(email_content)

      assert {:ok, []} = result

      System.delete_env("OPENAI_API_KEY")
    end

    test "handles HTML email content" do
      email_content = """
      <html>
        <body>
          <p>This is an HTML email</p>
          <a href="https://example.com/unsubscribe">Unsubscribe</a>
        </body>
      </html>
      """

      mock_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => "https://example.com/unsubscribe"
              }
            }
          ]
        }
      }

      Req
      |> expect(:post, fn _url, _opts ->
        {:ok, mock_response}
      end)

      System.put_env("OPENAI_API_KEY", "test-key")

      result = UnsubscribeAgent.find_unsubscribe_links(email_content)

      assert {:ok, ["https://example.com/unsubscribe"]} = result

      System.delete_env("OPENAI_API_KEY")
    end

    test "handles API error" do
      email_content = "Test email"

      Req
      |> expect(:post, fn _url, _opts ->
        {:error, %{reason: :timeout}}
      end)

      System.put_env("OPENAI_API_KEY", "test-key")

      result = UnsubscribeAgent.find_unsubscribe_links(email_content)

      assert {:error, _} = result

      System.delete_env("OPENAI_API_KEY")
    end

    test "handles response with no valid URLs" do
      email_content = "Test email"

      # AI returns text that doesn't contain valid URLs
      mock_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => "No unsubscribe links found in this email"
              }
            }
          ]
        }
      }

      Req
      |> expect(:post, fn _url, _opts ->
        {:ok, mock_response}
      end)

      System.put_env("OPENAI_API_KEY", "test-key")

      result = UnsubscribeAgent.find_unsubscribe_links(email_content)

      # Should return empty list when no valid URLs in response
      assert {:ok, []} = result

      System.delete_env("OPENAI_API_KEY")
    end

    test "returns error when no API key is available" do
      email_content = "Test email"

      result = UnsubscribeAgent.find_unsubscribe_links(email_content)

      assert {:error, :no_api_key} = result
    end
  end

  describe "unsubscribe/1 with mocked API" do
    test "successfully unsubscribes when link is found" do
      email_content = """
      Newsletter content

      Unsubscribe: https://example.com/unsubscribe
      """

      # Mock finding the unsubscribe link (returns URL one per line)
      mock_find_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => "https://example.com/unsubscribe"
              }
            }
          ]
        }
      }

      # Mock the HTTP GET request to the unsubscribe link
      mock_get_response = %{status: 200, body: "Unsubscribed successfully"}

      Req
      |> expect(:post, fn _url, _opts ->
        {:ok, mock_find_response}
      end)
      |> expect(:get, fn _url, _opts ->
        {:ok, mock_get_response}
      end)

      System.put_env("OPENAI_API_KEY", "test-key")

      result = UnsubscribeAgent.unsubscribe(email_content)

      assert {:ok, _} = result

      System.delete_env("OPENAI_API_KEY")
    end

    test "returns error when no unsubscribe link found" do
      email_content = "Personal email with no unsubscribe link"

      # AI returns NONE when no links found
      mock_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => "NONE"
              }
            }
          ]
        }
      }

      Req
      |> expect(:post, fn _url, _opts ->
        {:ok, mock_response}
      end)

      System.put_env("OPENAI_API_KEY", "test-key")

      result = UnsubscribeAgent.unsubscribe(email_content)

      assert {:error, :no_unsubscribe_link} = result

      System.delete_env("OPENAI_API_KEY")
    end

    test "handles HTTP error when visiting unsubscribe link" do
      email_content = "Newsletter with unsubscribe link"

      mock_find_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => "https://example.com/unsubscribe"
              }
            }
          ]
        }
      }

      Req
      |> expect(:post, fn _url, _opts ->
        {:ok, mock_find_response}
      end)
      |> expect(:get, fn _url, _opts ->
        {:error, %{reason: :network_error}}
      end)

      System.put_env("OPENAI_API_KEY", "test-key")

      result = UnsubscribeAgent.unsubscribe(email_content)

      assert {:error, _} = result

      System.delete_env("OPENAI_API_KEY")
    end
  end
end
