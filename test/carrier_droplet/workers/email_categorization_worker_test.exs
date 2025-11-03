defmodule CarrierDroplet.Workers.EmailCategorizationWorkerTest do
  use CarrierDroplet.DataCase
  use Oban.Testing, repo: CarrierDroplet.Repo

  alias CarrierDroplet.Workers.EmailCategorizationWorker
  alias CarrierDroplet.Accounts
  alias CarrierDroplet.Emails

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
        "access_token" => "token",
        "refresh_token" => "refresh"
      })

    # Create a category
    {:ok, category} =
      Emails.create_category(user, %{
        name: "Work",
        description: "Work-related emails from colleagues and clients"
      })

    # Create an email
    email_data = %{
      gmail_message_id: "msg_123",
      subject: "Project Update",
      from_address: "colleague@company.com",
      to_address: "user@example.com",
      received_at: DateTime.utc_now(),
      original_content: "Here's the latest update on the project..."
    }

    {:ok, email} = Emails.create_email(gmail_account.id, email_data)

    %{user: user, gmail_account: gmail_account, category: category, email: email}
  end

  describe "perform/1" do
    test "enqueues job successfully", %{email: email} do
      assert {:ok, job} =
               %{email_id: email.id}
               |> EmailCategorizationWorker.new()
               |> Oban.insert()

      assert job.worker == "CarrierDroplet.Workers.EmailCategorizationWorker"
      assert job.args == %{email_id: email.id}
    end

    test "handles missing email" do
      assert {:error, :email_not_found} =
               perform_job(EmailCategorizationWorker, %{email_id: 99999})
    end

    test "handles email with no categories available", %{gmail_account: _gmail_account} do
      # Create a new user with no categories
      oauth_data = %{
        "email" => "user2@example.com",
        "google_id" => "google_456",
        "access_token" => "token_456",
        "refresh_token" => "refresh_456",
        "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      {:ok, user2} = Accounts.upsert_user_from_oauth(oauth_data)

      {:ok, gmail_account2} =
        Accounts.get_or_create_gmail_account(user2.id, "gmail2@example.com", %{
          "access_token" => "token",
          "refresh_token" => "refresh"
        })

      email_data = %{
        gmail_message_id: "msg_456",
        subject: "Test Email",
        from_address: "sender@example.com",
        to_address: "user2@example.com",
        received_at: DateTime.utc_now(),
        original_content: "Test content"
      }

      {:ok, email} = Emails.create_email(gmail_account2.id, email_data)

      # Should handle gracefully when no categories exist
      # Without categories, the worker should still succeed but with nil values
      assert {:ok, result} = perform_job(EmailCategorizationWorker, %{email_id: email.id})
      assert result.category_id == nil
      # Summary might be nil when no categories are available
      assert result.summary == nil or is_binary(result.summary)
    end
  end
end
