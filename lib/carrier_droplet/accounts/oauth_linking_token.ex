defmodule CarrierDroplet.Accounts.OAuthLinkingToken do
  use Ecto.Schema
  import Ecto.Changeset

  schema "oauth_linking_tokens" do
    field :token, :string
    field :expires_at, :utc_datetime

    belongs_to :user, CarrierDroplet.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:token, :expires_at])
    |> validate_required([:token, :expires_at])
    |> unique_constraint(:token)
  end
end
