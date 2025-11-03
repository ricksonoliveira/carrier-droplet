defmodule CarrierDroplet.Workers.ScheduledEmailImportWorkerTest do
  use CarrierDroplet.DataCase
  use Oban.Testing, repo: CarrierDroplet.Repo

  alias CarrierDroplet.Workers.{ScheduledEmailImportWorker, EmailImportWorker}
  alias CarrierDroplet.Accounts

  setup do
    # Create users and gmail accounts for testing
    oauth_data1 = %{
      "email" => "user1@example.com",
      "google_id" => "google_123",
      "access_token" => "token_123",
      "refresh_token" => "refresh_123",
      "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
    }

    {:ok, user1} = Accounts.upsert_user_from_oauth(oauth_data1)

    {:ok, gmail_account1} =
      Accounts.get_or_create_gmail_account(user1.id, "gmail1@example.com", %{
        "access_token" => "token",
        "refresh_token" => "refresh"
      })

    oauth_data2 = %{
      "email" => "user2@example.com",
      "google_id" => "google_456",
      "access_token" => "token_456",
      "refresh_token" => "refresh_456",
      "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
    }

    {:ok, user2} = Accounts.upsert_user_from_oauth(oauth_data2)

    {:ok, gmail_account2} =
      Accounts.get_or_create_gmail_account(user2.id, "gmail2@example.com", %{
        "access_token" => "token",
        "refresh_token" => "refresh"
      })

    %{
      user1: user1,
      gmail_account1: gmail_account1,
      user2: user2,
      gmail_account2: gmail_account2
    }
  end

  describe "perform/1" do
    test "enqueues import jobs for all gmail accounts", %{
      user1: user1,
      gmail_account1: gmail_account1,
      user2: user2,
      gmail_account2: gmail_account2
    } do
      # Perform the scheduled import job
      assert :ok = perform_job(ScheduledEmailImportWorker, %{})

      # Verify that import jobs were enqueued for both accounts
      assert_enqueued(
        worker: EmailImportWorker,
        args: %{"gmail_account_id" => gmail_account1.id, "user_id" => user1.id}
      )

      assert_enqueued(
        worker: EmailImportWorker,
        args: %{"gmail_account_id" => gmail_account2.id, "user_id" => user2.id}
      )

      # Should have 2 jobs enqueued
      assert length(all_enqueued(worker: EmailImportWorker)) == 2
    end

    test "handles no gmail accounts gracefully" do
      # Delete all gmail accounts
      CarrierDroplet.Repo.delete_all(CarrierDroplet.Accounts.GmailAccount)

      # Should complete successfully even with no accounts
      assert :ok = perform_job(ScheduledEmailImportWorker, %{})

      # No jobs should be enqueued
      assert length(all_enqueued(worker: EmailImportWorker)) == 0
    end
  end
end
