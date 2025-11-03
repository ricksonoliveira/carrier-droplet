defmodule CarrierDroplet.AccountsTest do
  use CarrierDroplet.DataCase

  alias CarrierDroplet.Accounts

  describe "upsert_user_from_oauth/1" do
    test "creates a new user from OAuth data" do
      oauth_data = %{
        "email" => "test@example.com",
        "google_id" => "google_123",
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      assert {:ok, user} = Accounts.upsert_user_from_oauth(oauth_data)
      assert user.email == "test@example.com"
      assert user.google_id == "google_123"
      assert user.access_token == "access_token_123"
      assert user.refresh_token == "refresh_token_123"
    end

    test "updates existing user from OAuth data" do
      oauth_data = %{
        "email" => "test@example.com",
        "google_id" => "google_123",
        "access_token" => "old_token",
        "refresh_token" => "old_refresh",
        "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      {:ok, user1} = Accounts.upsert_user_from_oauth(oauth_data)

      # Update with new tokens
      new_oauth_data = %{
        "email" => "test@example.com",
        "google_id" => "google_123",
        "access_token" => "new_token",
        "refresh_token" => "new_refresh",
        "token_expires_at" => DateTime.utc_now() |> DateTime.add(7200, :second)
      }

      {:ok, user2} = Accounts.upsert_user_from_oauth(new_oauth_data)

      assert user1.id == user2.id
      assert user2.access_token == "new_token"
      assert user2.refresh_token == "new_refresh"
    end
  end

  describe "get_or_create_gmail_account/3" do
    setup do
      oauth_data = %{
        "email" => "user@example.com",
        "google_id" => "google_456",
        "access_token" => "token_456",
        "refresh_token" => "refresh_456",
        "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      {:ok, user} = Accounts.upsert_user_from_oauth(oauth_data)
      %{user: user}
    end

    test "creates a new gmail account for user", %{user: user} do
      {:ok, account} =
        Accounts.get_or_create_gmail_account(user.id, "gmail@example.com", %{
          "access_token" => "access_token_789",
          "refresh_token" => "refresh_token_789"
        })

      assert account.user_id == user.id
      assert account.email == "gmail@example.com"
      assert account.access_token == "access_token_789"
      assert account.is_primary == false
    end

    test "returns existing gmail account if already exists", %{user: user} do
      {:ok, account1} =
        Accounts.get_or_create_gmail_account(user.id, "gmail@example.com", %{
          "access_token" => "token1",
          "refresh_token" => "refresh1"
        })

      {:ok, account2} =
        Accounts.get_or_create_gmail_account(user.id, "gmail@example.com", %{
          "access_token" => "token2",
          "refresh_token" => "refresh2"
        })

      assert account1.id == account2.id
      # Should update tokens
      assert account2.access_token == "token2"
      assert account2.refresh_token == "refresh2"
    end

    test "creates multiple gmail accounts for same user", %{user: user} do
      {:ok, account1} =
        Accounts.get_or_create_gmail_account(user.id, "gmail1@example.com", %{
          "access_token" => "token1",
          "refresh_token" => "refresh1"
        })

      {:ok, account2} =
        Accounts.get_or_create_gmail_account(user.id, "gmail2@example.com", %{
          "access_token" => "token2",
          "refresh_token" => "refresh2"
        })

      assert account1.id != account2.id
      assert account1.email == "gmail1@example.com"
      assert account2.email == "gmail2@example.com"
    end
  end

  describe "list_gmail_accounts/1" do
    setup do
      oauth_data = %{
        "email" => "user@example.com",
        "google_id" => "google_789",
        "access_token" => "token_789",
        "refresh_token" => "refresh_789",
        "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      {:ok, user} = Accounts.upsert_user_from_oauth(oauth_data)
      %{user: user}
    end

    test "returns empty list when user has no gmail accounts", %{user: user} do
      accounts = Accounts.list_gmail_accounts(user.id)
      assert accounts == []
    end

    test "returns all gmail accounts for user", %{user: user} do
      {:ok, _account1} =
        Accounts.get_or_create_gmail_account(user.id, "gmail1@example.com", %{
          "access_token" => "token1",
          "refresh_token" => "refresh1"
        })

      {:ok, _account2} =
        Accounts.get_or_create_gmail_account(user.id, "gmail2@example.com", %{
          "access_token" => "token2",
          "refresh_token" => "refresh2"
        })

      accounts = Accounts.list_gmail_accounts(user.id)
      assert length(accounts) == 2
      emails = Enum.map(accounts, & &1.email)
      assert "gmail1@example.com" in emails
      assert "gmail2@example.com" in emails
    end
  end

  describe "get_gmail_account!/1" do
    setup do
      oauth_data = %{
        "email" => "user@example.com",
        "google_id" => "google_999",
        "access_token" => "token_999",
        "refresh_token" => "refresh_999",
        "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      {:ok, user} = Accounts.upsert_user_from_oauth(oauth_data)

      {:ok, account} =
        Accounts.get_or_create_gmail_account(user.id, "gmail@example.com", %{
          "access_token" => "token",
          "refresh_token" => "refresh"
        })

      %{user: user, account: account}
    end

    test "returns gmail account by id", %{account: account} do
      fetched_account = Accounts.get_gmail_account!(account.id)
      assert fetched_account.id == account.id
      assert fetched_account.email == account.email
    end

    test "raises when account doesn't exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_gmail_account!(999_999)
      end
    end
  end

  describe "delete_gmail_account/1" do
    setup do
      oauth_data = %{
        "email" => "user@example.com",
        "google_id" => "google_delete_1",
        "access_token" => "token",
        "refresh_token" => "refresh",
        "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      {:ok, user} = Accounts.upsert_user_from_oauth(oauth_data)

      {:ok, account} =
        Accounts.get_or_create_gmail_account(user.id, "gmail@example.com", %{
          "access_token" => "token",
          "refresh_token" => "refresh"
        })

      %{user: user, account: account}
    end

    test "deletes gmail account successfully", %{account: account} do
      assert {:ok, deleted_account} = Accounts.delete_gmail_account(account)
      assert deleted_account.id == account.id
      assert Accounts.get_gmail_account(account.id) == nil
    end

    test "deleting gmail account cascades to emails", %{account: account} do
      # Create an email for this account
      alias CarrierDroplet.Emails

      email_data = %{
        gmail_message_id: "msg_123",
        subject: "Test",
        from_address: "sender@example.com",
        to_address: "user@example.com",
        received_at: DateTime.utc_now(),
        original_content: "Content"
      }

      {:ok, email} = Emails.create_email(account.id, email_data)

      # Delete the account
      {:ok, _} = Accounts.delete_gmail_account(account)

      # Email should be deleted too (cascade)
      assert Emails.get_email(email.id) == nil
    end
  end

  describe "delete_user/1" do
    setup do
      oauth_data = %{
        "email" => "user@example.com",
        "google_id" => "google_delete_2",
        "access_token" => "token",
        "refresh_token" => "refresh",
        "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      {:ok, user} = Accounts.upsert_user_from_oauth(oauth_data)

      {:ok, account} =
        Accounts.get_or_create_gmail_account(user.id, "gmail@example.com", %{
          "access_token" => "token",
          "refresh_token" => "refresh"
        })

      %{user: user, account: account}
    end

    test "deletes user successfully", %{user: user} do
      assert {:ok, deleted_user} = Accounts.delete_user(user)
      assert deleted_user.id == user.id
      assert Accounts.get_user(user.id) == nil
    end

    test "deleting user cascades to gmail accounts", %{user: user, account: account} do
      {:ok, _} = Accounts.delete_user(user)

      # Gmail account should be deleted too (cascade)
      assert Accounts.get_gmail_account(account.id) == nil
    end

    test "deleting user cascades to categories", %{user: user} do
      alias CarrierDroplet.Emails

      {:ok, category} =
        Emails.create_category(user, %{name: "Work", description: "Work emails"})

      {:ok, _} = Accounts.delete_user(user)

      # Category should be deleted too (cascade)
      assert_raise Ecto.NoResultsError, fn ->
        Emails.get_category!(category.id)
      end
    end
  end

  describe "count_gmail_accounts/1" do
    setup do
      oauth_data = %{
        "email" => "user@example.com",
        "google_id" => "google_count",
        "access_token" => "token",
        "refresh_token" => "refresh",
        "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      {:ok, user} = Accounts.upsert_user_from_oauth(oauth_data)
      %{user: user}
    end

    test "returns 0 when user has no gmail accounts", %{user: user} do
      assert Accounts.count_gmail_accounts(user.id) == 0
    end

    test "returns correct count of gmail accounts", %{user: user} do
      {:ok, _account1} =
        Accounts.get_or_create_gmail_account(user.id, "gmail1@example.com", %{
          "access_token" => "token1",
          "refresh_token" => "refresh1"
        })

      assert Accounts.count_gmail_accounts(user.id) == 1

      {:ok, _account2} =
        Accounts.get_or_create_gmail_account(user.id, "gmail2@example.com", %{
          "access_token" => "token2",
          "refresh_token" => "refresh2"
        })

      assert Accounts.count_gmail_accounts(user.id) == 2
    end
  end

  describe "refresh_gmail_account_token/1" do
    setup do
      oauth_data = %{
        "email" => "user@example.com",
        "google_id" => "google_refresh",
        "access_token" => "token",
        "refresh_token" => "refresh",
        "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      {:ok, user} = Accounts.upsert_user_from_oauth(oauth_data)

      {:ok, account} =
        Accounts.get_or_create_gmail_account(user.id, "gmail@example.com", %{
          "access_token" => "old_token",
          "refresh_token" => "valid_refresh_token",
          "token_expires_at" => DateTime.utc_now() |> DateTime.add(-100, :second)
        })

      %{user: user, account: account}
    end

    test "handles token refresh failure gracefully", %{account: account} do
      # This will fail because we don't have a real Google OAuth server
      # but we can verify the error handling
      result = Accounts.refresh_gmail_account_token(account)
      assert match?({:error, _}, result)
    end
  end
end
