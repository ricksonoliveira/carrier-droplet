defmodule CarrierDroplet.Workers.EmailCategorizationWorker do
  @moduledoc """
  Oban worker for categorizing and summarizing emails using AI.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias CarrierDroplet.{Emails, Accounts}
  alias CarrierDroplet.AI.Client

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email_id" => email_id}}) do
    email = Emails.get_email(email_id)

    if email do
      categorize_and_summarize(email)
    else
      {:error, :email_not_found}
    end
  end

  defp categorize_and_summarize(email) do
    # Get the user's categories
    gmail_account = Accounts.get_gmail_account!(email.gmail_account_id)
    categories = Emails.list_categories(gmail_account.user_id)

    # Categorize the email
    category_id =
      case Client.categorize_email(email.original_content, categories) do
        {:ok, cat_id} -> cat_id
        {:error, _} -> nil
      end

    # Summarize the email
    summary =
      case Client.summarize_email(email.original_content) do
        {:ok, sum} -> sum
        {:error, _} -> nil
      end

    # Update the email with category and summary
    Emails.update_email(email, %{
      category_id: category_id,
      summary: summary
    })

    {:ok, %{category_id: category_id, summary: summary}}
  end
end
