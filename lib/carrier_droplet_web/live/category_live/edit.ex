defmodule CarrierDropletWeb.CategoryLive.Edit do
  use CarrierDropletWeb, :live_view

  alias CarrierDroplet.Emails

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    category = Emails.get_category!(id)
    changeset = Emails.change_category(category)

    {:ok,
     socket
     |> assign(:page_title, "Edit Category")
     |> assign(:category, category)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"category" => category_params}, socket) do
    changeset =
      socket.assigns.category
      |> Emails.change_category(category_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"category" => category_params}, socket) do
    case Emails.update_category(socket.assigns.category, category_params) do
      {:ok, _category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category updated successfully")
         |> push_navigate(to: ~p"/dashboard")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div class="mb-8 flex justify-between items-start">
        <div>
          <h1 class="text-3xl font-bold text-gray-900">Edit Category</h1>
          <p class="mt-2 text-sm text-gray-600">
            Update your category details to refine AI categorization
          </p>
        </div>
        <a
          href={~p"/auth/logout"}
          class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
        >
          <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5 mr-2" /> Logout
        </a>
      </div>

      <div class="bg-white shadow rounded-lg p-6">
        <.form for={@form} id="category-form" phx-change="validate" phx-submit="save">
          <div class="space-y-6">
            <div>
              <.input
                field={@form[:name]}
                type="text"
                label="Category Name"
                placeholder="e.g., Newsletters, Work, Personal"
                required
              />
            </div>

            <div>
              <.input
                field={@form[:description]}
                type="textarea"
                label="Description"
                placeholder="Describe what types of emails should be categorized here. The AI will use this to categorize your emails."
                rows="4"
                required
              />
              <p class="mt-2 text-sm text-gray-500">
                Be specific! The AI uses this description to categorize emails. For example: "Promotional emails from online stores and marketing campaigns" or "Project updates and team communications from work"
              </p>
            </div>

            <div class="flex justify-end space-x-3">
              <.link
                navigate={~p"/dashboard"}
                class="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
              >
                Cancel
              </.link>
              <button
                type="submit"
                class="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
              >
                Update Category
              </button>
            </div>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
