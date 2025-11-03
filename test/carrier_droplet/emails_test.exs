defmodule CarrierDroplet.EmailsTest do
  use CarrierDroplet.DataCase

  alias CarrierDroplet.Emails
  alias CarrierDroplet.Accounts

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

  describe "categories" do
    test "list_categories/1 returns all categories for user", %{user: user} do
      {:ok, _cat1} = Emails.create_category(user, %{name: "Work", description: "Work emails"})

      {:ok, _cat2} =
        Emails.create_category(user, %{name: "Personal", description: "Personal emails"})

      categories = Emails.list_categories(user.id)
      assert length(categories) == 2
      names = Enum.map(categories, & &1.name)
      assert "Work" in names
      assert "Personal" in names
    end

    test "create_category/2 creates a category with valid data", %{user: user} do
      attrs = %{name: "Newsletter", description: "Marketing newsletters"}
      {:ok, category} = Emails.create_category(user, attrs)

      assert category.name == "Newsletter"
      assert category.description == "Marketing newsletters"
      assert category.user_id == user.id
    end

    test "create_category/2 returns error with invalid data", %{user: user} do
      attrs = %{name: "", description: ""}
      {:error, changeset} = Emails.create_category(user, attrs)

      assert changeset.errors[:name]
    end

    test "create_category/2 enforces unique name per user", %{user: user} do
      attrs = %{name: "Work", description: "Work emails"}
      {:ok, _category} = Emails.create_category(user, attrs)

      # Try to create another category with same name
      {:error, changeset} = Emails.create_category(user, attrs)
      assert changeset.errors[:user_id]
    end

    test "update_category/2 updates category with valid data", %{user: user} do
      {:ok, category} = Emails.create_category(user, %{name: "Work", description: "Work emails"})

      {:ok, updated} = Emails.update_category(category, %{description: "Updated description"})
      assert updated.description == "Updated description"
      assert updated.name == "Work"
    end

    test "delete_category/1 deletes the category", %{user: user} do
      {:ok, category} = Emails.create_category(user, %{name: "Work", description: "Work emails"})

      {:ok, _deleted} = Emails.delete_category(category)

      assert_raise Ecto.NoResultsError, fn ->
        Emails.get_category!(category.id)
      end
    end

    test "get_category!/1 returns category by id", %{user: user} do
      {:ok, category} = Emails.create_category(user, %{name: "Work", description: "Work emails"})

      fetched = Emails.get_category!(category.id)
      assert fetched.id == category.id
      assert fetched.name == "Work"
    end
  end

  describe "emails" do
    setup %{user: user, gmail_account: gmail_account} do
      {:ok, category} = Emails.create_category(user, %{name: "Work", description: "Work emails"})
      %{category: category, gmail_account: gmail_account}
    end

    test "create_email/2 creates an email with valid data", %{gmail_account: gmail_account} do
      email_data = %{
        gmail_message_id: "msg_123",
        subject: "Test Email",
        from_address: "sender@example.com",
        to_address: "recipient@example.com",
        received_at: DateTime.utc_now(),
        original_content: "This is the email body"
      }

      {:ok, email} = Emails.create_email(gmail_account.id, email_data)

      assert email.gmail_message_id == "msg_123"
      assert email.subject == "Test Email"
      assert email.from_address == "sender@example.com"
      assert email.original_content == "This is the email body"
      assert email.gmail_account_id == gmail_account.id
    end

    test "get_email_by_gmail_message_id/2 returns email if exists", %{
      gmail_account: gmail_account
    } do
      email_data = %{
        gmail_message_id: "msg_456",
        subject: "Test",
        from_address: "sender@example.com",
        to_address: "recipient@example.com",
        received_at: DateTime.utc_now(),
        original_content: "Body"
      }

      {:ok, email} = Emails.create_email(gmail_account.id, email_data)

      found = Emails.get_email_by_gmail_message_id(gmail_account.id, "msg_456")
      assert found.id == email.id
    end

    test "get_email_by_gmail_message_id/2 returns nil if not exists", %{
      gmail_account: gmail_account
    } do
      found = Emails.get_email_by_gmail_message_id(gmail_account.id, "nonexistent")
      assert found == nil
    end

    test "list_emails_by_category/1 returns emails in category", %{
      gmail_account: gmail_account,
      category: category
    } do
      email_data1 = %{
        gmail_message_id: "msg_1",
        subject: "Email 1",
        from_address: "sender@example.com",
        to_address: "recipient@example.com",
        received_at: DateTime.utc_now(),
        original_content: "Body 1"
      }

      email_data2 = %{
        gmail_message_id: "msg_2",
        subject: "Email 2",
        from_address: "sender@example.com",
        to_address: "recipient@example.com",
        received_at: DateTime.utc_now(),
        original_content: "Body 2"
      }

      {:ok, email1} = Emails.create_email(gmail_account.id, email_data1)
      {:ok, email2} = Emails.create_email(gmail_account.id, email_data2)

      # Assign to category
      Emails.update_email(email1, %{category_id: category.id})
      Emails.update_email(email2, %{category_id: category.id})

      emails = Emails.list_emails_by_category(category.id)
      assert length(emails) == 2
    end

    test "update_email/2 updates email with summary and category", %{
      gmail_account: gmail_account,
      category: category
    } do
      email_data = %{
        gmail_message_id: "msg_789",
        subject: "Test",
        from_address: "sender@example.com",
        to_address: "recipient@example.com",
        received_at: DateTime.utc_now(),
        original_content: "Body"
      }

      {:ok, email} = Emails.create_email(gmail_account.id, email_data)

      {:ok, updated} =
        Emails.update_email(email, %{
          summary: "AI generated summary",
          category_id: category.id
        })

      assert updated.summary == "AI generated summary"
      assert updated.category_id == category.id
    end

    test "delete_emails/1 deletes multiple emails", %{gmail_account: gmail_account} do
      {:ok, email1} =
        Emails.create_email(gmail_account.id, %{
          gmail_message_id: "msg_del_1",
          subject: "Delete 1",
          from_address: "sender@example.com",
          to_address: "recipient@example.com",
          received_at: DateTime.utc_now(),
          original_content: "Body"
        })

      {:ok, email2} =
        Emails.create_email(gmail_account.id, %{
          gmail_message_id: "msg_del_2",
          subject: "Delete 2",
          from_address: "sender@example.com",
          to_address: "recipient@example.com",
          received_at: DateTime.utc_now(),
          original_content: "Body"
        })

      {count, _} = Emails.delete_emails([email1.id, email2.id])
      assert count == 2

      assert Emails.get_email(email1.id) == nil
      assert Emails.get_email(email2.id) == nil
    end
  end
end
