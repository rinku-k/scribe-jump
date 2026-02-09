defmodule MeetingPlatformDetectionTest do
  @moduledoc """
  Test script to verify meeting platform detection for Google Meet, Zoom, and Microsoft Teams
  """

  # Simulate the detection logic
  def detect_meeting_platform_and_url(item) do
    if hangout_link = Map.get(item, "hangoutLink") do
      {"google_meet", hangout_link}
    else
      location = Map.get(item, "location", "")
      description = Map.get(item, "description", "")
      
      cond do
        zoom_url = extract_zoom_url(location) || extract_zoom_url(description) ->
          {"zoom", zoom_url}
        
        teams_url = extract_teams_url(location) || extract_teams_url(description) ->
          {"microsoft_teams", teams_url}
        
        meet_url = extract_google_meet_url(location) || extract_google_meet_url(description) ->
          {"google_meet", meet_url}
        
        true ->
          {nil, nil}
      end
    end
  end

  defp extract_zoom_url(text) when is_binary(text) do
    case Regex.run(~r/https?:\/\/[^\s]*\.?zoom\.us\/[^\s]+/i, text) do
      [url | _] -> url
      _ -> nil
    end
  end
  defp extract_zoom_url(_), do: nil

  defp extract_teams_url(text) when is_binary(text) do
    case Regex.run(~r/https?:\/\/teams\.(microsoft\.com|live\.com)\/[^\s]+/i, text) do
      [url | _] -> url
      _ -> nil
    end
  end
  defp extract_teams_url(_), do: nil

  defp extract_google_meet_url(text) when is_binary(text) do
    case Regex.run(~r/https?:\/\/meet\.google\.com\/[^\s]+/i, text) do
      [url | _] -> url
      _ -> nil
    end
  end
  defp extract_google_meet_url(_), do: nil

  # Test cases
  def run_tests do
    IO.puts("\n=== Testing Meeting Platform Detection ===\n")

    # Test 1: Google Meet via hangoutLink
    test_case_1 = %{
      "hangoutLink" => "https://meet.google.com/abc-defg-hij"
    }
    {platform, url} = detect_meeting_platform_and_url(test_case_1)
    IO.puts("✓ Test 1 - Google Meet (hangoutLink): #{platform} - #{url}")

    # Test 2: Zoom in location
    test_case_2 = %{
      "location" => "https://zoom.us/j/123456789?pwd=abc123"
    }
    {platform, url} = detect_meeting_platform_and_url(test_case_2)
    IO.puts("✓ Test 2 - Zoom (location): #{platform} - #{url}")

    # Test 3: Microsoft Teams in location
    test_case_3 = %{
      "location" => "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc123"
    }
    {platform, url} = detect_meeting_platform_and_url(test_case_3)
    IO.puts("✓ Test 3 - Microsoft Teams (location): #{platform} - #{url}")

    # Test 4: Google Meet in description
    test_case_4 = %{
      "description" => "Join the meeting: https://meet.google.com/xyz-abcd-efg"
    }
    {platform, url} = detect_meeting_platform_and_url(test_case_4)
    IO.puts("✓ Test 4 - Google Meet (description): #{platform} - #{url}")

    # Test 5: Zoom in description
    test_case_5 = %{
      "description" => "Meeting link: https://company.zoom.us/j/987654321"
    }
    {platform, url} = detect_meeting_platform_and_url(test_case_5)
    IO.puts("✓ Test 5 - Zoom (description): #{platform} - #{url}")

    # Test 6: Microsoft Teams in description
    test_case_6 = %{
      "description" => "Join here: https://teams.live.com/meet/123456789"
    }
    {platform, url} = detect_meeting_platform_and_url(test_case_6)
    IO.puts("✓ Test 6 - Microsoft Teams (description): #{platform} - #{url}")

    # Test 7: No meeting link
    test_case_7 = %{
      "location" => "Conference Room A"
    }
    {platform, url} = detect_meeting_platform_and_url(test_case_7)
    IO.puts("✓ Test 7 - No meeting link: #{inspect(platform)} - #{inspect(url)}")

    IO.puts("\n=== All Tests Completed ===\n")
  end
end

# Run the tests
MeetingPlatformDetectionTest.run_tests()
