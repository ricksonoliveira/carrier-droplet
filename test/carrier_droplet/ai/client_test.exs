defmodule CarrierDroplet.AI.ClientTest do
  use ExUnit.Case, async: false
  use Mimic

  alias CarrierDroplet.AI.Client

  setup :set_mimic_global

  describe "categorize_email/2 with mocked API" do
    test "successfully categorizes email" do
      email_content = "This is a promotional email about a 50% off sale"

      categories = [
        %{id: 1, name: "Promotions", description: "Marketing and promotional emails"},
        %{id: 2, name: "Personal", description: "Personal correspondence"},
        %{id: 3, name: "Work", description: "Work-related emails"}
      ]

      # Mock successful OpenAI API response - returns category ID
      mock_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => "1"
              }
            }
          ]
        }
      }

      Req
      |> expect(:post, fn _url, _opts ->
        {:ok, mock_response}
      end)

      # Set API key for this test
      System.put_env("OPENAI_API_KEY", "test-key")

      result = Client.categorize_email(email_content, categories)

      assert {:ok, category_id} = result
      assert category_id == 1

      # Clean up
      System.delete_env("OPENAI_API_KEY")
    end

    test "handles NONE response from AI" do
      email_content = "Random email content that doesn't fit any category"

      categories = [
        %{id: 1, name: "Promotions", description: "Marketing emails"},
        %{id: 2, name: "Personal", description: "Personal emails"}
      ]

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

      result = Client.categorize_email(email_content, categories)

      # Should return nil when AI returns NONE
      assert {:ok, nil} = result

      System.delete_env("OPENAI_API_KEY")
    end

    test "handles invalid category ID from AI" do
      email_content = "Test email"

      categories = [
        %{id: 1, name: "Promotions", description: "Marketing emails"},
        %{id: 2, name: "Personal", description: "Personal emails"}
      ]

      # AI returns an ID that doesn't exist in the categories list
      mock_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => "999"
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

      result = Client.categorize_email(email_content, categories)

      # Should return nil when category ID doesn't exist
      assert {:ok, nil} = result

      System.delete_env("OPENAI_API_KEY")
    end

    test "handles API error response" do
      email_content = "Test email"

      categories = [
        %{id: 1, name: "Test", description: "Test category"}
      ]

      Req
      |> expect(:post, fn _url, _opts ->
        {:error, %{reason: :timeout}}
      end)

      System.put_env("OPENAI_API_KEY", "test-key")

      result = Client.categorize_email(email_content, categories)

      assert {:error, _} = result

      System.delete_env("OPENAI_API_KEY")
    end

    test "returns error when no API key is available" do
      # Without OPENAI_API_KEY env var, should return error
      email_content = "This is a promotional email about a sale"

      categories = [
        %{id: 1, name: "Promotions", description: "Marketing emails"}
      ]

      result = Client.categorize_email(email_content, categories)

      # Should return error when no API key
      assert {:error, :no_api_key} = result
    end

    test "handles empty categories list" do
      email_content = "Test email content"
      categories = []

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

      result = Client.categorize_email(email_content, categories)

      assert {:ok, nil} = result

      System.delete_env("OPENAI_API_KEY")
    end
  end

  describe "summarize_email/1 with mocked API" do
    test "successfully generates summary" do
      email_content =
        "This is a test email about a meeting tomorrow at 3pm in the conference room."

      mock_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => "Meeting scheduled for tomorrow at 3pm in conference room."
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

      result = Client.summarize_email(email_content)

      assert {:ok, summary} = result
      assert summary == "Meeting scheduled for tomorrow at 3pm in conference room."

      System.delete_env("OPENAI_API_KEY")
    end

    test "handles API error" do
      email_content = "Test email"

      Req
      |> expect(:post, fn _url, _opts ->
        {:error, %{reason: :network_error}}
      end)

      System.put_env("OPENAI_API_KEY", "test-key")

      result = Client.summarize_email(email_content)

      assert {:error, _} = result

      System.delete_env("OPENAI_API_KEY")
    end

    test "returns error when no API key is available" do
      email_content = "Test email"

      result = Client.summarize_email(email_content)

      # Without API key, should return error (either :no_api_key or :unauthorized)
      assert match?({:error, _}, result)
    end

    test "handles empty email content" do
      email_content = ""

      mock_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => "Empty email."
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

      result = Client.summarize_email(email_content)

      assert {:ok, "Empty email."} = result

      System.delete_env("OPENAI_API_KEY")
    end

    test "handles very long email content" do
      email_content = String.duplicate("This is a long email. ", 1000)

      mock_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => "Long repetitive email content."
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

      result = Client.summarize_email(email_content)

      assert {:ok, summary} = result
      assert String.length(summary) < String.length(email_content)

      System.delete_env("OPENAI_API_KEY")
    end
  end
end
