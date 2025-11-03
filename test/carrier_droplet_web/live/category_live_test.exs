defmodule CarrierDropletWeb.CategoryLiveTest do
  use CarrierDropletWeb.ConnCase
  use Oban.Testing, repo: CarrierDroplet.Repo

  import Phoenix.LiveViewTest

  alias CarrierDroplet.Accounts
  alias CarrierDroplet.Emails

  setup do
    # Create a user
    oauth_data = %{
      "email" => "user@example.com",
      "google_id" => "google_123",
      "access_token" => "token_123",
      "refresh_token" => "refresh_123",
      "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
    }

    {:ok, user} = Accounts.upsert_user_from_oauth(oauth_data)

    # Create a gmail account
    {:ok, gmail_account} =
      Accounts.get_or_create_gmail_account(user.id, "gmail@example.com", %{
        "access_token" => "token",
        "refresh_token" => "refresh"
      })

    %{user: user, gmail_account: gmail_account}
  end

  describe "New Category" do
    test "displays new category form", %{conn: conn, user: user} do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, _view, html} = live(conn, ~p"/categories/new")

      assert html =~ "Create Category"
      assert html =~ "Name"
      assert html =~ "Description"
    end

    test "creates category with valid data", %{conn: conn, user: user} do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/categories/new")

      view
      |> form("#category-form", category: %{name: "Work", description: "Work emails"})
      |> render_submit()

      assert_redirect(view, ~p"/dashboard")

      # Verify category was created
      categories = Emails.list_categories(user.id)
      assert length(categories) == 1
      assert hd(categories).name == "Work"
    end

    test "shows validation errors with invalid data", %{conn: conn, user: user} do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/categories/new")

      html =
        view
        |> form("#category-form", category: %{name: "", description: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "redirects to login when not authenticated", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/categories/new")
      assert path == "/"
    end
  end

  describe "Edit Category" do
    setup %{user: user} do
      {:ok, category} = Emails.create_category(user, %{name: "Work", description: "Work emails"})
      %{category: category}
    end

    test "displays edit category form", %{conn: conn, user: user, category: category} do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, _view, html} = live(conn, ~p"/categories/#{category.id}/edit")

      assert html =~ "Edit Category"
      assert html =~ "Work"
      assert html =~ "Work emails"
    end

    test "updates category with valid data", %{conn: conn, user: user, category: category} do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}/edit")

      view
      |> form("#category-form", category: %{description: "Updated description"})
      |> render_submit()

      assert_redirect(view, ~p"/dashboard")

      # Verify category was updated
      updated = Emails.get_category!(category.id)
      assert updated.description == "Updated description"
    end

    test "shows validation errors with invalid data", %{
      conn: conn,
      user: user,
      category: category
    } do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}/edit")

      html =
        view
        |> form("#category-form", category: %{name: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end
  end

  describe "Show Category" do
    setup %{user: user, gmail_account: gmail_account} do
      {:ok, category} = Emails.create_category(user, %{name: "Work", description: "Work emails"})

      # Create some emails
      {:ok, email1} =
        Emails.create_email(gmail_account.id, %{
          gmail_message_id: "msg_1",
          subject: "Email 1",
          from_address: "sender@example.com",
          to_address: "recipient@example.com",
          received_at: DateTime.utc_now(),
          original_content: "Body 1"
        })

      {:ok, email2} =
        Emails.create_email(gmail_account.id, %{
          gmail_message_id: "msg_2",
          subject: "Email 2",
          from_address: "sender@example.com",
          to_address: "recipient@example.com",
          received_at: DateTime.utc_now(),
          original_content: "Body 2"
        })

      # Assign to category
      Emails.update_email(email1, %{category_id: category.id, summary: "Summary 1"})
      Emails.update_email(email2, %{category_id: category.id, summary: "Summary 2"})

      %{category: category, email1: email1, email2: email2}
    end

    test "displays category with emails", %{conn: conn, user: user, category: category} do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, _view, html} = live(conn, ~p"/categories/#{category.id}")

      assert html =~ "Work"
      assert html =~ "Email 1"
      assert html =~ "Email 2"
      assert html =~ "Summary 1"
      assert html =~ "Summary 2"
    end

    test "can select individual emails", %{
      conn: conn,
      user: user,
      category: category,
      email1: email1
    } do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      view
      |> element("input[phx-value-id='#{email1.id}']")
      |> render_click()

      assert has_element?(view, "button", "Delete Selected")
    end

    test "can select all emails", %{conn: conn, user: user, category: category} do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      view
      |> element("button", "Select All")
      |> render_click()

      assert has_element?(view, "button", "Deselect All")
    end

    test "can deselect all emails", %{conn: conn, user: user, category: category, email1: email1} do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      # Select one email first
      view
      |> element("input[phx-value-id='#{email1.id}']")
      |> render_click()

      # Then deselect all
      view
      |> element("button", "Deselect All")
      |> render_click()

      refute has_element?(view, "button", "Delete Selected")
    end

    test "can bulk delete emails", %{
      conn: conn,
      user: user,
      category: category,
      email1: email1,
      email2: email2
    } do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      # Select all emails
      view
      |> element("button", "Select All")
      |> render_click()

      # Delete selected
      view
      |> element("button", "Delete Selected")
      |> render_click()

      # Verify emails were deleted
      assert Emails.get_email(email1.id) == nil
      assert Emails.get_email(email2.id) == nil
    end

    test "displays empty state when no emails", %{conn: conn, user: user} do
      {:ok, empty_category} =
        Emails.create_category(user, %{name: "Empty", description: "No emails"})

      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, _view, html} = live(conn, ~p"/categories/#{empty_category.id}")

      assert html =~ "No emails in this category yet"
    end

    test "can bulk unsubscribe from emails", %{
      conn: conn,
      user: user,
      category: category,
      email1: email1
    } do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      # Select all emails
      view
      |> element("button", "Select All")
      |> render_click()

      # Unsubscribe from selected
      view
      |> element("button", "Unsubscribe Selected")
      |> render_click()

      # Verify unsubscribe jobs were enqueued
      assert_enqueued(
        worker: CarrierDroplet.Workers.UnsubscribeWorker,
        args: %{"email_id" => email1.id}
      )
    end

    test "opens email view modal when clicking on email", %{
      conn: conn,
      user: user,
      category: category,
      email1: email1
    } do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      html =
        view
        |> element("div[phx-click='view_email'][phx-value-id='#{email1.id}']")
        |> render_click()

      assert html =~ email1.subject
      assert html =~ email1.from_address
      assert html =~ "Body 1"
    end

    test "closes email view modal when clicking close", %{
      conn: conn,
      user: user,
      category: category,
      email1: email1
    } do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      # Open modal
      view
      |> element("div[phx-click='view_email'][phx-value-id='#{email1.id}']")
      |> render_click()

      # Close modal
      html =
        view
        |> element("button[phx-click='close_email']")
        |> render_click()

      refute html =~ "Body 1"
    end

    test "can unsubscribe from single email in modal", %{
      conn: conn,
      user: user,
      category: category,
      email1: email1
    } do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      # Open modal
      view
      |> element("div[phx-click='view_email'][phx-value-id='#{email1.id}']")
      |> render_click()

      # Click unsubscribe
      view
      |> element("button[phx-click='unsubscribe_single']")
      |> render_click()

      # Verify unsubscribe job was enqueued
      assert_enqueued(
        worker: CarrierDroplet.Workers.UnsubscribeWorker,
        args: %{"email_id" => email1.id}
      )
    end

    test "can delete single email from modal", %{
      conn: conn,
      user: user,
      category: category,
      email1: email1
    } do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      # Open modal
      view
      |> element("div[phx-click='view_email'][phx-value-id='#{email1.id}']")
      |> render_click()

      # Click delete
      view
      |> element("button[phx-click='delete_single']")
      |> render_click()

      # Verify email was deleted
      assert Emails.get_email(email1.id) == nil
    end
  end
end
