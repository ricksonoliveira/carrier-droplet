defmodule CarrierDroplet.Accounts.GmailAccount do
  use Ecto.Schema
  import Ecto.Changeset

  schema "gmail_accounts" do
    field :email, :string
    field :access_token, :string
    field :refresh_token, :string
    field :token_expires_at, :utc_datetime
    field :is_primary, :boolean, default: false

    belongs_to :user, CarrierDroplet.Accounts.User
    has_many :emails, CarrierDroplet.Emails.Email

    timestamps()
  end

  @doc false
  def changeset(gmail_account, attrs) do
    gmail_account
    |> cast(attrs, [:email, :access_token, :refresh_token, :token_expires_at, :is_primary])
    |> validate_required([:email])
    |> unique_constraint([:user_id, :email])
  end
end
