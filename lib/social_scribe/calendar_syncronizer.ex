defmodule SocialScribe.CalendarSyncronizer do
  @moduledoc """
  Fetches and syncs Google Calendar events.
  """

  require Logger

  alias SocialScribe.GoogleCalendarApi
  alias SocialScribe.Calendar
  alias SocialScribe.Accounts
  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.TokenRefresherApi

  @doc """
  Syncs events for a user.

  Currently, only works for the primary calendar and for meeting links that are either on the hangoutLink or location field.

  #TODO: Add support for syncing only since the last sync time and record sync attempts
  """
  def sync_events_for_user(user) do
    user
    |> Accounts.list_user_credentials(provider: "google")
    |> Task.async_stream(&fetch_and_sync_for_credential/1, ordered: false, on_timeout: :kill_task)
    |> Stream.run()

    {:ok, :sync_complete}
  end

  defp fetch_and_sync_for_credential(%UserCredential{} = credential) do
    with {:ok, token} <- ensure_valid_token(credential),
         {:ok, %{"items" => items}} <-
           GoogleCalendarApi.list_events(
             token,
             DateTime.utc_now() |> Timex.beginning_of_day() |> Timex.shift(days: -1),
             DateTime.utc_now() |> Timex.end_of_day() |> Timex.shift(days: 7),
             "primary"
           ),
         :ok <- sync_items(items, credential.user_id, credential.id) do
      :ok
    else
      {:error, reason} ->
        # Log errors but don't crash the sync for other accounts
        Logger.error("Failed to sync credential #{credential.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_valid_token(%UserCredential{} = credential) do
    if DateTime.compare(credential.expires_at || DateTime.utc_now(), DateTime.utc_now()) == :lt do
      # Check if we have a refresh token before attempting to refresh
      if is_nil(credential.refresh_token) do
        {:error, :no_refresh_token}
      else
        case TokenRefresherApi.refresh_token(credential.refresh_token) do
          {:ok, new_token_data} ->
            {:ok, updated_credential} =
              Accounts.update_credential_tokens(credential, new_token_data)

            {:ok, updated_credential.token}

          {:error, reason} ->
            {:error, {:refresh_failed, reason}}
        end
      end
    else
      {:ok, credential.token}
    end
  end

  defp sync_items(items, user_id, credential_id) do
    Enum.each(items, fn item ->
      try do
        parsed_event = parse_google_event(item, user_id, credential_id)

        # Only sync meetings that have a detected meeting platform
        if parsed_event.meeting_platform do
          Calendar.create_or_update_calendar_event(parsed_event)
        end
      rescue
        e ->
          Logger.error(
            "Failed to sync calendar event #{inspect(item["id"])}: #{inspect(e)}"
          )
      end
    end)

    :ok
  end

  defp parse_google_event(item, user_id, credential_id) do
    start_time_str = Map.get(item["start"], "dateTime", Map.get(item["start"], "date"))
    end_time_str = Map.get(item["end"], "dateTime", Map.get(item["end"], "date"))

    # Detect meeting platform and extract meeting URL
    {meeting_platform, meeting_url} = detect_meeting_platform_and_url(item)

    %{
      google_event_id: item["id"],
      summary: Map.get(item, "summary", "No Title"),
      description: Map.get(item, "description"),
      location: Map.get(item, "location"),
      html_link: Map.get(item, "htmlLink"),
      hangout_link: Map.get(item, "hangoutLink", Map.get(item, "location")),
      meeting_platform: meeting_platform,
      meeting_url: meeting_url,
      status: Map.get(item, "status"),
      start_time: to_utc_datetime(start_time_str),
      end_time: to_utc_datetime(end_time_str),
      user_id: user_id,
      user_credential_id: credential_id
    }
  end

  # Detects the meeting platform and extracts the meeting URL from a Google Calendar event.
  # 
  # Returns a tuple {platform, url} where:
  # - platform is one of: "google_meet", "zoom", "microsoft_teams", or nil
  # - url is the meeting URL string or nil
  # 
  # Checks multiple fields in this order:
  # 1. hangoutLink (Google Meet)
  # 2. location field (for Zoom, Teams, or other meeting links)
  # 3. description field (for embedded meeting links)
  defp detect_meeting_platform_and_url(item) do
    # Check hangoutLink first (Google Meet)
    if hangout_link = Map.get(item, "hangoutLink") do
      {"google_meet", hangout_link}
    else
      # Check location and description for other platforms
      location = Map.get(item, "location", "")
      description = Map.get(item, "description", "")
      
      cond do
        # Zoom detection - various patterns
        zoom_url = extract_zoom_url(location) || extract_zoom_url(description) ->
          {"zoom", zoom_url}
        
        # Microsoft Teams detection
        teams_url = extract_teams_url(location) || extract_teams_url(description) ->
          {"microsoft_teams", teams_url}
        
        # Google Meet in location/description (fallback)
        meet_url = extract_google_meet_url(location) || extract_google_meet_url(description) ->
          {"google_meet", meet_url}
        
        true ->
          {nil, nil}
      end
    end
  end

  # Extract Zoom URL from text
  # Matches patterns like:
  # - https://zoom.us/j/123456789
  # - https://company.zoom.us/j/123456789?pwd=abc123
  # Uses [^\s<>"'] to avoid capturing HTML tags and attributes
  defp extract_zoom_url(text) when is_binary(text) do
    case Regex.run(~r/https?:\/\/[^\s<>"']*\.?zoom\.us\/[^\s<>"']+/i, text) do
      [url | _] -> url
      _ -> nil
    end
  end
  defp extract_zoom_url(_), do: nil

  # Extract Microsoft Teams URL from text
  # Matches patterns like:
  # - https://teams.microsoft.com/l/meetup-join/...
  # - https://teams.live.com/meet/...
  # Uses [^\s<>"'] to avoid capturing HTML tags and attributes
  defp extract_teams_url(text) when is_binary(text) do
    case Regex.run(~r/https?:\/\/teams\.(microsoft\.com|live\.com)\/[^\s<>"']+/i, text) do
      [url | _] -> url
      _ -> nil
    end
  end
  defp extract_teams_url(_), do: nil

  # Extract Google Meet URL from text (when not in hangoutLink)
  # Matches patterns like:
  # - https://meet.google.com/abc-defg-hij
  # Uses [^\s<>"'] to avoid capturing HTML tags and attributes
  defp extract_google_meet_url(text) when is_binary(text) do
    case Regex.run(~r/https?:\/\/meet\.google\.com\/[^\s<>"']+/i, text) do
      [url | _] -> url
      _ -> nil
    end
  end
  defp extract_google_meet_url(_), do: nil

  defp to_utc_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _offset} ->
        datetime

      _ ->
        nil
    end
  end
end
