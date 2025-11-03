defmodule CarrierDroplet.Emails do
  @moduledoc """
  The Emails context.
  """

  import Ecto.Query, warn: false
  alias CarrierDroplet.Repo
  alias CarrierDroplet.Emails.{Category, Email}

  ## Categories

  @doc """
  Lists all categories for a user.
  """
  def list_categories(user_id) do
    Category
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  @doc """
  Gets a single category.
  """
  def get_category(id), do: Repo.get(Category, id)

  @doc """
  Gets a single category, raises if not found.
  """
  def get_category!(id), do: Repo.get!(Category, id)

  @doc """
  Gets a category by user_id and id.
  """
  def get_category(user_id, id) do
    Category
    |> where([c], c.user_id == ^user_id and c.id == ^id)
    |> Repo.one()
  end

  @doc """
  Creates a category.
  """
  def create_category(user, attrs) when is_map(user) do
    user_id = if is_struct(user), do: user.id, else: user

    %Category{user_id: user_id}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a category.
  """
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a category.
  """
  def delete_category(%Category{} = category) do
    Repo.delete(category)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking category changes.
  """
  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end

  ## Emails

  @doc """
  Lists all emails for a category.
  """
  def list_emails_by_category(category_id) do
    Email
    |> where([e], e.category_id == ^category_id)
    |> order_by([e], desc: e.received_at)
    |> Repo.all()
  end

  @doc """
  Lists all uncategorized emails for a user's gmail accounts.
  """
  def list_uncategorized_emails(user_id) do
    Email
    |> join(:inner, [e], g in assoc(e, :gmail_account))
    |> where([e, g], is_nil(e.category_id) and g.user_id == ^user_id)
    |> order_by([e], desc: e.received_at)
    |> Repo.all()
  end

  @doc """
  Lists all emails for a gmail account.
  """
  def list_emails_by_gmail_account(gmail_account_id) do
    Email
    |> where([e], e.gmail_account_id == ^gmail_account_id)
    |> order_by([e], desc: e.received_at)
    |> Repo.all()
  end

  @doc """
  Gets a single email.
  """
  def get_email(id), do: Repo.get(Email, id)

  @doc """
  Gets an email by gmail_message_id and gmail_account_id.
  """
  def get_email_by_gmail_message_id(gmail_account_id, gmail_message_id) do
    Email
    |> where(
      [e],
      e.gmail_account_id == ^gmail_account_id and e.gmail_message_id == ^gmail_message_id
    )
    |> Repo.one()
  end

  @doc """
  Creates an email.
  """
  def create_email(gmail_account_id, attrs) do
    %Email{gmail_account_id: gmail_account_id}
    |> Email.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an email.
  """
  def update_email(%Email{} = email, attrs) do
    email
    |> Email.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an email.
  """
  def delete_email(%Email{} = email) do
    Repo.delete(email)
  end

  @doc """
  Deletes multiple emails by ids.
  """
  def delete_emails(email_ids) when is_list(email_ids) do
    Email
    |> where([e], e.id in ^email_ids)
    |> Repo.delete_all()
  end

  @doc """
  Counts emails in a category.
  """
  def count_emails_by_category(category_id) do
    Email
    |> where([e], e.category_id == ^category_id)
    |> Repo.aggregate(:count)
  end
end
