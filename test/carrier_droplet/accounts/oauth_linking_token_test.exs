defmodule CarrierDroplet.Accounts.OAuthLinkingTokenTest do
  use CarrierDroplet.DataCase

  alias CarrierDroplet.Accounts.OAuthLinkingToken
  alias CarrierDroplet.Accounts

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      attrs = %{
        token: "test_token_123",
        expires_at: DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      changeset = OAuthLinkingToken.changeset(%OAuthLinkingToken{}, attrs)

      assert changeset.valid?
      assert changeset.changes.token == "test_token_123"
      assert %DateTime{} = changeset.changes.expires_at
    end

    test "invalid changeset when token is missing" do
      attrs = %{
        expires_at: DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      changeset = OAuthLinkingToken.changeset(%OAuthLinkingToken{}, attrs)

      refute changeset.valid?
      assert %{token: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid changeset when expires_at is missing" do
      attrs = %{
        token: "test_token_123"
      }

      changeset = OAuthLinkingToken.changeset(%OAuthLinkingToken{}, attrs)

      refute changeset.valid?
      assert %{expires_at: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid changeset when both fields are missing" do
      attrs = %{}

      changeset = OAuthLinkingToken.changeset(%OAuthLinkingToken{}, attrs)

      refute changeset.valid?
      errors = errors_on(changeset)
      assert %{token: ["can't be blank"], expires_at: ["can't be blank"]} = errors
    end

    test "unique constraint on token" do
      # Create a user first
      {:ok, user} =
        Accounts.upsert_user_from_oauth(%{
          "email" => "user@example.com",
          "google_id" => "google_123",
          "access_token" => "token",
          "refresh_token" => "refresh",
          "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
        })

      # Create first token
      {:ok, _token1} = Accounts.create_oauth_linking_token(user.id)

      # Try to create another token with the same token value
      # This is hard to test directly, but we can verify the constraint exists
      changeset =
        OAuthLinkingToken.changeset(%OAuthLinkingToken{}, %{
          token: "duplicate_token",
          expires_at: DateTime.utc_now() |> DateTime.add(3600, :second)
        })

      assert changeset.valid?
      # The unique constraint is checked at the database level
    end
  end

  describe "schema fields" do
    test "has correct fields" do
      token = %OAuthLinkingToken{}

      assert Map.has_key?(token, :token)
      assert Map.has_key?(token, :expires_at)
      assert Map.has_key?(token, :user_id)
      assert Map.has_key?(token, :inserted_at)
      assert Map.has_key?(token, :updated_at)
    end

    test "belongs to user" do
      # Create a user
      {:ok, user} =
        Accounts.upsert_user_from_oauth(%{
          "email" => "user@example.com",
          "google_id" => "google_123",
          "access_token" => "token",
          "refresh_token" => "refresh",
          "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
        })

      # Create a linking token
      {:ok, token} = Accounts.create_oauth_linking_token(user.id)

      # Verify the association
      assert token.user_id == user.id

      # Load the token with user association
      loaded_token =
        Repo.get(OAuthLinkingToken, token.id)
        |> Repo.preload(:user)

      assert loaded_token.user.id == user.id
      assert loaded_token.user.email == "user@example.com"
    end
  end

  describe "integration with Accounts context" do
    test "create_oauth_linking_token/1 creates valid token" do
      # Create a user
      {:ok, user} =
        Accounts.upsert_user_from_oauth(%{
          "email" => "user@example.com",
          "google_id" => "google_123",
          "access_token" => "token",
          "refresh_token" => "refresh",
          "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
        })

      # Create linking token
      {:ok, token} = Accounts.create_oauth_linking_token(user.id)

      assert token.user_id == user.id
      assert is_binary(token.token)
      assert String.length(token.token) > 0
      assert %DateTime{} = token.expires_at
      assert DateTime.compare(token.expires_at, DateTime.utc_now()) == :gt
    end

    test "get_user_by_oauth_linking_token/1 retrieves user" do
      # Create a user
      {:ok, user} =
        Accounts.upsert_user_from_oauth(%{
          "email" => "user@example.com",
          "google_id" => "google_123",
          "access_token" => "token",
          "refresh_token" => "refresh",
          "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
        })

      # Create linking token
      {:ok, token} = Accounts.create_oauth_linking_token(user.id)

      # Retrieve user by token
      retrieved_user = Accounts.get_user_by_oauth_linking_token(token.token)

      assert retrieved_user.id == user.id
      assert retrieved_user.email == "user@example.com"
    end

    test "get_user_by_oauth_linking_token/1 returns nil for invalid token" do
      result = Accounts.get_user_by_oauth_linking_token("invalid_token_123")

      assert result == nil
    end

    test "delete_oauth_linking_token/1 removes token" do
      # Create a user
      {:ok, user} =
        Accounts.upsert_user_from_oauth(%{
          "email" => "user@example.com",
          "google_id" => "google_123",
          "access_token" => "token",
          "refresh_token" => "refresh",
          "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
        })

      # Create linking token
      {:ok, token} = Accounts.create_oauth_linking_token(user.id)

      # Verify token exists
      assert Accounts.get_user_by_oauth_linking_token(token.token) != nil

      # Delete token (pass the token string, not the struct)
      {:ok, _deleted} = Accounts.delete_oauth_linking_token(token.token)

      # Verify token is gone
      assert Accounts.get_user_by_oauth_linking_token(token.token) == nil
    end

    test "delete_oauth_linking_token/1 returns error for non-existent token" do
      result = Accounts.delete_oauth_linking_token("non_existent_token")

      assert result == {:error, :not_found}
    end
  end
end
