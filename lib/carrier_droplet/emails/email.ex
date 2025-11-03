defmodule CarrierDroplet.Emails.Email do
  use Ecto.Schema
  import Ecto.Changeset

  schema "emails" do
    field :gmail_message_id, :string
    field :subject, :string
    field :from_address, :string
    field :to_address, :string
    field :received_at, :utc_datetime
    field :summary, :string
    field :original_content, :string
    field :archived_at, :utc_datetime

    belongs_to :gmail_account, CarrierDroplet.Accounts.GmailAccount
    belongs_to :category, CarrierDroplet.Emails.Category

    timestamps()
  end

  @doc false
  def changeset(email, attrs) do
    email
    |> cast(attrs, [
      :gmail_message_id,
      :subject,
      :from_address,
      :to_address,
      :received_at,
      :summary,
      :original_content,
      :archived_at,
      :category_id
    ])
    |> validate_required([:gmail_message_id])
    |> unique_constraint([:gmail_account_id, :gmail_message_id])
  end
end
