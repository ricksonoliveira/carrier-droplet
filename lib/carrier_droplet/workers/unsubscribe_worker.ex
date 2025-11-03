defmodule CarrierDroplet.Workers.UnsubscribeWorker do
  @moduledoc """
  Oban worker for unsubscribing from emails using AI.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias CarrierDroplet.Emails
  alias CarrierDroplet.AI.UnsubscribeAgent

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email_id" => email_id}}) do
    email = Emails.get_email(email_id)

    if email do
      case UnsubscribeAgent.unsubscribe(email.original_content) do
        {:ok, url} ->
          {:ok, %{unsubscribed: true, url: url}}

        {:error, :no_unsubscribe_link} ->
          {:error, :no_unsubscribe_link}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :email_not_found}
    end
  end
end
