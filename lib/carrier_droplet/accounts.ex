defmodule CarrierDroplet.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias CarrierDroplet.Repo
  alias CarrierDroplet.Accounts.{User, GmailAccount, OAuthLinkingToken}

  @doc """
  Gets a single user by id.
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Gets a single user by email.
  """
  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a single user by google_id.
  """
  def get_user_by_google_id(google_id) do
    Repo.get_by(User, google_id: google_id)
  end

  @doc """
  Creates or updates a user from OAuth data.
  """
  def upsert_user_from_oauth(attrs) do
    case get_user_by_google_id(attrs["google_id"]) do
      nil ->
        %User{}
        |> User.changeset(attrs)
        |> Repo.insert()

      user ->
        user
        |> User.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Lists all gmail accounts across all users.
  """
  def list_all_gmail_accounts do
    Repo.all(GmailAccount)
  end

  @doc """
  Lists all gmail accounts for a user.
  """
  def list_gmail_accounts(user_id) do
    GmailAccount
    |> where([g], g.user_id == ^user_id)
    |> order_by([g], desc: g.is_primary, asc: g.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single gmail account.
  """
  def get_gmail_account(id), do: Repo.get(GmailAccount, id)

  @doc """
  Gets a single gmail account, raises if not found.
  """
  def get_gmail_account!(id), do: Repo.get!(GmailAccount, id)

  @doc """
  Creates a gmail account.
  """
  def create_gmail_account(user_id, attrs) do
    %GmailAccount{user_id: user_id}
    |> GmailAccount.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a gmail account.
  """
  def update_gmail_account(%GmailAccount{} = gmail_account, attrs) do
    gmail_account
    |> GmailAccount.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Refreshes the access token for a Gmail account.
  """
  def refresh_gmail_account_token(%GmailAccount{} = gmail_account) do
    case CarrierDroplet.Gmail.Client.refresh_access_token(gmail_account.refresh_token) do
      {:ok, %{"access_token" => access_token, "expires_in" => expires_in}} ->
        expires_at = DateTime.utc_now() |> DateTime.add(expires_in, :second)

        update_gmail_account(gmail_account, %{
          "access_token" => access_token,
          "token_expires_at" => expires_at
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a Gmail account with a valid access token (refreshes if needed).
  """
  def get_gmail_account_with_valid_token(gmail_account_id) do
    case get_gmail_account(gmail_account_id) do
      nil ->
        {:error, :gmail_account_not_found}

      gmail_account ->
        if token_expired?(gmail_account) do
          case refresh_gmail_account_token(gmail_account) do
            {:ok, updated_account} -> {:ok, updated_account}
            {:error, reason} -> {:error, reason}
          end
        else
          {:ok, gmail_account}
        end
    end
  end

  defp token_expired?(%GmailAccount{token_expires_at: nil}), do: true

  defp token_expired?(%GmailAccount{token_expires_at: expires_at}) do
    # Consider token expired if it expires in less than 5 minutes
    buffer_time = DateTime.utc_now() |> DateTime.add(5 * 60, :second)
    DateTime.compare(expires_at, buffer_time) == :lt
  end

  @doc """
  Deletes a gmail account.
  """
  def delete_gmail_account(%GmailAccount{} = gmail_account) do
    Repo.delete(gmail_account)
  end

  @doc """
  Deletes a user and all associated data.
  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Counts the number of gmail accounts for a user.
  """
  def count_gmail_accounts(user_id) do
    GmailAccount
    |> where([g], g.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets or creates a gmail account for a user.
  """
  def get_or_create_gmail_account(user_id, email, attrs) do
    case Repo.get_by(GmailAccount, user_id: user_id, email: email) do
      nil ->
        create_gmail_account(user_id, Map.put(attrs, "email", email))

      gmail_account ->
        update_gmail_account(gmail_account, attrs)
    end
  end

  @doc """
  Creates an OAuth linking token for a user.
  """
  def create_oauth_linking_token(user_id) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    # 15 minutes
    expires_at = DateTime.utc_now() |> DateTime.add(15 * 60, :second)

    %OAuthLinkingToken{user_id: user_id}
    |> OAuthLinkingToken.changeset(%{
      "token" => token,
      "expires_at" => expires_at
    })
    |> Repo.insert()
  end

  @doc """
  Gets a user by OAuth linking token.
  """
  def get_user_by_oauth_linking_token(token) do
    case Repo.get_by(OAuthLinkingToken, token: token) do
      nil ->
        nil

      linking_token ->
        # Check if token is expired
        if DateTime.compare(linking_token.expires_at, DateTime.utc_now()) == :lt do
          nil
        else
          get_user(linking_token.user_id)
        end
    end
  end

  @doc """
  Deletes an OAuth linking token.
  """
  def delete_oauth_linking_token(token) do
    case Repo.get_by(OAuthLinkingToken, token: token) do
      nil -> {:error, :not_found}
      linking_token -> Repo.delete(linking_token)
    end
  end
end
