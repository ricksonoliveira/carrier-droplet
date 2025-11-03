defmodule CarrierDroplet.Workers.RecategorizeEmailsWorkerTest do
  use CarrierDroplet.DataCase
  use Oban.Testing, repo: CarrierDroplet.Repo

  alias CarrierDroplet.Workers.{RecategorizeEmailsWorker, EmailCategorizationWorker}
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

    %{user: user, gmail_account: gmail_account}
  end

  describe "perform/1" do
    test "enqueues categorization jobs for uncategorized emails", %{
      user: user,
      gmail_account: gmail_account
    } do
      # Create some uncategorized emails
      for i <- 1..3 do
        email_data = %{
          gmail_message_id: "msg_#{i}",
          subject: "Email #{i}",
          from_address: "sender#{i}@example.com",
          to_address: "user@example.com",
          received_at: DateTime.utc_now(),
          original_content: "Content #{i}"
        }

        {:ok, _email} = Emails.create_email(gmail_account.id, email_data)
      end

      # Perform the recategorization job
      assert {:ok, %{count: 3}} =
               perform_job(RecategorizeEmailsWorker, %{user_id: user.id})

      # Verify that categorization jobs were enqueued
      assert length(all_enqueued(worker: EmailCategorizationWorker)) == 3
    end

    test "does not enqueue jobs for already categorized emails", %{
      user: user,
      gmail_account: gmail_account
    } do
      # Create a category
      {:ok, category} =
        Emails.create_category(user, %{
          name: "Work",
          description: "Work emails"
        })

      # Create categorized email
      email_data = %{
        gmail_message_id: "msg_categorized",
        subject: "Categorized Email",
        from_address: "sender@example.com",
        to_address: "user@example.com",
        received_at: DateTime.utc_now(),
        original_content: "Content",
        category_id: category.id
      }

      {:ok, _email} = Emails.create_email(gmail_account.id, email_data)

      # Create uncategorized email
      email_data2 = %{
        gmail_message_id: "msg_uncategorized",
        subject: "Uncategorized Email",
        from_address: "sender2@example.com",
        to_address: "user@example.com",
        received_at: DateTime.utc_now(),
        original_content: "Content 2"
      }

      {:ok, _email2} = Emails.create_email(gmail_account.id, email_data2)

      # Perform the recategorization job
      assert {:ok, %{count: 1}} =
               perform_job(RecategorizeEmailsWorker, %{user_id: user.id})

      # Only 1 job should be enqueued (for the uncategorized email)
      assert length(all_enqueued(worker: EmailCategorizationWorker)) == 1
    end

    test "handles user with no emails", %{user: user} do
      assert {:ok, %{count: 0}} =
               perform_job(RecategorizeEmailsWorker, %{user_id: user.id})

      # No jobs should be enqueued
      assert length(all_enqueued(worker: EmailCategorizationWorker)) == 0
    end
  end
end
