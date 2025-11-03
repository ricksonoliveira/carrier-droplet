defmodule CarrierDropletWeb.DashboardLive do
  use CarrierDropletWeb, :live_view

  alias CarrierDroplet.Accounts
  alias CarrierDroplet.Emails

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    # Subscribe to email import updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CarrierDroplet.PubSub, "user:#{current_user.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:disconnect_account, nil)
     |> stream(:gmail_accounts, Accounts.list_gmail_accounts(current_user.id))
     |> stream(:categories, Emails.list_categories(current_user.id))
     |> assign(:categories_empty?, Emails.list_categories(current_user.id) == [])}
  end

  @impl true
  def handle_event("delete_category", %{"id" => id}, socket) do
    category = Emails.get_category!(id)

    case Emails.delete_category(category) do
      {:ok, _category} ->
        {:noreply,
         socket
         |> stream_delete(:categories, category)
         |> put_flash(:info, "Category deleted successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete category")}
    end
  end

  @impl true
  def handle_event("add_account", _params, socket) do
    current_user = socket.assigns.current_user

    # Create a linking token
    case Accounts.create_oauth_linking_token(current_user.id) do
      {:ok, linking_token} ->
        # Redirect to Google OAuth with the token as a query parameter
        {:noreply,
         socket
         |> push_navigate(to: "/auth/google?linking_token=#{linking_token.token}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to initiate account linking")}
    end
  end

  @impl true
  def handle_event("import_emails", %{"account_id" => account_id}, socket) do
    current_user = socket.assigns.current_user

    # Enqueue email import job
    %{gmail_account_id: String.to_integer(account_id), user_id: current_user.id}
    |> CarrierDroplet.Workers.EmailImportWorker.new()
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Email import started. This may take a few moments.")}
  end

  @impl true
  def handle_event("show_disconnect_modal", %{"account_id" => account_id}, socket) do
    account = Accounts.get_gmail_account(String.to_integer(account_id))
    {:noreply, assign(socket, :disconnect_account, account)}
  end

  @impl true
  def handle_event("close_disconnect_modal", _params, socket) do
    {:noreply, assign(socket, :disconnect_account, nil)}
  end

  @impl true
  def handle_event("confirm_disconnect", _params, socket) do
    account = socket.assigns.disconnect_account
    current_user = socket.assigns.current_user

    if account.is_primary do
      # Delete the entire user account
      case Accounts.delete_user(current_user) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Your account has been deleted successfully")
           |> push_navigate(to: ~p"/")}

        {:error, _} ->
          {:noreply,
           socket
           |> assign(:disconnect_account, nil)
           |> put_flash(:error, "Failed to delete account")}
      end
    else
      # Just delete the Gmail account
      case Accounts.delete_gmail_account(account) do
        {:ok, _} ->
          {:noreply,
           socket
           |> stream_delete(:gmail_accounts, account)
           |> assign(:disconnect_account, nil)
           |> put_flash(:info, "Gmail account disconnected successfully")}

        {:error, _} ->
          {:noreply,
           socket
           |> assign(:disconnect_account, nil)
           |> put_flash(:error, "Failed to disconnect account")}
      end
    end
  end

  @impl true
  def handle_info(
        {:email_import_complete, %{success: true, count: count, account_email: email}},
        socket
      ) do
    {:noreply,
     socket
     |> put_flash(:info, "Successfully imported #{count} emails from #{email}")
     |> stream(:categories, Emails.list_categories(socket.assigns.current_user.id), reset: true)
     |> assign(:categories_empty?, Emails.list_categories(socket.assigns.current_user.id) == [])}
  end

  @impl true
  def handle_info({:email_import_complete, %{success: false, error: error}}, socket) do
    {:noreply, put_flash(socket, :error, error)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div class="mb-8 flex justify-between items-start">
        <div>
          <h1 class="text-3xl font-bold text-gray-900">Dashboard</h1>
          <p class="mt-2 text-sm text-gray-600">
            Manage your Gmail accounts and email categories
          </p>
        </div>
        <a
          href={~p"/auth/logout"}
          class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
        >
          <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5 mr-2" /> Logout
        </a>
      </div>

      <%!-- Gmail Accounts Section --%>
      <div class="bg-white shadow rounded-lg p-6 mb-8">
        <div class="flex justify-between items-center mb-4">
          <h2 class="text-xl font-semibold text-gray-900">Connected Gmail Accounts</h2>
          <button
            phx-click="add_account"
            class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
          >
            <.icon name="hero-plus" class="w-5 h-5 mr-2" /> Add Account
          </button>
        </div>

        <div id="gmail-accounts" phx-update="stream">
          <div id="gmail-accounts-empty" class="hidden only:block text-gray-500 text-center py-8">
            No Gmail accounts connected yet
          </div>
          <div
            :for={{id, account} <- @streams.gmail_accounts}
            id={id}
            class="flex items-center justify-between py-3 border-b border-gray-200 last:border-0"
          >
            <div class="flex items-center space-x-3">
              <.icon name="hero-envelope" class="w-5 h-5 text-gray-400" />
              <div>
                <div class="flex items-center gap-2">
                  <p class="text-sm font-medium text-gray-900">{account.email}</p>
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                    Connected
                  </span>
                </div>
                <p :if={account.is_primary} class="text-xs text-indigo-600">Primary Account</p>
              </div>
            </div>
            <div class="flex items-center space-x-3">
              <button
                phx-click="import_emails"
                phx-value-account_id={account.id}
                class="inline-flex items-center px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 cursor-pointer"
              >
                <.icon name="hero-arrow-down-tray" class="w-4 h-4 mr-1.5" /> Import Emails
              </button>
              <button
                phx-click="show_disconnect_modal"
                phx-value-account_id={account.id}
                class="inline-flex items-center px-3 py-1.5 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500 cursor-pointer"
              >
                <.icon name="hero-x-circle" class="w-4 h-4 mr-1.5" /> Disconnect
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Categories Section --%>
      <div class="bg-white shadow rounded-lg p-6">
        <div class="flex justify-between items-center mb-4">
          <h2 class="text-xl font-semibold text-gray-900">Email Categories</h2>
          <.link
            navigate={~p"/categories/new"}
            class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
          >
            <.icon name="hero-plus" class="w-5 h-5 mr-2" /> New Category
          </.link>
        </div>

        <div id="categories" phx-update="stream">
          <div id="categories-empty" class="hidden only:block text-gray-500 text-center py-8">
            No categories created yet. Create your first category to start organizing emails.
          </div>
          <div
            :for={{id, category} <- @streams.categories}
            id={id}
            class="flex items-center justify-between py-4 border-b border-gray-200 last:border-0"
          >
            <div class="flex-1">
              <h3 class="text-sm font-medium text-gray-900">{category.name}</h3>
              <p class="text-sm text-gray-500 mt-1">{category.description}</p>
            </div>
            <div class="flex items-center space-x-4">
              <.link
                navigate={~p"/categories/#{category.id}"}
                class="text-sm text-indigo-600 hover:text-indigo-900"
              >
                View Emails
              </.link>
              <.link
                navigate={~p"/categories/#{category.id}/edit"}
                class="text-sm text-gray-600 hover:text-gray-900"
              >
                Edit
              </.link>
              <button
                phx-click="delete_category"
                phx-value-id={category.id}
                data-confirm="Are you sure you want to delete this category?"
                class="text-sm text-red-600 hover:text-red-900"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Disconnect Confirmation Modal --%>
      <div
        :if={@disconnect_account}
        class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50"
        phx-click="close_disconnect_modal"
      >
        <div
          class="bg-white rounded-lg shadow-xl max-w-md w-full mx-4 p-6"
          phx-click-away="close_disconnect_modal"
        >
          <div class="flex items-start mb-4">
            <div class="flex-shrink-0">
              <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-red-600" />
            </div>
            <div class="ml-3 flex-1">
              <h3 class="text-lg font-medium text-gray-900">
                Disconnect Gmail Account
              </h3>
              <div class="mt-2 text-sm text-gray-500">
                <p class="mb-2">
                  Are you sure you want to disconnect <strong>{@disconnect_account.email}</strong>?
                </p>
                <p :if={@disconnect_account.is_primary} class="text-red-600 font-medium">
                  ⚠️ This is your primary account. Your entire account will be deleted from this app since it's required to have at least one Gmail account connected.
                </p>
                <p :if={!@disconnect_account.is_primary}>
                  This will remove access to this Gmail account from the app.
                </p>
              </div>
            </div>
          </div>
          <div class="flex justify-end space-x-3">
            <button
              phx-click="close_disconnect_modal"
              class="inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            >
              Cancel
            </button>
            <button
              phx-click="confirm_disconnect"
              class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
            >
              {if @disconnect_account.is_primary, do: "Delete Account", else: "Disconnect"}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
