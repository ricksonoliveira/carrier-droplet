defmodule CarrierDroplet.Workers.RecategorizeEmailsWorker do
  @moduledoc """
  Oban worker for re-categorizing uncategorized emails.
  This is useful when new categories are added - uncategorized emails
  can be re-evaluated to see if they fit the new categories.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias CarrierDroplet.Emails

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    require Logger
    Logger.info("Re-categorizing uncategorized emails for user #{user_id}")

    # Get all uncategorized emails for this user
    uncategorized_emails = Emails.list_uncategorized_emails(user_id)

    # Enqueue categorization jobs for each uncategorized email
    Enum.each(uncategorized_emails, fn email ->
      %{email_id: email.id}
      |> CarrierDroplet.Workers.EmailCategorizationWorker.new()
      |> Oban.insert()
    end)

    Logger.info(
      "Enqueued categorization for #{length(uncategorized_emails)} uncategorized emails"
    )

    {:ok, %{count: length(uncategorized_emails)}}
  end
end
