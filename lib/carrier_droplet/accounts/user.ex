defmodule CarrierDroplet.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :google_id, :string
    field :access_token, :string
    field :refresh_token, :string
    field :token_expires_at, :utc_datetime

    has_many :gmail_accounts, CarrierDroplet.Accounts.GmailAccount
    has_many :categories, CarrierDroplet.Emails.Category

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :google_id, :access_token, :refresh_token, :token_expires_at])
    |> validate_required([:email, :google_id])
    |> unique_constraint(:email)
    |> unique_constraint(:google_id)
  end
end
