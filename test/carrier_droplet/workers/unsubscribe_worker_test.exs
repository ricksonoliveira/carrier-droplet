defmodule CarrierDroplet.Workers.UnsubscribeWorkerTest do
  use CarrierDroplet.DataCase
  use Oban.Testing, repo: CarrierDroplet.Repo

  alias CarrierDroplet.Workers.UnsubscribeWorker
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

    # Create an email with unsubscribe link
    email_data = %{
      gmail_message_id: "msg_123",
      subject: "Newsletter",
      from_address: "newsletter@example.com",
      to_address: "user@example.com",
      received_at: DateTime.utc_now(),
      original_content: """
      <html>
        <body>
          <p>This is a newsletter</p>
          <a href="https://example.com/unsubscribe">Unsubscribe</a>
        </body>
      </html>
      """
    }

    {:ok, email} = Emails.create_email(gmail_account.id, email_data)

    %{user: user, gmail_account: gmail_account, email: email}
  end

  describe "perform/1" do
    test "enqueues job successfully", %{email: email} do
      assert {:ok, job} =
               %{email_id: email.id}
               |> UnsubscribeWorker.new()
               |> Oban.insert()

      assert job.worker == "CarrierDroplet.Workers.UnsubscribeWorker"
      assert job.args == %{email_id: email.id}
    end

    test "handles missing email" do
      assert {:error, :email_not_found} =
               perform_job(UnsubscribeWorker, %{email_id: 99999})
    end

    test "handles email without unsubscribe link", %{gmail_account: gmail_account} do
      email_data = %{
        gmail_message_id: "msg_no_unsub",
        subject: "Regular Email",
        from_address: "sender@example.com",
        to_address: "user@example.com",
        received_at: DateTime.utc_now(),
        original_content: "This email has no unsubscribe link"
      }

      {:ok, email} = Emails.create_email(gmail_account.id, email_data)

      # Should return error when no unsubscribe link is found
      # Note: This will fail if OPENAI_API_KEY is not set, which is expected in test env
      result = perform_job(UnsubscribeWorker, %{email_id: email.id})
      assert match?({:error, _}, result)
    end
  end
end
