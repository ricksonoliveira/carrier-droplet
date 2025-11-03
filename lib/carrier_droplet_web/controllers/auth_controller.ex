defmodule CarrierDropletWeb.AuthController do
  use CarrierDropletWeb, :controller

  alias CarrierDroplet.Accounts

  # Store linking token in session BEFORE Ueberauth processes the request
  plug :store_linking_token when action in [:request]
  plug Ueberauth

  defp store_linking_token(conn, _opts) do
    if conn.params["linking_token"] do
      put_session(conn, :linking_token, conn.params["linking_token"])
    else
      conn
    end
  end

  def request(conn, _params) do
    # Ueberauth will handle the redirect
    conn
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate with Google.")
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    # Check if there's an OAuth linking token (for adding accounts)
    # First check the session (set in request/2)
    linking_token = get_session(conn, :linking_token)

    current_user =
      linking_token && Accounts.get_user_by_oauth_linking_token(linking_token)

    if current_user do
      # User is already logged in, just add the Gmail account
      gmail_account_params = %{
        "email" => auth.info.email,
        "access_token" => auth.credentials.token,
        "refresh_token" => auth.credentials.refresh_token,
        "token_expires_at" => expires_at(auth.credentials.expires_at),
        "is_primary" => false
      }

      case Accounts.get_or_create_gmail_account(
             current_user.id,
             auth.info.email,
             gmail_account_params
           ) do
        {:ok, _gmail_account} ->
          Accounts.delete_oauth_linking_token(linking_token)

          conn
          |> delete_session(:linking_token)
          |> put_flash(:info, "Gmail account #{auth.info.email} added successfully!")
          |> redirect(to: ~p"/dashboard")

        {:error, _changeset} ->
          Accounts.delete_oauth_linking_token(linking_token)

          conn
          |> delete_session(:linking_token)
          |> put_flash(:error, "Failed to add Gmail account.")
          |> redirect(to: ~p"/dashboard")
      end
    else
      # This is a primary login - create/update user and primary gmail account
      user_params = %{
        "email" => auth.info.email,
        "google_id" => auth.uid,
        "access_token" => auth.credentials.token,
        "refresh_token" => auth.credentials.refresh_token,
        "token_expires_at" => expires_at(auth.credentials.expires_at)
      }

      case Accounts.upsert_user_from_oauth(user_params) do
        {:ok, user} ->
          # Create primary gmail account
          gmail_account_params = %{
            "email" => auth.info.email,
            "access_token" => auth.credentials.token,
            "refresh_token" => auth.credentials.refresh_token,
            "token_expires_at" => expires_at(auth.credentials.expires_at),
            "is_primary" => true
          }

          Accounts.get_or_create_gmail_account(user.id, auth.info.email, gmail_account_params)

          conn
          |> put_session(:user_id, user.id)
          |> put_flash(:info, "Successfully authenticated!")
          |> redirect(to: ~p"/dashboard")

        {:error, _changeset} ->
          conn
          |> put_flash(:error, "Failed to create user account.")
          |> redirect(to: ~p"/")
      end
    end
  end

  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: ~p"/")
  end

  defp expires_at(nil), do: nil

  defp expires_at(expires_at) when is_integer(expires_at) do
    DateTime.from_unix!(expires_at)
  end

  defp expires_at(_), do: nil
end
