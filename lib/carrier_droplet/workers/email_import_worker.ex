defmodule CarrierDroplet.Workers.EmailImportWorker do
  @moduledoc """
  Oban worker for importing emails from Gmail.
  """

  use Oban.Worker, queue: :email_import, max_attempts: 3

  alias CarrierDroplet.{Accounts, Emails}
  alias CarrierDroplet.Gmail.Client

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"gmail_account_id" => gmail_account_id, "user_id" => user_id}}) do
    # Get Gmail account with valid token (refreshes if needed)
    case Accounts.get_gmail_account_with_valid_token(gmail_account_id) do
      {:ok, gmail_account} ->
        import_emails_with_account(gmail_account, user_id)

      {:error, :gmail_account_not_found} ->
        Phoenix.PubSub.broadcast(
          CarrierDroplet.PubSub,
          "user:#{user_id}",
          {:email_import_complete, %{success: false, error: "Gmail account not found"}}
        )

        {:error, :gmail_account_not_found}

      {:error, reason} ->
        Phoenix.PubSub.broadcast(
          CarrierDroplet.PubSub,
          "user:#{user_id}",
          {:email_import_complete,
           %{success: false, error: "Failed to refresh token: #{inspect(reason)}"}}
        )

        {:error, :token_refresh_failed}
    end
  end

  defp import_emails_with_account(gmail_account, user_id) do
    case import_emails(gmail_account) do
      {:ok, count} ->
        # Broadcast success to user
        Phoenix.PubSub.broadcast(
          CarrierDroplet.PubSub,
          "user:#{user_id}",
          {:email_import_complete,
           %{success: true, count: count, account_email: gmail_account.email}}
        )

        {:ok, %{imported: count}}

      {:error, :unauthorized} ->
        # Token expired, need to refresh
        Phoenix.PubSub.broadcast(
          CarrierDroplet.PubSub,
          "user:#{user_id}",
          {:email_import_complete,
           %{success: false, error: "Token expired. Please reconnect your account."}}
        )

        {:error, :token_expired}

      {:error, reason} ->
        Phoenix.PubSub.broadcast(
          CarrierDroplet.PubSub,
          "user:#{user_id}",
          {:email_import_complete,
           %{success: false, error: "Failed to import emails: #{inspect(reason)}"}}
        )

        {:error, reason}
    end
  end

  defp import_emails(gmail_account) do
    # List UNREAD messages from Gmail inbox only (last 100)
    case Client.list_messages(gmail_account.access_token,
           max_results: 100,
           query: "in:inbox is:unread"
         ) do
      {:ok, %{"messages" => messages}} when is_list(messages) ->
        require Logger
        Logger.info("Found #{length(messages)} messages from Gmail")

        results =
          messages
          |> Enum.map(fn %{"id" => message_id} ->
            import_single_email(gmail_account, message_id)
          end)

        new_count = Enum.count(results, fn result -> result == {:ok, :new} end)
        existing_count = Enum.count(results, fn result -> result == {:ok, :existing} end)

        Logger.info("Imported #{new_count} new emails, #{existing_count} already existed")

        {:ok, new_count}

      {:ok, %{}} ->
        # No messages
        {:ok, 0}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp import_single_email(gmail_account, message_id) do
    # Check if email already exists
    case Emails.get_email_by_gmail_message_id(gmail_account.id, message_id) do
      nil ->
        # Fetch full message
        case Client.get_message(gmail_account.access_token, message_id) do
          {:ok, message} ->
            parsed = Client.parse_message(message)

            # Create email without category (will be categorized later)
            case Emails.create_email(gmail_account.id, parsed) do
              {:ok, email} ->
                # Mark the email as read in Gmail
                case Client.mark_as_read(gmail_account.access_token, message_id) do
                  {:ok, _} ->
                    require Logger
                    Logger.debug("Marked message #{message_id} as read in Gmail")

                  {:error, reason} ->
                    require Logger

                    Logger.error(
                      "Failed to mark message #{message_id} as read: #{inspect(reason)}"
                    )
                end

                # Enqueue categorization job
                %{email_id: email.id}
                |> CarrierDroplet.Workers.EmailCategorizationWorker.new()
                |> Oban.insert()

                {:ok, :new}

              {:error, _changeset} ->
                :error
            end

          {:error, _reason} ->
            :error
        end

      _existing_email ->
        # Email already imported
        {:ok, :existing}
    end
  end
end
