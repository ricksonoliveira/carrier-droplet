defmodule CarrierDroplet.Emails.Category do
  use Ecto.Schema
  import Ecto.Changeset

  schema "categories" do
    field :name, :string
    field :description, :string

    belongs_to :user, CarrierDroplet.Accounts.User
    has_many :emails, CarrierDroplet.Emails.Email

    timestamps()
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint([:user_id, :name])
  end
end
