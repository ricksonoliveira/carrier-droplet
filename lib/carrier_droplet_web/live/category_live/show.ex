defmodule CarrierDropletWeb.CategoryLive.Show do
  use CarrierDropletWeb, :live_view

  alias CarrierDroplet.Emails

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    category = Emails.get_category!(id)
    emails = Emails.list_emails_by_category(id)

    {:ok,
     socket
     |> assign(:page_title, category.name)
     |> assign(:category, category)
     |> stream(:emails, emails)
     |> assign(:selected_email_ids, MapSet.new())
     |> assign(:emails_empty?, emails == [])
     |> assign(:selected_email, nil)}
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected = socket.assigns.selected_email_ids
    email_id = String.to_integer(id)

    new_selected =
      if MapSet.member?(selected, email_id) do
        MapSet.delete(selected, email_id)
      else
        MapSet.put(selected, email_id)
      end

    {:noreply, assign(socket, :selected_email_ids, new_selected)}
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    emails = Emails.list_emails_by_category(socket.assigns.category.id)
    all_ids = MapSet.new(Enum.map(emails, & &1.id))

    {:noreply,
     socket
     |> assign(:selected_email_ids, all_ids)
     |> stream(:emails, emails, reset: true)}
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    emails = Emails.list_emails_by_category(socket.assigns.category.id)

    {:noreply,
     socket
     |> assign(:selected_email_ids, MapSet.new())
     |> stream(:emails, emails, reset: true)}
  end

  @impl true
  def handle_event("bulk_delete", _params, socket) do
    selected_ids = MapSet.to_list(socket.assigns.selected_email_ids)

    if selected_ids == [] do
      {:noreply, put_flash(socket, :error, "No emails selected")}
    else
      case Emails.delete_emails(selected_ids) do
        {count, _} when count > 0 ->
          # Refresh the email list
          emails = Emails.list_emails_by_category(socket.assigns.category.id)

          {:noreply,
           socket
           |> stream(:emails, emails, reset: true)
           |> assign(:selected_email_ids, MapSet.new())
           |> assign(:emails_empty?, emails == [])
           |> put_flash(:info, "#{count} email(s) deleted successfully")}

        _ ->
          {:noreply, put_flash(socket, :error, "Failed to delete emails")}
      end
    end
  end

  @impl true
  def handle_event("bulk_unsubscribe", _params, socket) do
    selected_ids = MapSet.to_list(socket.assigns.selected_email_ids)

    if selected_ids == [] do
      {:noreply, put_flash(socket, :error, "No emails selected")}
    else
      # Enqueue unsubscribe jobs for each selected email
      Enum.each(selected_ids, fn email_id ->
        %{email_id: email_id}
        |> CarrierDroplet.Workers.UnsubscribeWorker.new()
        |> Oban.insert()
      end)

      {:noreply,
       socket
       |> assign(:selected_email_ids, MapSet.new())
       |> put_flash(:info, "Unsubscribe requests queued for #{length(selected_ids)} email(s)")}
    end
  end

  @impl true
  def handle_event("view_email", %{"id" => id}, socket) do
    email = Emails.get_email(String.to_integer(id))
    {:noreply, assign(socket, :selected_email, email)}
  end

  @impl true
  def handle_event("close_email", _params, socket) do
    {:noreply, assign(socket, :selected_email, nil)}
  end

  @impl true
  def handle_event("unsubscribe_single", %{"id" => id}, socket) do
    email_id = String.to_integer(id)

    # Enqueue unsubscribe job
    %{email_id: email_id}
    |> CarrierDroplet.Workers.UnsubscribeWorker.new()
    |> Oban.insert()

    {:noreply,
     socket
     |> assign(:selected_email, nil)
     |> put_flash(:info, "Unsubscribe request queued for this email")}
  end

  @impl true
  def handle_event("delete_single", %{"id" => id}, socket) do
    email_id = String.to_integer(id)

    case Emails.delete_email(Emails.get_email(email_id)) do
      {:ok, _} ->
        emails = Emails.list_emails_by_category(socket.assigns.category.id)

        {:noreply,
         socket
         |> stream(:emails, emails, reset: true)
         |> assign(:emails_empty?, emails == [])
         |> assign(:selected_email, nil)
         |> put_flash(:info, "Email deleted successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete email")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div class="mb-8">
        <div class="flex justify-between items-center">
          <div>
            <.link navigate={~p"/dashboard"} class="text-sm text-indigo-600 hover:text-indigo-900">
              ← Back to Dashboard
            </.link>
            <h1 class="text-3xl font-bold text-gray-900 mt-2">{@category.name}</h1>
            <p class="mt-2 text-sm text-gray-600">{@category.description}</p>
          </div>
          <div class="flex items-center space-x-3">
            <.link
              navigate={~p"/categories/#{@category.id}/edit"}
              class="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
            >
              Edit Category
            </.link>
            <a
              href={~p"/auth/logout"}
              class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5 mr-2" /> Logout
            </a>
          </div>
        </div>
      </div>

      <%!-- Bulk Actions Bar --%>
      <div
        :if={MapSet.size(@selected_email_ids) > 0}
        class="bg-indigo-50 border border-indigo-200 rounded-lg p-4 mb-4"
      >
        <div class="flex items-center justify-between">
          <span class="text-sm font-medium text-indigo-900">
            {MapSet.size(@selected_email_ids)} email(s) selected
          </span>
          <div class="flex space-x-3">
            <button
              phx-click="deselect_all"
              class="text-sm text-indigo-600 hover:text-indigo-900"
            >
              Deselect All
            </button>
            <button
              phx-click="bulk_unsubscribe"
              data-confirm="Are you sure you want to unsubscribe from the selected emails?"
              class="px-3 py-1 bg-indigo-600 text-white text-sm rounded-md hover:bg-indigo-700"
            >
              Unsubscribe Selected
            </button>
            <button
              phx-click="bulk_delete"
              data-confirm="Are you sure you want to delete the selected emails?"
              class="px-3 py-1 bg-red-600 text-white text-sm rounded-md hover:bg-red-700"
            >
              Delete Selected
            </button>
          </div>
        </div>
      </div>

      <%!-- Emails List --%>
      <div class="bg-white shadow rounded-lg overflow-hidden">
        <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
          <h2 class="text-lg font-medium text-gray-900">Emails</h2>
          <button
            :if={!@emails_empty?}
            phx-click="select_all"
            class="text-sm text-indigo-600 hover:text-indigo-900"
          >
            Select All
          </button>
        </div>

        <div id="emails" phx-update="stream">
          <div id="emails-empty" class="hidden only:block text-gray-500 text-center py-12">
            No emails in this category yet. Emails will appear here once they are imported and categorized.
          </div>
          <div
            :for={{id, email} <- @streams.emails}
            id={id}
            class="border-b border-gray-200 last:border-0 hover:bg-gray-50"
          >
            <div class="px-6 py-4 flex items-start space-x-4">
              <input
                type="checkbox"
                checked={MapSet.member?(@selected_email_ids, email.id)}
                phx-click="toggle_select"
                phx-value-id={email.id}
                class="mt-1 h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
              />
              <div
                class="flex-1 min-w-0 cursor-pointer"
                phx-click="view_email"
                phx-value-id={email.id}
              >
                <div class="flex items-center justify-between">
                  <p class="text-sm font-medium text-gray-900 truncate hover:text-indigo-600">
                    {email.subject}
                  </p>
                  <p class="text-sm text-gray-500 ml-4">
                    {Calendar.strftime(email.received_at, "%b %d, %Y")}
                  </p>
                </div>
                <p class="text-sm text-gray-600 mt-1">From: {email.from_address}</p>
                <p :if={email.summary} class="text-sm text-gray-700 mt-2 italic">
                  {email.summary}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Email View Modal --%>
      <div
        :if={@selected_email}
        class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50"
        phx-click="close_email"
      >
        <div
          class="bg-white rounded-lg shadow-xl max-w-4xl w-full mx-4 max-h-[90vh] overflow-hidden"
          phx-click-away="close_email"
        >
          <div class="px-6 py-4 border-b border-gray-200">
            <div class="flex justify-between items-start mb-3">
              <div class="flex-1">
                <h3 class="text-lg font-medium text-gray-900">{@selected_email.subject}</h3>
                <p class="text-sm text-gray-600 mt-1">From: {@selected_email.from_address}</p>
                <p class="text-sm text-gray-500">
                  {Calendar.strftime(@selected_email.received_at, "%B %d, %Y at %I:%M %p")}
                </p>
              </div>
              <button
                phx-click="close_email"
                class="text-gray-400 hover:text-gray-500"
                aria-label="Close"
              >
                <.icon name="hero-x-mark" class="w-6 h-6" />
              </button>
            </div>
            <div class="flex space-x-3">
              <button
                phx-click="unsubscribe_single"
                phx-value-id={@selected_email.id}
                class="inline-flex items-center px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
              >
                <.icon name="hero-x-circle" class="w-4 h-4 mr-1.5" /> Unsubscribe
              </button>
              <button
                phx-click="delete_single"
                phx-value-id={@selected_email.id}
                class="inline-flex items-center px-3 py-1.5 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
              >
                <.icon name="hero-trash" class="w-4 h-4 mr-1.5" /> Delete
              </button>
            </div>
          </div>
          <div class="px-6 py-4 overflow-y-auto max-h-[calc(90vh-120px)]">
            <div class="prose max-w-none">
              <div phx-no-format>{raw(@selected_email.original_content)}</div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
