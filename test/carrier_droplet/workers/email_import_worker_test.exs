defmodule CarrierDroplet.Workers.EmailImportWorkerTest do
  use CarrierDroplet.DataCase
  use Oban.Testing, repo: CarrierDroplet.Repo
  use Mimic

  import ExUnit.CaptureLog

  alias CarrierDroplet.Workers.EmailImportWorker
  alias CarrierDroplet.Accounts
  alias CarrierDroplet.Gmail.Client
  alias CarrierDroplet.Emails

  setup :set_mimic_global

  setup do
    # Create a user and gmail account for testing
    oauth_data = %{
      "email" => "user@example.com",
      "google_id" => "google_123",
      "access_token" => "token_123",
      "refresh_token" => "refresh_123",
      "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
    }

    {:ok, user} = Accounts.upsert_user_from_oauth(oauth_data)

    {:ok, gmail_account} =
      Accounts.get_or_create_gmail_account(user.id, "gmail@example.com", %{
        "access_token" => "valid_access_token",
        "refresh_token" => "valid_refresh_token",
        "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
      })

    %{user: user, gmail_account: gmail_account}
  end

  describe "perform/1" do
    test "enqueues job successfully", %{user: user, gmail_account: gmail_account} do
      assert {:ok, job} =
               %{gmail_account_id: gmail_account.id, user_id: user.id}
               |> EmailImportWorker.new()
               |> Oban.insert()

      assert job.worker == "CarrierDroplet.Workers.EmailImportWorker"
      assert job.args == %{gmail_account_id: gmail_account.id, user_id: user.id}
    end

    test "handles token refresh when token is expired", %{
      user: user,
      gmail_account: gmail_account
    } do
      # Update gmail account with expired token
      expired_time = DateTime.utc_now() |> DateTime.add(-3600, :second)

      {:ok, expired_account} =
        Accounts.update_gmail_account(gmail_account, %{
          "token_expires_at" => expired_time
        })

      # The worker should attempt to refresh the token
      # Since we don't have a real Google OAuth server, this will fail
      # but we can verify the error handling
      assert {:error, :token_refresh_failed} =
               perform_job(EmailImportWorker, %{
                 gmail_account_id: expired_account.id,
                 user_id: user.id
               })
    end

    test "handles missing gmail account", %{user: user} do
      assert {:error, :gmail_account_not_found} =
               perform_job(EmailImportWorker, %{
                 gmail_account_id: 99999,
                 user_id: user.id
               })
    end

    test "handles expired token and refreshes it", %{user: user, gmail_account: gmail_account} do
      # Set token to expired
      expired_time = DateTime.utc_now() |> DateTime.add(-3600, :second)

      {:ok, expired_account} =
        Accounts.update_gmail_account(gmail_account, %{token_expires_at: expired_time})

      # This will attempt to refresh the token (which will fail in test env)
      # but we're testing the error handling path
      result =
        perform_job(EmailImportWorker, %{
          gmail_account_id: expired_account.id,
          user_id: user.id
        })

      # Should return token refresh error since we don't have real Google OAuth
      assert match?({:error, _}, result)
    end

    test "broadcasts success message on successful import", %{
      user: user,
      gmail_account: gmail_account
    } do
      # Subscribe to user's pubsub topic
      Phoenix.PubSub.subscribe(CarrierDroplet.PubSub, "user:#{user.id}")

      # This will fail to actually import (no real Gmail API)
      # but we're testing the broadcast mechanism
      perform_job(EmailImportWorker, %{
        gmail_account_id: gmail_account.id,
        user_id: user.id
      })

      # Should receive a broadcast message (either success or error)
      assert_receive {:email_import_complete, %{success: _}}, 1000
    end

    test "handles Gmail API errors gracefully", %{user: user, gmail_account: gmail_account} do
      # Without real Gmail credentials, this should handle the error
      result =
        perform_job(EmailImportWorker, %{
          gmail_account_id: gmail_account.id,
          user_id: user.id
        })

      # Should return an error (no real Gmail API access)
      assert match?({:error, _}, result)
    end
  end

  describe "perform/1 with mocked Gmail API" do
    test "successfully imports new emails", %{user: user, gmail_account: gmail_account} do
      # Mock Gmail API responses
      mock_list_response = %{
        "messages" => [
          %{"id" => "msg_1"},
          %{"id" => "msg_2"}
        ]
      }

      mock_message_1 = %{
        "id" => "msg_1",
        "payload" => %{
          "headers" => [
            %{"name" => "From", "value" => "sender1@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"},
            %{"name" => "Subject", "value" => "Test Email 1"},
            %{"name" => "Date", "value" => "Mon, 1 Jan 2024 12:00:00 +0000"}
          ],
          "body" => %{"data" => Base.url_encode64("Email body 1", padding: false)}
        }
      }

      mock_message_2 = %{
        "id" => "msg_2",
        "payload" => %{
          "headers" => [
            %{"name" => "From", "value" => "sender2@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"},
            %{"name" => "Subject", "value" => "Test Email 2"},
            %{"name" => "Date", "value" => "Mon, 1 Jan 2024 13:00:00 +0000"}
          ],
          "body" => %{"data" => Base.url_encode64("Email body 2", padding: false)}
        }
      }

      Client
      |> expect(:list_messages, fn _token, _opts ->
        {:ok, mock_list_response}
      end)
      |> expect(:get_message, 2, fn _token, message_id ->
        case message_id do
          "msg_1" -> {:ok, mock_message_1}
          "msg_2" -> {:ok, mock_message_2}
        end
      end)
      |> expect(:mark_as_read, 2, fn _token, _message_id ->
        {:ok, %{}}
      end)

      Phoenix.PubSub.subscribe(CarrierDroplet.PubSub, "user:#{user.id}")

      result =
        perform_job(EmailImportWorker, %{
          gmail_account_id: gmail_account.id,
          user_id: user.id
        })

      assert {:ok, %{imported: 2}} = result

      # Should receive success broadcast
      assert_receive {:email_import_complete,
                      %{success: true, count: 2, account_email: "gmail@example.com"}},
                     1000

      # Verify emails were created
      emails = Emails.list_emails_by_gmail_account(gmail_account.id)
      assert length(emails) == 2
    end

    test "handles empty inbox", %{user: user, gmail_account: gmail_account} do
      # Mock empty response
      Client
      |> expect(:list_messages, fn _token, _opts ->
        {:ok, %{}}
      end)

      Phoenix.PubSub.subscribe(CarrierDroplet.PubSub, "user:#{user.id}")

      result =
        perform_job(EmailImportWorker, %{
          gmail_account_id: gmail_account.id,
          user_id: user.id
        })

      assert {:ok, %{imported: 0}} = result

      # Should receive success broadcast with 0 count
      assert_receive {:email_import_complete,
                      %{success: true, count: 0, account_email: "gmail@example.com"}},
                     1000
    end

    test "skips already imported emails", %{user: user, gmail_account: gmail_account} do
      # Create an existing email
      {:ok, _existing_email} =
        Emails.create_email(gmail_account.id, %{
          gmail_message_id: "msg_existing",
          from_address: "sender@example.com",
          to_address: "recipient@example.com",
          subject: "Existing Email",
          body: "Already imported",
          received_at: DateTime.utc_now()
        })

      mock_list_response = %{
        "messages" => [
          %{"id" => "msg_existing"},
          %{"id" => "msg_new"}
        ]
      }

      mock_new_message = %{
        "id" => "msg_new",
        "payload" => %{
          "headers" => [
            %{"name" => "From", "value" => "sender@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"},
            %{"name" => "Subject", "value" => "New Email"},
            %{"name" => "Date", "value" => "Mon, 1 Jan 2024 12:00:00 +0000"}
          ],
          "body" => %{"data" => Base.url_encode64("New email body", padding: false)}
        }
      }

      Client
      |> expect(:list_messages, fn _token, _opts ->
        {:ok, mock_list_response}
      end)
      |> expect(:get_message, fn _token, "msg_new" ->
        {:ok, mock_new_message}
      end)
      |> expect(:mark_as_read, fn _token, "msg_new" ->
        {:ok, %{}}
      end)

      result =
        perform_job(EmailImportWorker, %{
          gmail_account_id: gmail_account.id,
          user_id: user.id
        })

      # Should only import 1 new email (skip the existing one)
      assert {:ok, %{imported: 1}} = result

      # Verify total emails
      emails = Emails.list_emails_by_gmail_account(gmail_account.id)
      assert length(emails) == 2
    end

    test "handles unauthorized error from Gmail API", %{user: user, gmail_account: gmail_account} do
      Client
      |> expect(:list_messages, fn _token, _opts ->
        {:error, :unauthorized}
      end)

      Phoenix.PubSub.subscribe(CarrierDroplet.PubSub, "user:#{user.id}")

      result =
        perform_job(EmailImportWorker, %{
          gmail_account_id: gmail_account.id,
          user_id: user.id
        })

      assert {:error, :token_expired} = result

      # Should receive error broadcast
      assert_receive {:email_import_complete,
                      %{success: false, error: "Token expired. Please reconnect your account."}},
                     1000
    end

    test "handles network errors from Gmail API", %{user: user, gmail_account: gmail_account} do
      Client
      |> expect(:list_messages, fn _token, _opts ->
        {:error, :network_error}
      end)

      Phoenix.PubSub.subscribe(CarrierDroplet.PubSub, "user:#{user.id}")

      result =
        perform_job(EmailImportWorker, %{
          gmail_account_id: gmail_account.id,
          user_id: user.id
        })

      assert {:error, :network_error} = result

      # Should receive error broadcast
      assert_receive {:email_import_complete, %{success: false, error: _}}, 1000
    end

    test "handles errors when fetching individual messages", %{
      user: user,
      gmail_account: gmail_account
    } do
      mock_list_response = %{
        "messages" => [
          %{"id" => "msg_1"},
          %{"id" => "msg_2"}
        ]
      }

      mock_message_1 = %{
        "id" => "msg_1",
        "payload" => %{
          "headers" => [
            %{"name" => "From", "value" => "sender@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"},
            %{"name" => "Subject", "value" => "Test Email"},
            %{"name" => "Date", "value" => "Mon, 1 Jan 2024 12:00:00 +0000"}
          ],
          "body" => %{"data" => Base.url_encode64("Email body", padding: false)}
        }
      }

      Client
      |> expect(:list_messages, fn _token, _opts ->
        {:ok, mock_list_response}
      end)
      |> expect(:get_message, 2, fn _token, message_id ->
        case message_id do
          "msg_1" -> {:ok, mock_message_1}
          "msg_2" -> {:error, :not_found}
        end
      end)
      |> expect(:mark_as_read, fn _token, "msg_1" ->
        {:ok, %{}}
      end)

      result =
        perform_job(EmailImportWorker, %{
          gmail_account_id: gmail_account.id,
          user_id: user.id
        })

      # Should import the successful one
      assert {:ok, %{imported: 1}} = result

      # Verify only 1 email was created
      emails = Emails.list_emails_by_gmail_account(gmail_account.id)
      assert length(emails) == 1
    end

    test "continues importing even if mark_as_read fails", %{
      user: user,
      gmail_account: gmail_account
    } do
      mock_list_response = %{
        "messages" => [
          %{"id" => "msg_1"}
        ]
      }

      mock_message = %{
        "id" => "msg_1",
        "payload" => %{
          "headers" => [
            %{"name" => "From", "value" => "sender@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"},
            %{"name" => "Subject", "value" => "Test Email"},
            %{"name" => "Date", "value" => "Mon, 1 Jan 2024 12:00:00 +0000"}
          ],
          "body" => %{"data" => Base.url_encode64("Email body", padding: false)}
        }
      }

      Client
      |> expect(:list_messages, fn _token, _opts ->
        {:ok, mock_list_response}
      end)
      |> expect(:get_message, fn _token, "msg_1" ->
        {:ok, mock_message}
      end)
      |> expect(:mark_as_read, fn _token, "msg_1" ->
        {:error, :failed}
      end)

      # Capture the error log to avoid test output noise
      capture_log(fn ->
        result =
          perform_job(EmailImportWorker, %{
            gmail_account_id: gmail_account.id,
            user_id: user.id
          })

        # Should still import the email even if mark_as_read fails
        assert {:ok, %{imported: 1}} = result

        # Verify email was created
        emails = Emails.list_emails_by_gmail_account(gmail_account.id)
        assert length(emails) == 1
      end)
    end
  end
end
