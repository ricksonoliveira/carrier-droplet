defmodule CarrierDropletWeb.AuthControllerTest do
  use CarrierDropletWeb.ConnCase

  alias CarrierDroplet.Accounts

  # Note: Full OAuth flow testing is done in integration tests
  # These tests focus on the controller logic after Ueberauth processes the request

  describe "request/2" do
    test "initiates OAuth request", %{conn: conn} do
      # Just verify the route exists and doesn't error
      conn = get(conn, ~p"/auth/google")
      # Ueberauth will handle the redirect, so we just check it doesn't crash
      assert conn.status in [200, 302]
    end
  end

  describe "callback/2 - authentication failure" do
    test "handles Ueberauth failure", %{conn: conn} do
      failure = %Ueberauth.Failure{
        errors: [%Ueberauth.Failure.Error{message: "OAuth failed"}]
      }

      conn =
        conn
        |> bypass_through(CarrierDropletWeb.Router, [:browser])
        |> get("/")
        |> assign(:ueberauth_failure, failure)
        |> CarrierDropletWeb.AuthController.callback(%{})

      # Should redirect to home with error
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Failed to authenticate with Google."
    end
  end

  # Note: Full OAuth callback flow is tested in integration tests
  # Controller unit tests are limited because Ueberauth plug modifies the conn
  # before the controller action runs, making it difficult to test in isolation

  describe "logout/2" do
    test "logs out user and redirects to home", %{conn: conn} do
      # Create a user and set session
      {:ok, user} =
        Accounts.upsert_user_from_oauth(%{
          "email" => "user@example.com",
          "google_id" => "google_123",
          "access_token" => "token",
          "refresh_token" => "refresh",
          "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
        })

      conn =
        conn
        |> init_test_session(%{user_id: user.id})
        |> get(~p"/auth/logout")

      # Should redirect to home
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "You have been logged out."
    end

    test "handles logout when not logged in", %{conn: conn} do
      conn = get(conn, ~p"/auth/logout")

      # Should still redirect to home
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "You have been logged out."
    end
  end
end
