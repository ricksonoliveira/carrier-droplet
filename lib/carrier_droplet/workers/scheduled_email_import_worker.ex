defmodule CarrierDroplet.Workers.ScheduledEmailImportWorker do
  @moduledoc """
  Scheduled Oban worker that automatically imports new emails for all connected Gmail accounts.
  Runs periodically to check for new emails.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias CarrierDroplet.Accounts

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    require Logger
    Logger.info("Running scheduled email import for all accounts")

    # Get all Gmail accounts
    gmail_accounts = Accounts.list_all_gmail_accounts()

    # Enqueue import jobs for each account
    Enum.each(gmail_accounts, fn account ->
      %{gmail_account_id: account.id, user_id: account.user_id}
      |> CarrierDroplet.Workers.EmailImportWorker.new()
      |> Oban.insert()
    end)

    Logger.info("Enqueued email import for #{length(gmail_accounts)} accounts")

    :ok
  end
end
