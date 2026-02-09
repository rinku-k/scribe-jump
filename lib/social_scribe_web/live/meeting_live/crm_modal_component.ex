defmodule SocialScribeWeb.MeetingLive.CrmModalComponent do
  @moduledoc """
  Unified LiveComponent for CRM contact update modals.

  Supports HubSpot, Salesforce, and future CRM integrations through
  configuration-driven rendering. All CRM-specific values (display name,
  message atoms, button styling, icon paths) are sourced from `CrmConfig`.

  ## Features

  - **Contact Search**: Debounced search input queries the CRM API
  - **AI Suggestions**: Uses Google Gemini to analyze meeting transcripts and
    suggest updates to contact fields (phone, email, job title, etc.)
  - **Selective Updates**: Checkbox per field allows users to choose which
    suggestions to apply
  - **Retry Logic**: Handles rate limiting with suggested wait times

  ## Events

  - `contact_search` - Triggers CRM contact search
  - `select_contact` - Selects a contact and generates AI suggestions
  - `toggle_suggestion` - Toggles a suggestion's apply state
  - `apply_updates` - Applies selected updates to the CRM
  - `retry_generate_suggestions` - Retries after rate limiting

  ## Required Assigns

  - `:crm_type` - The CRM type atom (`:hubspot` or `:salesforce`)
  - `:meeting` - The meeting struct with transcript data
  - `:credential` - CRM OAuth credential for API calls
  """

  use SocialScribeWeb, :live_component

  import SocialScribeWeb.ModalComponents

  alias SocialScribeWeb.MeetingLive.CrmConfig

  @impl true
  def render(assigns) do
    config = CrmConfig.get(assigns.crm_type)
    assigns = assign(assigns, :patch, ~p"/dashboard/meetings/#{assigns.meeting}")
    assigns = assign_new(assigns, :modal_id, fn -> "#{config.modal_id_prefix}-modal-wrapper" end)
    assigns = assign(assigns, :config, config)

    ~H"""
    <div class="space-y-6">
      <div>
        <h2 id={"#{@modal_id}-title"} class="text-xl font-medium tracking-tight text-slate-900">
          Update in {@config.display_name}
        </h2>
        <p id={"#{@modal_id}-description"} class="mt-2 text-base font-light leading-7 text-slate-500">
          Here are suggested updates to sync with your integrations based on this
          <span class="block">meeting</span>
        </p>
      </div>

      <.contact_select
        selected_contact={@selected_contact}
        contacts={@contacts}
        loading={@searching}
        open={@dropdown_open}
        query={@query}
        target={@myself}
        error={@error}
        id={"#{@config.modal_id_prefix}-contact-select"}
      />

      <div :if={@error && @selected_contact} class="flex items-center gap-3">
        <button
          type="button"
          phx-click="retry_generate_suggestions"
          phx-target={@myself}
          class="px-3 py-2 rounded-md bg-slate-100 text-slate-800 text-sm font-medium hover:bg-slate-200"
        >
          Try again
        </button>
        <span :if={@retry_after_seconds} class="text-xs text-slate-500">
          Suggested wait: ~{@retry_after_seconds}s
        </span>
      </div>

      <%= if @selected_contact do %>
        <.suggestions_section
          suggestions={@suggestions}
          loading={@loading}
          myself={@myself}
          patch={@patch}
          config={@config}
        />
      <% end %>
    </div>
    """
  end

  attr :suggestions, :list, required: true
  attr :loading, :boolean, required: true
  attr :myself, :any, required: true
  attr :patch, :string, required: true
  attr :config, :map, required: true

  defp suggestions_section(assigns) do
    selected_count = Enum.count(assigns.suggestions, & &1.apply)
    object_count = if(selected_count > 0, do: 1, else: 0)
    integration_count = if(selected_count > 0, do: 1, else: 0)

    info_text =
      "#{object_count} #{pluralize("object", object_count)}, " <>
        "#{selected_count} #{pluralize("field", selected_count)} in " <>
        "#{integration_count} #{pluralize("integration", integration_count)} selected to update"

    assigns =
      assigns
      |> assign(:selected_count, selected_count)
      |> assign(:info_text, info_text)

    ~H"""
    <div class="space-y-4">
      <%= if @loading do %>
        <div class="text-center py-8 text-slate-500">
          <.icon name="hero-arrow-path" class="h-6 w-6 animate-spin mx-auto mb-2" />
          <p>Generating suggestions...</p>
        </div>
      <% else %>
        <%= if Enum.empty?(@suggestions) do %>
          <.empty_state
            message="No update suggestions found from this meeting."
            submessage="The AI didn't detect any new contact information in the transcript."
          />
        <% else %>
          <form phx-submit="apply_updates" phx-change="toggle_suggestion" phx-target={@myself}>
            <div class="space-y-4 max-h-[60vh] overflow-y-auto">
              <.suggestion_card
                :for={suggestion <- @suggestions}
                suggestion={suggestion}
                target={@myself}
              />
            </div>

            <.modal_footer
              cancel_patch={@patch}
              submit_text={"Update #{@config.display_name}"}
              submit_class={@config.button_class}
              icon_src={@config.icon_path}
              icon_class="w-7 h-7"
              disabled={@selected_count == 0}
              loading={@loading}
              loading_text="Updating..."
              info_text={@info_text}
            />
          </form>
        <% end %>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> maybe_select_all_suggestions(assigns)
      |> assign_new(:step, fn -> :search end)
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:contacts, fn -> [] end)
      |> assign_new(:selected_contact, fn -> nil end)
      |> assign_new(:suggestions, fn -> [] end)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:searching, fn -> false end)
      |> assign_new(:dropdown_open, fn -> false end)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:retry_after_seconds, fn -> nil end)

    {:ok, socket}
  end

  @impl true
  def handle_event("update_mapping", %{"field" => _field}, socket) do
    config = CrmConfig.get(socket.assigns.crm_type)

    if length(socket.assigns.suggestions) == 1 do
      selected_contact = socket.assigns.selected_contact
      credential = socket.assigns.credential

      updates =
        socket.assigns.suggestions
        |> Enum.filter(& &1.apply)
        |> Enum.into(%{}, fn s -> {s.field, s.new_value} end)

      if map_size(updates) > 0 do
        send(self(), {config.apply_message, updates, selected_contact, credential})
        {:noreply, assign(socket, loading: true)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("contact_search", %{"value" => query}, socket) do
    config = CrmConfig.get(socket.assigns.crm_type)
    query = String.trim(query)

    if String.length(query) >= 2 do
      socket = assign(socket, searching: true, error: nil, query: query, dropdown_open: true)
      send(self(), {config.search_message, query, socket.assigns.credential})
      {:noreply, socket}
    else
      {:noreply, assign(socket, query: query, contacts: [], dropdown_open: query != "")}
    end
  end

  @impl true
  def handle_event("open_contact_dropdown", _params, socket) do
    {:noreply, assign(socket, dropdown_open: true)}
  end

  @impl true
  def handle_event("close_contact_dropdown", _params, socket) do
    {:noreply, assign(socket, dropdown_open: false)}
  end

  @impl true
  def handle_event("toggle_contact_dropdown", _params, socket) do
    config = CrmConfig.get(socket.assigns.crm_type)

    if socket.assigns.dropdown_open do
      {:noreply, assign(socket, dropdown_open: false)}
    else
      socket = assign(socket, dropdown_open: true, searching: true)

      query =
        "#{socket.assigns.selected_contact.firstname} #{socket.assigns.selected_contact.lastname}"

      send(self(), {config.search_message, query, socket.assigns.credential})
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_contact", %{"id" => contact_id}, socket) do
    config = CrmConfig.get(socket.assigns.crm_type)
    contact = Enum.find(socket.assigns.contacts, &(&1.id == contact_id))

    if contact do
      socket =
        assign(socket,
          loading: true,
          selected_contact: contact,
          error: nil,
          retry_after_seconds: nil,
          dropdown_open: false,
          query: "",
          suggestions: []
        )

      send(
        self(),
        {config.generate_message, contact, socket.assigns.meeting, socket.assigns.credential}
      )

      {:noreply, socket}
    else
      {:noreply, assign(socket, error: "Contact not found")}
    end
  end

  @impl true
  def handle_event("retry_generate_suggestions", _params, socket) do
    config = CrmConfig.get(socket.assigns.crm_type)

    if socket.assigns.selected_contact do
      socket =
        assign(socket,
          loading: true,
          error: nil,
          retry_after_seconds: nil,
          suggestions: []
        )

      send(
        self(),
        {config.generate_message, socket.assigns.selected_contact, socket.assigns.meeting,
         socket.assigns.credential}
      )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_contact", _params, socket) do
    {:noreply,
     assign(socket,
       step: :search,
       selected_contact: nil,
       suggestions: [],
       loading: false,
       searching: false,
       dropdown_open: false,
       contacts: [],
       query: "",
       error: nil,
       retry_after_seconds: nil
     )}
  end

  @impl true
  def handle_event("toggle_suggestion", params, socket) do
    applied_fields = Map.get(params, "apply", %{})
    values = Map.get(params, "values", %{})
    checked_fields = Map.keys(applied_fields)

    updated_suggestions =
      Enum.map(socket.assigns.suggestions, fn suggestion ->
        apply? = suggestion.field in checked_fields

        suggestion =
          case Map.get(values, suggestion.field) do
            nil -> suggestion
            new_value -> %{suggestion | new_value: new_value}
          end

        %{suggestion | apply: apply?}
      end)

    {:noreply, assign(socket, suggestions: updated_suggestions)}
  end

  @impl true
  def handle_event("apply_updates", %{"apply" => selected, "values" => values}, socket) do
    config = CrmConfig.get(socket.assigns.crm_type)
    socket = assign(socket, loading: true, error: nil)

    updates =
      selected
      |> Map.keys()
      |> Enum.reduce(%{}, fn field, acc ->
        Map.put(acc, field, Map.get(values, field, ""))
      end)

    send(
      self(),
      {config.apply_message, updates, socket.assigns.selected_contact,
       socket.assigns.credential}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_updates", _params, socket) do
    {:noreply, assign(socket, error: "Please select at least one field to update")}
  end

  # --- Private helpers ---

  defp maybe_select_all_suggestions(socket, %{suggestions: suggestions})
       when is_list(suggestions) do
    assign(socket, suggestions: Enum.map(suggestions, &Map.put(&1, :apply, true)))
  end

  defp maybe_select_all_suggestions(socket, _assigns), do: socket

  defp pluralize(word, 1), do: word
  defp pluralize(word, _count), do: word <> "s"
end
