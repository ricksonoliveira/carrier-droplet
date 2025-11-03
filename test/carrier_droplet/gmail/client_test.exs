defmodule CarrierDroplet.Gmail.ClientTest do
  use ExUnit.Case, async: true

  alias CarrierDroplet.Gmail.Client

  describe "parse_message/1" do
    test "parses a basic Gmail message" do
      message = %{
        "id" => "msg_123",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => "Test Subject"},
            %{"name" => "From", "value" => "sender@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"},
            %{"name" => "Date", "value" => "Mon, 1 Nov 2021 10:00:00 +0000"}
          ],
          "body" => %{
            "data" => Base.url_encode64("This is the email body", padding: false)
          }
        }
      }

      parsed = Client.parse_message(message)

      assert parsed.gmail_message_id == "msg_123"
      assert parsed.subject == "Test Subject"
      assert parsed.from_address == "sender@example.com"
      assert parsed.to_address == "recipient@example.com"
      assert parsed.original_content =~ "This is the email body"
    end

    test "handles missing subject" do
      message = %{
        "id" => "msg_456",
        "payload" => %{
          "headers" => [
            %{"name" => "From", "value" => "sender@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"}
          ],
          "body" => %{"data" => Base.url_encode64("Body", padding: false)}
        }
      }

      parsed = Client.parse_message(message)
      assert parsed.subject == "(No Subject)"
    end

    test "handles multipart messages" do
      message = %{
        "id" => "msg_789",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => "Multipart"},
            %{"name" => "From", "value" => "sender@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"}
          ],
          "parts" => [
            %{
              "mimeType" => "text/plain",
              "body" => %{"data" => Base.url_encode64("Plain text part", padding: false)}
            },
            %{
              "mimeType" => "text/html",
              "body" => %{"data" => Base.url_encode64("<p>HTML part</p>", padding: false)}
            }
          ]
        }
      }

      parsed = Client.parse_message(message)
      assert parsed.original_content =~ "Plain text part"
    end

    test "handles nested multipart messages" do
      message = %{
        "id" => "msg_nested",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => "Nested"},
            %{"name" => "From", "value" => "sender@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"}
          ],
          "parts" => [
            %{
              "mimeType" => "multipart/alternative",
              "parts" => [
                %{
                  "mimeType" => "text/plain",
                  "body" => %{"data" => Base.url_encode64("Nested text", padding: false)}
                }
              ]
            }
          ]
        }
      }

      parsed = Client.parse_message(message)
      assert parsed.original_content =~ "Nested text"
    end

    test "handles empty body" do
      message = %{
        "id" => "msg_empty",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => "Empty"},
            %{"name" => "From", "value" => "sender@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"}
          ],
          "body" => %{}
        }
      }

      parsed = Client.parse_message(message)
      assert parsed.original_content == ""
    end

    test "handles missing from address" do
      message = %{
        "id" => "msg_no_from",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => "Test"},
            %{"name" => "To", "value" => "recipient@example.com"}
          ],
          "body" => %{"data" => Base.url_encode64("Body", padding: false)}
        }
      }

      parsed = Client.parse_message(message)
      # Returns empty string when header is missing
      assert parsed.from_address == "" or parsed.from_address == nil
    end

    test "handles missing to address" do
      message = %{
        "id" => "msg_no_to",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => "Test"},
            %{"name" => "From", "value" => "sender@example.com"}
          ],
          "body" => %{"data" => Base.url_encode64("Body", padding: false)}
        }
      }

      parsed = Client.parse_message(message)
      # Returns empty string when header is missing
      assert parsed.to_address == "" or parsed.to_address == nil
    end

    test "handles message with attachments" do
      message = %{
        "id" => "msg_attachments",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => "With Attachment"},
            %{"name" => "From", "value" => "sender@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"}
          ],
          "parts" => [
            %{
              "mimeType" => "text/plain",
              "body" => %{"data" => Base.url_encode64("Email body", padding: false)}
            },
            %{
              "mimeType" => "application/pdf",
              "filename" => "document.pdf",
              "body" => %{"attachmentId" => "att_123"}
            }
          ]
        }
      }

      parsed = Client.parse_message(message)
      assert parsed.original_content =~ "Email body"
    end

    test "handles HTML-only email" do
      message = %{
        "id" => "msg_html",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => "HTML Email"},
            %{"name" => "From", "value" => "sender@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"}
          ],
          "parts" => [
            %{
              "mimeType" => "text/html",
              "body" => %{
                "data" =>
                  Base.url_encode64("<html><body><h1>Hello</h1></body></html>", padding: false)
              }
            }
          ]
        }
      }

      parsed = Client.parse_message(message)
      assert parsed.original_content =~ "Hello"
    end

    test "handles very long subject" do
      long_subject = String.duplicate("Very long subject ", 50)

      message = %{
        "id" => "msg_long_subject",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => long_subject},
            %{"name" => "From", "value" => "sender@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"}
          ],
          "body" => %{"data" => Base.url_encode64("Body", padding: false)}
        }
      }

      parsed = Client.parse_message(message)
      assert parsed.subject == long_subject
    end

    test "handles email with special characters in headers" do
      message = %{
        "id" => "msg_special",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => "Test 🎉 Special Chars: @#$%"},
            %{"name" => "From", "value" => "sender+tag@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"}
          ],
          "body" => %{"data" => Base.url_encode64("Body with émojis 🚀", padding: false)}
        }
      }

      parsed = Client.parse_message(message)
      assert parsed.subject =~ "🎉"
      assert parsed.from_address == "sender+tag@example.com"
      assert parsed.original_content =~ "🚀"
    end
  end

  describe "list_messages/2" do
    test "returns error without valid access token" do
      result = Client.list_messages("invalid_token", [])

      assert match?({:error, _}, result)
    end

    test "accepts query parameters" do
      # This will fail without a real token, but we're testing the function signature
      result = Client.list_messages("invalid_token", q: "is:unread", max_results: 10)

      assert match?({:error, _}, result)
    end
  end

  describe "get_message/2" do
    test "returns error without valid access token" do
      result = Client.get_message("invalid_token", "msg_123")

      assert match?({:error, _}, result)
    end
  end

  describe "mark_as_read/2" do
    test "returns error without valid access token" do
      result = Client.mark_as_read("invalid_token", "msg_123")

      assert match?({:error, _}, result)
    end
  end
end
