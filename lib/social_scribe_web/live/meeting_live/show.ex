defmodule SocialScribeWeb.MeetingLive.Show do
  use SocialScribeWeb, :live_view

  import SocialScribeWeb.PlatformLogo
  import SocialScribeWeb.ClipboardButton
  import SocialScribeWeb.ModalComponents, only: [hubspot_modal: 1]

  alias SocialScribe.Meetings
  alias SocialScribe.Automations
  alias SocialScribe.Accounts
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.HubspotSuggestions
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi
  alias SocialScribe.SalesforceSuggestions
  alias SocialScribe.AIContentGeneratorApi

  @impl true
  def mount(%{"id" => meeting_id}, _session, socket) do
    timezone = (connected?(socket) && get_connect_params(socket)["timezone"]) || "UTC"
    meeting = Meetings.get_meeting_with_details(meeting_id)

    user_has_automations =
      Automations.list_active_user_automations(socket.assigns.current_user.id)
      |> length()
      |> Kernel.>(0)

    automation_results = Automations.list_automation_results_for_meeting(meeting_id)

    if meeting.calendar_event.user_id != socket.assigns.current_user.id do
      socket =
        socket
        |> put_flash(:error, "You do not have permission to view this meeting.")
        |> redirect(to: ~p"/dashboard/meetings")

      # Note: mount/3 must return {:ok, socket} even when redirecting
      {:ok, socket}
    else
      hubspot_credential = Accounts.get_user_hubspot_credential(socket.assigns.current_user.id)
      salesforce_credential = Accounts.get_user_salesforce_credential(socket.assigns.current_user.id)

      socket =
        socket
        |> assign(:page_title, "Meeting Details: #{meeting.title}")
        |> assign(:meeting, meeting)
        |> assign(:automation_results, automation_results)
        |> assign(:user_has_automations, user_has_automations)
        |> assign(:hubspot_credential, hubspot_credential)
        |> assign(:salesforce_credential, salesforce_credential)
        |> assign(:show_chat, false)
        |> assign(:timezone, timezone)
        |> assign(
          :follow_up_email_form,
          to_form(%{
            "follow_up_email" => ""
          })
        )

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"automation_result_id" => automation_result_id}, _uri, socket) do
    automation_result = Automations.get_automation_result!(automation_result_id)
    automation = Automations.get_automation!(automation_result.automation_id)

    socket =
      socket
      |> assign(:automation_result, automation_result)
      |> assign(:automation, automation)

    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_chat", _params, socket) do
    {:noreply, update(socket, :show_chat, &(!&1))}
  end

  @impl true
  def handle_event("transcript_time_clicked", _params, socket) do
    {:noreply, put_flash(socket, :info, "Currently this feature is not implemented")}
  end

  @impl true
  def handle_event("validate-follow-up-email", params, socket) do
    socket =
      socket
      |> assign(:follow_up_email_form, to_form(params))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:hubspot_search, query, credential}, socket) do
    case HubspotApi.search_contacts(credential, query) do
      {:ok, contacts} ->
        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          contacts: contacts,
          searching: false
        )

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          error: "Failed to search contacts: #{inspect(reason)}",
          searching: false
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:generate_suggestions, contact, meeting, _credential}, socket) do
    case HubspotSuggestions.generate_suggestions_from_meeting(meeting) do
      {:ok, suggestions} ->
        merged = HubspotSuggestions.merge_with_contact(suggestions, contact)

        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          step: :suggestions,
          suggestions: merged,
          loading: false
        )

      {:error, reason} ->
        {message, retry_after_seconds} = hubspot_suggestions_error_message(reason)

        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          error: message,
          retry_after_seconds: retry_after_seconds,
          loading: false
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:apply_hubspot_updates, updates, contact, credential}, socket) do
    case HubspotApi.update_contact(credential, contact.id, updates) do
      {:ok, _updated_contact} ->
        socket =
          socket
          |> put_flash(:info, "Successfully updated #{map_size(updates)} field(s) in HubSpot")
          |> push_patch(to: ~p"/dashboard/meetings/#{socket.assigns.meeting}")

        {:noreply, socket}

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          error: "Failed to update contact: #{inspect(reason)}",
          loading: false
        )

        {:noreply, socket}
    end
  end

  # === Salesforce message handlers ===

  @impl true
  def handle_info({:salesforce_search, query, credential}, socket) do
    case SalesforceApi.search_contacts(credential, query) do
      {:ok, contacts} ->
        send_update(SocialScribeWeb.MeetingLive.SalesforceModalComponent,
          id: "salesforce-modal",
          contacts: contacts,
          searching: false
        )

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.SalesforceModalComponent,
          id: "salesforce-modal",
          error: "Failed to search contacts: #{inspect(reason)}",
          searching: false
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:generate_salesforce_suggestions, contact, meeting, _credential}, socket) do
    case SalesforceSuggestions.generate_suggestions_from_meeting(meeting) do
      {:ok, suggestions} ->
        merged = SalesforceSuggestions.merge_with_contact(suggestions, contact)

        send_update(SocialScribeWeb.MeetingLive.SalesforceModalComponent,
          id: "salesforce-modal",
          step: :suggestions,
          suggestions: merged,
          loading: false
        )

      {:error, reason} ->
        {message, retry_after_seconds} = salesforce_suggestions_error_message(reason)

        send_update(SocialScribeWeb.MeetingLive.SalesforceModalComponent,
          id: "salesforce-modal",
          error: message,
          retry_after_seconds: retry_after_seconds,
          loading: false
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:apply_salesforce_updates, updates, contact, credential}, socket) do
    case SalesforceApi.update_contact(credential, contact.id, updates) do
      {:ok, _updated_contact} ->
        socket =
          socket
          |> put_flash(
            :info,
            "Successfully updated #{map_size(updates)} field(s) in Salesforce"
          )
          |> push_patch(to: ~p"/dashboard/meetings/#{socket.assigns.meeting}")

        {:noreply, socket}

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.SalesforceModalComponent,
          id: "salesforce-modal",
          error: "Failed to update contact: #{inspect(reason)}",
          loading: false
        )

        {:noreply, socket}
    end
  end

  # === Chat message handlers ===

  @impl true
  def handle_info({:chat_contact_search, query, component_id}, socket) do
    results = search_contacts_for_chat(socket, query)

    send_update(SocialScribeWeb.Chat.ChatComponent,
      id: component_id,
      contact_results: results,
      contact_search_loading: false,
      show_contact_dropdown: true
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:chat_question, question, tagged_contacts, component_id}, socket) do
    meeting = socket.assigns.meeting

    # Build contact data context from tagged contacts
    contact_data =
      tagged_contacts
      |> Enum.flat_map(fn tc ->
        case tc.provider do
          "hubspot" ->
            case socket.assigns[:hubspot_credential] do
              nil -> []
              cred ->
                case HubspotApi.get_contact(cred, tc.id) do
                  {:ok, contact} -> [{"HubSpot - #{tc.name}", contact}]
                  _ -> []
                end
            end

          "salesforce" ->
            case socket.assigns[:salesforce_credential] do
              nil -> []
              cred ->
                case SalesforceApi.get_contact(cred, tc.id) do
                  {:ok, contact} -> [{"Salesforce - #{tc.name}", contact}]
                  _ -> []
                end
            end

          _ ->
            []
        end
      end)
      |> Enum.into(%{})

    case AIContentGeneratorApi.answer_contact_question(question, contact_data, meeting) do
      {:ok, %{answer: answer, sources: sources}} ->
        send_update(SocialScribeWeb.Chat.ChatComponent,
          id: component_id,
          ai_response: %{role: :assistant, content: answer, sources: sources},
          answering: false
        )

      {:error, reason} ->
        send_update(SocialScribeWeb.Chat.ChatComponent,
          id: component_id,
          ai_response: %{role: :error, content: "Sorry, I couldn't process your question: #{inspect(reason)}"},
          answering: false
        )
    end

    {:noreply, socket}
  end

  defp search_contacts_for_chat(socket, query) do
    hubspot_results =
      case socket.assigns[:hubspot_credential] do
        nil ->
          []

        cred ->
          case HubspotApi.search_contacts(cred, query) do
            {:ok, contacts} -> Enum.map(contacts, &Map.put(&1, :provider, "hubspot"))
            _ -> []
          end
      end

    salesforce_results =
      case socket.assigns[:salesforce_credential] do
        nil ->
          []

        cred ->
          case SalesforceApi.search_contacts(cred, query) do
            {:ok, contacts} -> Enum.map(contacts, &Map.put(&1, :provider, "salesforce"))
            _ -> []
          end
      end

    (hubspot_results ++ salesforce_results) |> Enum.take(8)
  end


  defp hubspot_suggestions_error_message({:api_error, 429, error_body}) when is_map(error_body) do
    retry_after_seconds = parse_gemini_retry_delay_seconds(error_body)

    base =
      "Gemini API quota/rate limit exceeded while generating suggestions. " <>
        "Please wait#{if(retry_after_seconds, do: " ~#{retry_after_seconds}s", else: "")} " <>
        "and try again. If this keeps happening, check billing/quota for your GEMINI_API_KEY."

    {base, retry_after_seconds}
  end

  defp hubspot_suggestions_error_message({:api_error, status, _error_body}) do
    {"Gemini API error (HTTP #{status}) while generating suggestions. Please try again.", nil}
  end

  defp hubspot_suggestions_error_message({:config_error, message}) when is_binary(message) do
    {message, nil}
  end

  defp hubspot_suggestions_error_message(reason) do
    {"Failed to generate suggestions. Please try again. (#{inspect(reason)})", nil}
  end

  defp parse_gemini_retry_delay_seconds(error_body) when is_map(error_body) do
    details = get_in(error_body, ["error", "details"])

    with details when is_list(details) <- details,
         %{"retryDelay" => retry_delay} <-
           Enum.find(details, fn d -> is_map(d) and d["@type"] == "type.googleapis.com/google.rpc.RetryInfo" end),
         retry_delay when is_binary(retry_delay) <- retry_delay,
         [seconds_str] <- Regex.run(~r/(\d+)s/, retry_delay, capture: :all_but_first),
         {seconds, ""} <- Integer.parse(seconds_str) do
      seconds
    else
      _ -> nil
    end
  end

  defp format_duration(nil), do: "N/A"

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)

    cond do
      minutes > 0 && remaining_seconds > 0 -> "#{minutes} min #{remaining_seconds} sec"
      minutes > 0 -> "#{minutes} min"
      seconds > 0 -> "#{seconds} sec"
      true -> "Less than a second"
    end
  end

  attr :meeting_transcript, :map, required: true
  attr :meeting_participants, :list, default: []

  defp transcript_content(assigns) do
    has_transcript =
      assigns.meeting_transcript &&
        assigns.meeting_transcript.content &&
        Map.get(assigns.meeting_transcript.content, "data") &&
        Enum.any?(Map.get(assigns.meeting_transcript.content, "data"))

    # Map recall_participant_id -> name so we can resolve speaker_id in transcript segments
    participants = assigns.meeting_participants || []
    participant_id_to_name =
      participants
      |> Enum.map(fn p -> {to_string(p.recall_participant_id), p.name || "Unknown Participant"} end)
      |> Map.new()

    assigns =
      assigns
      |> assign(:has_transcript, has_transcript)
      |> assign(:participant_id_to_name, participant_id_to_name)

    ~H"""
    <div class="bg-white shadow-xl rounded-lg p-6 md:p-8">
      <h2 class="text-2xl font-semibold mb-4 text-slate-700">
        Meeting Transcript
      </h2>
      <div class="prose prose-sm sm:prose max-w-none h-96 overflow-y-auto pr-2">
        <%= if @has_transcript do %>
          <div :for={segment <- @meeting_transcript.content["data"]} class="mb-3">
            <p>
              <span class="font-semibold text-indigo-600">
                {speaker_display_name(segment, @participant_id_to_name)}:
              </span>
              {segment_words_text(segment)}
            </p>
          </div>
        <% else %>
          <p class="text-slate-500">
            Transcript not available for this meeting.
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  defp speaker_display_name(segment, participant_id_to_name) do
    # Segment may have string or atom keys (stored JSON).
    # Recall API can use "speaker"/"speaker_id" or "participant" (id or %{id, name}) per segment.
    speaker = segment["speaker"] || segment[:speaker]
    speaker_id = segment["speaker_id"] || segment[:speaker_id]
    participant = segment["participant"] || segment[:participant]

    participant_id = participant_id_from_segment(participant)
    participant_name = participant_name_from_segment(participant)

    cond do
      is_binary(speaker) and speaker != "" -> speaker
      is_binary(participant_name) and participant_name != "" -> participant_name
      speaker_id != nil -> Map.get(participant_id_to_name, to_string(speaker_id), "Unknown Speaker")
      participant_id != nil -> Map.get(participant_id_to_name, to_string(participant_id), "Unknown Speaker")
      true -> "Unknown Speaker"
    end
  end

  defp participant_id_from_segment(nil), do: nil
  defp participant_id_from_segment(id) when is_integer(id) or is_binary(id), do: id
  defp participant_id_from_segment(participant) when is_map(participant) do
    participant["id"] || participant[:id]
  end
  defp participant_id_from_segment(_), do: nil

  defp participant_name_from_segment(nil), do: nil
  defp participant_name_from_segment(participant) when is_map(participant) do
    name = participant["name"] || participant[:name]
    if is_binary(name) and name != "", do: name, else: nil
  end
  defp participant_name_from_segment(_), do: nil

  defp segment_words_text(segment) do
    words = segment["words"] || segment[:words] || []
    Enum.map_join(words, " ", fn w -> w["text"] || w[:text] || "" end)
  end



  defp salesforce_suggestions_error_message({:api_error, 429, error_body})
       when is_map(error_body) do
    retry_after_seconds = parse_gemini_retry_delay_seconds(error_body)

    base =
      "Gemini API quota/rate limit exceeded while generating suggestions. " <>
        "Please wait#{if(retry_after_seconds, do: " ~#{retry_after_seconds}s", else: "")} " <>
        "and try again."

    {base, retry_after_seconds}
  end

  defp salesforce_suggestions_error_message({:api_error, status, _error_body}) do
    {"Gemini API error (HTTP #{status}) while generating suggestions. Please try again.", nil}
  end

  defp salesforce_suggestions_error_message({:config_error, message}) when is_binary(message) do
    {message, nil}
  end

  defp salesforce_suggestions_error_message(reason) do
    {"Failed to generate suggestions. Please try again. (#{inspect(reason)})", nil}
  end
end
