defmodule CarrierDroplet.Repo.Migrations.AddOauthStateToUsers do
  use Ecto.Migration

  def change do
    create table(:oauth_linking_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :string, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:oauth_linking_tokens, [:token])
    create index(:oauth_linking_tokens, [:user_id])
  end
end
