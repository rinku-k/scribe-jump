defmodule SocialScribeWeb.Chat.ChatComponent do
  @moduledoc """
  A chat drawer component that allows users to ask questions about contacts
  in both HubSpot and Salesforce. Supports contact tagging and AI-powered answers.

  ## Features

  - **Contact Tagging**: Type `@` to search and tag contacts from HubSpot or Salesforce
  - **AI-Powered Answers**: Questions are answered using Google Gemini with context
    from meeting transcripts and tagged contact data
  - **Chat/History Tabs**: Switch between active chat and conversation history
  - **Auto-Scroll**: JavaScript hook ensures the chat always scrolls to latest message
  - **Responsive Design**: Full-width on mobile, 400px side panel on desktop

  ## Events

  - `send_message` - Sends user message to AI for processing
  - `chat_keyup` - Handles typing, @mention detection
  - `tag_contact` - Tags a selected contact
  - `remove_tag` - Removes a tagged contact
  - `switch_tab` - Switches between Chat and History tabs
  - `new_chat` - Starts a new conversation
  """

  use SocialScribeWeb, :live_component

  alias SocialScribe.Accounts
  alias SocialScribeWeb.Chat.ChatHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "fixed inset-y-0 right-0 z-50 w-full md:w-[400px] bg-white shadow-2xl transform transition-transform duration-300 ease-in-out border-l border-gray-200 flex flex-col font-sans",
        @show && "translate-x-0",
        !@show && "translate-x-full"
      ]}
    >
      <!-- Header -->
      <div class="px-6 py-4 border-b border-gray-100">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-xl font-semibold text-gray-900 tracking-tight">Ask Anything</h2>
          <button
            phx-click="toggle_chat"
            class="text-gray-400 hover:text-gray-600 transition-colors p-1"
            aria-label="Close chat"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="2"
              stroke="currentColor"
              class="w-5 h-5"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M11.25 4.5l7.5 7.5-7.5 7.5m-6-15l7.5 7.5-7.5 7.5"
              />
            </svg>
          </button>
        </div>

        <div class="flex items-center gap-6 text-sm font-medium border-b border-transparent">
          <button
            phx-click="switch_tab"
            phx-value-tab="chat"
            phx-target={@myself}
            class={[
              "px-3 py-1.5 rounded-md transition-colors",
              @active_tab == "chat" && "text-gray-900 bg-gray-100",
              @active_tab != "chat" && "text-gray-500 hover:text-gray-700"
            ]}
          >
            Chat
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="history"
            phx-target={@myself}
            class={[
              "px-3 py-1.5 rounded-md transition-colors",
              @active_tab == "history" && "text-gray-900 bg-gray-100",
              @active_tab != "history" && "text-gray-500 hover:text-gray-700"
            ]}
          >
            History
          </button>
          <div class="ml-auto">
            <button
              phx-click="new_chat"
              phx-target={@myself}
              class="text-gray-400 hover:text-gray-600"
              title="New conversation"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="size-5"
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
              </svg>
            </button>
          </div>
        </div>
      </div>
      
    <!-- Messages Area -->
      <div id="chat-messages" phx-hook="ChatScroll" class="flex-1 overflow-y-auto px-6 py-4 space-y-6">
        <%= if @active_tab == "chat" do %>
          <!-- Date Separator -->
          <div class="flex items-center justify-center relative">
            <div class="absolute inset-0 flex items-center" aria-hidden="true">
              <div class="w-full border-t border-gray-200"></div>
            </div>
            <div class="relative flex justify-center">
              <span class="bg-white px-3 text-xs text-gray-400">
                {Calendar.strftime(DateTime.utc_now(), "%I:%M%P – %B %d, %Y")}
              </span>
            </div>
          </div>
          
    <!-- Welcome Message -->
          <div class="text-gray-800 text-[15px] leading-relaxed">
            I can answer questions about Jump meetings and data – just ask!
          </div>
          
    <!-- Message History -->
          <div :for={message <- @messages} class="space-y-4">
            <!-- User Message -->
            <div :if={message.role == :user} class="flex justify-end">
              <div class="bg-chat-bubble text-gray-900 px-4 py-2.5 rounded-2xl rounded-tr-sm text-[15px] leading-relaxed max-w-[90%] font-sans flex items-center flex-wrap gap-x-1 whitespace-pre-wrap">
                <.message_content
                  content={message.content}
                  contacts={Map.get(message, :tagged_contacts, [])}
                  mode={:user}
                />
              </div>
            </div>
            
    <!-- AI Response -->
            <div
              :if={message.role == :assistant}
              class="text-gray-800 text-[15px] leading-relaxed space-y-2"
            >
              <div class="prose prose-sm max-w-none">
                <p :for={paragraph <- String.split(message.content, "\n\n")} class="mb-2">
                  <.message_content
                    content={paragraph}
                    contacts={@conversation_contacts}
                    mode={:assistant}
                  />
                </p>
              </div>
              <div
                :if={message[:sources] && is_list(message.sources)}
                class="flex items-center gap-2 mt-2"
              >
                <span class="text-[11px] text-gray-400 font-medium">Sources</span>
                <div class="flex -space-x-1">
                  <span
                    :if={:jump in message.sources}
                    class="bg-gray-100 rounded-full w-4 h-4 inline-flex items-center justify-center z-40 border border-white"
                  >
                    <.source_icon type={:jump} class="w-2.5 h-2.5" />
                  </span>
                  <span
                    :if={:meeting in message.sources}
                    class="bg-gray-100 rounded-full w-4 h-4 inline-flex items-center justify-center z-30 border border-white"
                  >
                    <.source_icon type={:meeting} class="w-2.5 h-2.5" />
                  </span>
                  <span
                    :if={:hubspot in message.sources}
                    class="bg-gray-100 rounded-full w-4 h-4 inline-flex items-center justify-center z-20 border border-white"
                  >
                    <.source_icon type={:hubspot} class="w-2.5 h-2.5" />
                  </span>
                  <span
                    :if={:salesforce in message.sources}
                    class="bg-gray-100 rounded-full w-4 h-4 inline-flex items-center justify-center z-10 border border-white"
                  >
                    <.source_icon type={:salesforce} class="w-2.5 h-2.5" />
                  </span>
                </div>
              </div>
            </div>
            
    <!-- Loading indicator -->
            <div :if={message.role == :loading} class="flex items-center gap-2 text-gray-500">
              <div class="flex gap-1">
                <span
                  class="w-2 h-2 rounded-full bg-gray-400 animate-bounce"
                  style="animation-delay: 0ms"
                >
                </span>
                <span
                  class="w-2 h-2 rounded-full bg-gray-400 animate-bounce"
                  style="animation-delay: 150ms"
                >
                </span>
                <span
                  class="w-2 h-2 rounded-full bg-gray-400 animate-bounce"
                  style="animation-delay: 300ms"
                >
                </span>
              </div>
              <span class="text-sm">Thinking...</span>
            </div>
            
    <!-- Error message -->
            <div :if={message.role == :error} class="bg-red-50 border border-red-200 rounded-lg p-3">
              <p class="text-red-700 text-sm">{message.content}</p>
            </div>
          </div>
        <% else %>
          <!-- History tab -->
          <div :if={Enum.empty?(@chat_history)} class="text-center py-8 text-gray-400">
            <p>No conversation history yet.</p>
          </div>
          <div :for={entry <- @chat_history} class="border-b border-gray-100 pb-3 mb-3 last:border-0">
            <p class="text-sm text-gray-800 font-medium truncate">{entry.question}</p>
            <p class="text-xs text-gray-400 mt-1">{entry.timestamp}</p>
          </div>
        <% end %>
      </div>
      
    <!-- Contact Tag Dropdown -->
      <div :if={@show_contact_dropdown} class="px-6 pb-2">
        <div class="border border-gray-200 rounded-lg bg-white shadow-lg max-h-40 overflow-y-auto">
          <div :if={@contact_search_loading} class="px-3 py-2 text-sm text-gray-500">
            Searching contacts...
          </div>
          <div
            :if={!@contact_search_loading && Enum.empty?(@contact_results)}
            class="px-3 py-2 text-sm text-gray-500"
          >
            No contacts found. Type more to search.
          </div>
          <button
            :for={contact <- @contact_results}
            type="button"
            phx-click="tag_contact"
            phx-value-id={contact.id}
            phx-value-name={"#{contact.firstname} #{contact.lastname}"}
            phx-value-provider={contact[:provider] || "unknown"}
            phx-target={@myself}
            class="w-full text-left px-3 py-2 hover:bg-gray-50 flex items-center gap-2 text-sm border-b border-gray-50 last:border-0"
          >
            <div class="rounded-full bg-gray-200 w-6 h-6 flex items-center justify-center text-[10px] font-semibold text-gray-700 flex-shrink-0">
              {String.at(contact.firstname || "", 0)}{String.at(contact.lastname || "", 0)}
            </div>
            <div>
              <span class="font-medium">{contact.firstname} {contact.lastname}</span>
              <span :if={contact[:provider]} class="text-xs text-gray-400 ml-1">
                ({contact[:provider]})
              </span>
            </div>
          </button>
        </div>
      </div>
      
    <!-- Input Area -->
      <div class="p-4 border-t border-gray-100 bg-white pb-8">
        <form phx-submit="send_message" phx-target={@myself} class="relative">
          <div class={[
            "border rounded-2xl p-3 shadow-sm bg-white relative transition-colors",
            @input_focused && "border-blue-500",
            !@input_focused && "border-gray-300"
          ]}>
            <button
              type="button"
              phx-click="toggle_add_context"
              phx-target={@myself}
              class="flex items-center gap-1.5 text-xs text-gray-500 border border-gray-200 rounded px-2 py-1 hover:bg-gray-50 transition-colors mb-2"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="w-3.5 h-3.5"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M12 9v6m3-3H9m12 0a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
              Add context
            </button>
            
    <!-- Tagged contact capsules (shown after selecting a contact) -->
            <div :if={Enum.any?(@tagged_contacts)} class="flex flex-wrap gap-1.5 mb-2">
              <span
                :for={tc <- @tagged_contacts}
                class="inline-flex items-center gap-1.5 pl-0.5 pr-1.5 py-0.5 bg-chat-bubble rounded-full text-sm"
              >
                <div class="relative flex-shrink-0">
                  <span class={[
                    "rounded-full text-white w-[18px] h-[18px] inline-flex items-center justify-center text-[9px] font-bold",
                    ChatHelpers.avatar_bg_class(tc.provider)
                  ]}>
                    {ChatHelpers.contact_initials(tc.name)}
                  </span>
                  <span
                    :if={tc.provider != "unknown"}
                    class="absolute -bottom-0.5 -right-0.5 rounded-full w-[9px] h-[9px] border border-white flex items-center justify-center bg-gray-100"
                  >
                    <.source_icon type={tc.provider} class="w-[5px] h-[5px]" />
                  </span>
                </div>
                <span class="font-medium text-gray-900 text-[13px]">{tc.name}</span>
                <button
                  type="button"
                  phx-click="remove_tag"
                  phx-value-id={tc.id}
                  phx-target={@myself}
                  class="text-gray-400 hover:text-gray-600 ml-0.5 p-0.5 rounded-full hover:bg-gray-200"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="2.5"
                    stroke="currentColor"
                    class="w-3 h-3"
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </span>
            </div>

            <textarea
              id="chat-input"
              name="message"
              phx-keyup="chat_keyup"
              phx-focus="input_focus"
              phx-blur="input_blur"
              phx-target={@myself}
              phx-debounce="100"
              phx-hook="ChatInput"
              class="w-full text-[15px] text-gray-600 placeholder-gray-400 border-0 focus:ring-0 p-0 resize-none min-h-[40px]"
              placeholder="Ask anything about your meetings"
              rows="2"
              disabled={@answering}
            >{@draft}</textarea>

            <div class="flex items-center justify-between mt-2">
              <div class="flex items-center gap-1">
                <span class="text-[11px] text-gray-400 font-medium mr-1">Sources</span>
                <div class="flex -space-x-1">
                  <span class="bg-gray-100 rounded-full w-4 h-4 inline-flex items-center justify-center z-40 border border-white">
                    <.source_icon type={:jump} class="w-2.5 h-2.5" />
                  </span>
                  <span class="bg-gray-100 rounded-full w-4 h-4 inline-flex items-center justify-center z-30 border border-white">
                    <.source_icon type={:meeting} class="w-2.5 h-2.5" />
                  </span>
                  <span
                    :if={@has_hubspot}
                    class="bg-gray-100 rounded-full w-4 h-4 inline-flex items-center justify-center z-20 border border-white"
                  >
                    <.source_icon type={:hubspot} class="w-2.5 h-2.5" />
                  </span>
                  <span
                    :if={@has_salesforce}
                    class="bg-gray-100 rounded-full w-4 h-4 inline-flex items-center justify-center z-10 border border-white"
                  >
                    <.source_icon type={:salesforce} class="w-2.5 h-2.5" />
                  </span>
                </div>
              </div>
              <button
                type="submit"
                disabled={@answering || String.trim(@draft) == ""}
                class={[
                  "rounded-lg p-1.5 transition-colors",
                  String.trim(@draft) != "" && !@answering &&
                    "bg-blue-500 hover:bg-blue-600 text-white",
                  (String.trim(@draft) == "" || @answering) && "bg-gray-100 text-gray-400"
                ]}
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="w-5 h-5"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M4.5 10.5 12 3m0 0 7.5 7.5M12 3v18"
                  />
                </svg>
              </button>
            </div>
          </div>
        </form>
      </div>
    </div>
    """
  end

  # Function component: renders message text with inline contact capsules
  defp message_content(assigns) do
    segments =
      ChatHelpers.parse_content_segments(assigns.content, assigns.contacts || [], assigns.mode)

    assigns = assign(assigns, :segments, segments)

    ~H"""
    <%= for segment <- @segments do %>
      <%= if segment.type == :contact do %>
        <span
          class={[
            "inline-flex items-center gap-1.5 pl-1 pr-2.5 py-1 rounded-full whitespace-nowrap mx-0.5 transition-all text-gray-900 shrink-0",
            @mode == :user && "bg-white border border-gray-100 shadow-sm",
            @mode == :assistant && "bg-chat-bubble"
          ]}
          style="display: inline-flex !important; vertical-align: middle; line-height: 1; height: 28px; width: fit-content; position: relative; top: -1px;"
        >
          <span class="relative flex-shrink-0 flex items-center justify-center w-5 h-5">
            <span class={[
              "rounded-full text-white w-5 h-5 inline-flex items-center justify-center text-[10px] font-bold flex-shrink-0",
              ChatHelpers.avatar_bg_class(segment.provider)
            ]}>
              {segment.initials}
            </span><span
              :if={segment.provider != "unknown"}
              class={[
                "absolute -bottom-0.5 -right-0.5 rounded-full w-[10px] h-[10px] border border-white flex items-center justify-center overflow-hidden bg-gray-100"
              ]}
            ><.source_icon type={segment.provider} class="w-[6px] h-[6px]" /></span>
          </span><span class="font-semibold text-[13px] leading-none mb-[0.5px] whitespace-nowrap"><%= segment.name %></span>
        </span>
      <% else %>
        <span class="inline-block align-middle whitespace-pre-wrap">{segment.text}</span>
      <% end %>
    <% end %>
    """
  end

  @impl true
  def update(assigns, socket) do
    has_hubspot =
      case assigns[:current_user] do
        nil -> false
        user -> Accounts.get_user_hubspot_credential(user.id) != nil
      end

    has_salesforce =
      case assigns[:current_user] do
        nil -> false
        user -> Accounts.get_user_salesforce_credential(user.id) != nil
      end

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:messages, fn -> [] end)
      |> assign_new(:chat_history, fn -> [] end)
      |> assign_new(:draft, fn -> "" end)
      |> assign_new(:active_tab, fn -> "chat" end)
      |> assign_new(:answering, fn -> false end)
      |> assign_new(:input_focused, fn -> false end)
      |> assign_new(:tagged_contacts, fn -> [] end)
      |> assign_new(:show_contact_dropdown, fn -> false end)
      |> assign_new(:contact_results, fn -> [] end)
      |> assign_new(:contact_search_loading, fn -> false end)
      |> assign_new(:conversation_contacts, fn -> [] end)
      |> assign(:has_hubspot, has_hubspot)
      |> assign(:has_salesforce, has_salesforce)
      |> maybe_append_ai_response(assigns)

    {:ok, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    {:noreply,
     assign(socket,
       messages: [],
       draft: "",
       tagged_contacts: [],
       conversation_contacts: [],
       active_tab: "chat"
     )}
  end

  @impl true
  def handle_event("input_focus", _params, socket) do
    {:noreply, assign(socket, input_focused: true)}
  end

  @impl true
  def handle_event("input_blur", _params, socket) do
    {:noreply, assign(socket, input_focused: false)}
  end

  @impl true
  def handle_event("chat_keyup", %{"key" => "Enter", "value" => _value} = _params, socket) do
    # Enter key handled by form submit
    {:noreply, socket}
  end

  @impl true
  def handle_event("chat_keyup", %{"value" => value}, socket) do
    # Sync tagged contacts: remove any whose @Name was deleted from the draft
    tagged_contacts =
      Enum.filter(socket.assigns.tagged_contacts, fn contact ->
        String.contains?(value, "@#{contact.name}")
      end)

    socket = assign(socket, draft: value, tagged_contacts: tagged_contacts)

    # Check for @mention trigger
    case ChatHelpers.detect_mention(value) do
      {:mention, query} when byte_size(query) >= 2 ->
        socket = assign(socket, show_contact_dropdown: true, contact_search_loading: true)
        send(self(), {:chat_contact_search, query, socket.assigns.id})
        {:noreply, socket}

      _ ->
        {:noreply, assign(socket, show_contact_dropdown: false)}
    end
  end

  @impl true
  def handle_event("tag_contact", %{"id" => id, "name" => name, "provider" => provider}, socket) do
    contact = %{id: id, name: String.trim(name), provider: provider}

    # Replace the @mention partial with @FullName in the draft (keeps it inline)
    draft = ChatHelpers.replace_last_mention(socket.assigns.draft, contact.name)

    tagged =
      if Enum.any?(socket.assigns.tagged_contacts, &(&1.id == id)),
        do: socket.assigns.tagged_contacts,
        else: socket.assigns.tagged_contacts ++ [contact]

    {:noreply,
     assign(socket,
       tagged_contacts: tagged,
       show_contact_dropdown: false,
       contact_results: [],
       draft: draft
     )}
  end

  @impl true
  def handle_event("remove_tag", %{"id" => id}, socket) do
    contact = Enum.find(socket.assigns.tagged_contacts, &(&1.id == id))
    tagged = Enum.reject(socket.assigns.tagged_contacts, &(&1.id == id))

    # Also remove @Name from draft if contact found
    draft =
      if contact do
        socket.assigns.draft
        |> String.replace("@#{contact.name}", "")
        |> String.replace(~r/\s{2,}/, " ")
        |> String.trim()
      else
        socket.assigns.draft
      end

    {:noreply, assign(socket, tagged_contacts: tagged, draft: draft)}
  end

  @impl true
  def handle_event("toggle_add_context", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, socket}
    else
      # Capture tagged contacts before clearing
      tagged_contacts_snapshot = socket.assigns.tagged_contacts

      user_message = %{
        role: :user,
        content: message,
        tagged_contacts: tagged_contacts_snapshot
      }

      loading_message = %{role: :loading, content: ""}

      messages = socket.assigns.messages ++ [user_message, loading_message]

      # Accumulate conversation contacts for rendering capsules in AI responses
      conv_contacts =
        (socket.assigns.conversation_contacts ++ tagged_contacts_snapshot)
        |> Enum.uniq_by(& &1.id)

      socket =
        assign(socket,
          messages: messages,
          draft: "",
          answering: true,
          conversation_contacts: conv_contacts,
          tagged_contacts: []
        )

      # Send async to parent to process the question
      send(self(), {:chat_question, message, tagged_contacts_snapshot, socket.assigns.id})

      {:noreply, socket}
    end
  end

  # --- Private helpers ---

  # Handle ai_response from parent LiveView
  defp maybe_append_ai_response(socket, %{ai_response: ai_response}) do
    updated_messages =
      socket.assigns.messages
      |> Enum.reject(fn msg -> msg.role == :loading end)
      |> Kernel.++([ai_response])

    assign(socket, messages: updated_messages)
  end

  defp maybe_append_ai_response(socket, _assigns), do: socket

  # Renders source icon for CRM providers
  defp source_icon(assigns) do
    assigns = assign_new(assigns, :class, fn -> "w-full h-full" end)

    ~H"""
    <%= case ChatHelpers.entry_type(@type) do %>
      <% :jump -> %>
        <img src="/images/jump-icon.png" class={@class} alt="Jump" />
      <% :salesforce -> %>
        <img src="/images/salesforce.webp" class={@class} alt="Salesforce" />
      <% :hubspot -> %>
        <img src="/images/hubspot.webp" class={@class} alt="HubSpot" />
      <% :meeting -> %>
        <img src="/images/gmail.webp" class={@class} alt="Meeting" />
      <% :gmail -> %>
        <img src="/images/gmail.webp" class={@class} alt="Gmail" />
      <% :emoney -> %>
        <img src="/images/emoney.webp" class={@class} alt="eMoney" />
      <% _ -> %>
    <% end %>
    """
  end
end
