defmodule CarrierDroplet.Repo.Migrations.CreateEmails do
  use Ecto.Migration

  def change do
    create table(:emails) do
      add :gmail_account_id, references(:gmail_accounts, on_delete: :delete_all), null: false
      add :category_id, references(:categories, on_delete: :nilify_all)
      add :gmail_message_id, :string, null: false
      add :subject, :string
      add :from_address, :string
      add :to_address, :string
      add :received_at, :utc_datetime
      add :summary, :text
      add :original_content, :text
      add :archived_at, :utc_datetime

      timestamps()
    end

    create index(:emails, [:gmail_account_id])
    create index(:emails, [:category_id])
    create unique_index(:emails, [:gmail_account_id, :gmail_message_id])
  end
end
