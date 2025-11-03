defmodule CarrierDropletWeb.DashboardLiveTest do
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

    # Create a primary gmail account
    {:ok, gmail_account} =
      Accounts.get_or_create_gmail_account(user.id, "gmail@example.com", %{
        "access_token" => "token",
        "refresh_token" => "refresh",
        "is_primary" => true
      })

    %{user: user, gmail_account: gmail_account}
  end

  describe "Dashboard" do
    test "displays dashboard with no categories", %{conn: conn, user: user} do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Dashboard"
      assert html =~ "Connected Gmail Accounts"
      assert html =~ "Email Categories"
    end

    test "displays connected gmail accounts", %{
      conn: conn,
      user: user,
      gmail_account: gmail_account
    } do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ gmail_account.email
      assert html =~ "Import Emails"
    end

    test "displays categories", %{conn: conn, user: user} do
      {:ok, _category} = Emails.create_category(user, %{name: "Work", description: "Work emails"})

      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Work"
      assert html =~ "Work emails"
    end

    test "can navigate to create category", %{conn: conn, user: user} do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert view |> element("a", "New Category") |> render_click()
      assert_redirect(view, ~p"/categories/new")
    end

    test "can delete a category", %{conn: conn, user: user} do
      {:ok, category} = Emails.create_category(user, %{name: "Work", description: "Work emails"})

      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#categories-#{category.id}")

      view
      |> element("#categories-#{category.id} button", "Delete")
      |> render_click()

      refute has_element?(view, "#categories-#{category.id}")
    end

    test "redirects to login when not authenticated", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard")
      assert path == "/"
    end
  end

  describe "Disconnect Gmail Account" do
    test "shows disconnect button for gmail accounts", %{conn: conn, user: user} do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Disconnect"
    end

    test "opens disconnect modal when clicking disconnect", %{
      conn: conn,
      user: user,
      gmail_account: gmail_account
    } do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      html =
        view
        |> element(
          "button[phx-click='show_disconnect_modal'][phx-value-account_id='#{gmail_account.id}']"
        )
        |> render_click()

      assert html =~ "Disconnect Gmail Account"
      assert html =~ "Are you sure you want to disconnect"
      assert html =~ gmail_account.email
    end

    test "shows warning for primary account disconnect", %{
      conn: conn,
      user: user,
      gmail_account: gmail_account
    } do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      html =
        view
        |> element(
          "button[phx-click='show_disconnect_modal'][phx-value-account_id='#{gmail_account.id}']"
        )
        |> render_click()

      assert html =~ "primary account"
      assert html =~ "entire account will be deleted"
      assert html =~ "Delete Account"
    end

    test "disconnects non-primary account successfully", %{conn: conn, user: user} do
      # Create a second non-primary account
      {:ok, secondary_account} =
        Accounts.get_or_create_gmail_account(user.id, "secondary@example.com", %{
          "access_token" => "token2",
          "refresh_token" => "refresh2",
          "is_primary" => false
        })

      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Open disconnect modal
      view
      |> element(
        "button[phx-click='show_disconnect_modal'][phx-value-account_id='#{secondary_account.id}']"
      )
      |> render_click()

      # Confirm disconnect
      view
      |> element("button[phx-click='confirm_disconnect']")
      |> render_click()

      # Account should be deleted
      assert Accounts.get_gmail_account(secondary_account.id) == nil

      # User should still exist
      assert Accounts.get_user(user.id) != nil
    end

    test "deletes user when disconnecting primary account", %{
      conn: conn,
      user: user,
      gmail_account: gmail_account
    } do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Open disconnect modal
      view
      |> element(
        "button[phx-click='show_disconnect_modal'][phx-value-account_id='#{gmail_account.id}']"
      )
      |> render_click()

      # Confirm disconnect
      view
      |> element("button[phx-click='confirm_disconnect']")
      |> render_click()

      # Should redirect to home page
      assert_redirect(view, ~p"/")

      # User should be deleted
      assert Accounts.get_user(user.id) == nil
    end

    test "closes modal when clicking cancel", %{
      conn: conn,
      user: user,
      gmail_account: gmail_account
    } do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Open disconnect modal
      html =
        view
        |> element(
          "button[phx-click='show_disconnect_modal'][phx-value-account_id='#{gmail_account.id}']"
        )
        |> render_click()

      assert html =~ "Disconnect Gmail Account"

      # Close modal
      html =
        view
        |> element("button[phx-click='close_disconnect_modal']")
        |> render_click()

      refute html =~ "Disconnect Gmail Account"
    end
  end

  describe "Import Emails" do
    test "enqueues email import job when clicking import", %{
      conn: conn,
      user: user,
      gmail_account: gmail_account
    } do
      conn = Plug.Test.init_test_session(conn, user_id: user.id)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("button[phx-click='import_emails'][phx-value-account_id='#{gmail_account.id}']")
      |> render_click()

      # Verify job was enqueued
      assert_enqueued(
        worker: CarrierDroplet.Workers.EmailImportWorker,
        args: %{"gmail_account_id" => gmail_account.id, "user_id" => user.id}
      )
    end
  end
end
