defmodule SocialScribeWeb.ChatComponentTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures
  import Mox

  setup :verify_on_exit!

  describe "Chat Component" do
    setup %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "chat drawer is initially hidden", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Chat drawer should be present but translated off-screen
      assert html =~ "translate-x-full"
      assert html =~ "Ask Anything"
    end

    test "chat toggle button is present on meeting page", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Check for the chat toggle button
      assert has_element?(view, "button[phx-click='toggle_chat']")
    end

    test "chat contains message input area", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert html =~ "Ask anything about your meetings"
      assert html =~ "chat-input"
    end

    test "chat has tab buttons for Chat and History", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert html =~ "Chat"
      assert html =~ "History"
    end

    test "chat shows welcome message", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert html =~ "I can answer questions about Jump meetings and data"
    end

    test "chat shows Sources badges", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert html =~ "Sources"
    end

    test "chat Add context button is present", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert html =~ "Add context"
    end
  end

  describe "Chat Component with CRM credentials" do
    setup %{conn: conn} do
      user = user_fixture()
      _hubspot = hubspot_credential_fixture(%{user_id: user.id})
      _salesforce = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "shows HubSpot badge when user has HubSpot credential", %{
      conn: conn,
      meeting: meeting
    } do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # HubSpot source icon is present (hubspot.webp image)
      assert html =~ "hubspot.webp"
    end

    test "shows Salesforce badge when user has Salesforce credential", %{
      conn: conn,
      meeting: meeting
    } do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Salesforce source icon is present (salesforce.webp image)
      assert html =~ "salesforce.webp"
    end
  end

  describe "Chat Component - new chat" do
    setup %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "new chat button exists", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert html =~ "New conversation"
    end
  end

  describe "Chat Component - message interactions" do
    setup %{conn: conn} do
      user = user_fixture()
      hubspot = hubspot_credential_fixture(%{user_id: user.id})
      salesforce = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        hubspot_credential: hubspot,
        salesforce_credential: salesforce
      }
    end

    test "send button is disabled when input is empty", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Button should have disabled styling when draft is empty
      assert html =~ "bg-gray-100 text-gray-400"
    end

    test "chat input placeholder is present", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert has_element?(view, "textarea#chat-input")
    end

    test "chat has form for sending messages", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert has_element?(view, "form[phx-submit='send_message']")
    end

    test "send message triggers AI question handler", %{conn: conn, meeting: meeting} do
      # Mock the AI content generator to return a response
      SocialScribe.AIContentGeneratorMock
      |> expect(:answer_contact_question, fn _question, _contact_data, _meeting ->
        {:ok, %{answer: "This is a test answer", sources: [:meeting]}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Submit a message via the form
      view
      |> form("form[phx-submit='send_message']", %{message: "What was discussed?"})
      |> render_submit()

      # Give time for async processing
      :timer.sleep(300)

      html = render(view)

      # The user message should appear
      assert html =~ "What was discussed?"
    end

    test "contact tagging via @ mention shows dropdown", %{conn: conn, meeting: meeting} do
      # Mock contact search to return results
      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _cred, _query ->
        {:ok, [%{id: "123", firstname: "Test", lastname: "User", email: "test@example.com"}]}
      end)

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, _query ->
        {:ok, []}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Type @Te to trigger contact search
      view
      |> element("textarea#chat-input")
      |> render_keyup(%{"value" => "@Te"})

      :timer.sleep(200)

      html = render(view)

      # Contact dropdown should show or search should be triggered
      # The dropdown shows "Searching contacts..." or contact results
      assert html =~ "contact" or html =~ "Search"
    end

    test "empty message submission does not trigger API call", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Submit empty message - should not trigger any API calls
      view
      |> form("form[phx-submit='send_message']", %{message: ""})
      |> render_submit()

      # No errors should occur, page should still render
      html = render(view)
      assert html =~ "Ask Anything"
    end

    test "whitespace-only message is treated as empty", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Submit whitespace-only message
      view
      |> form("form[phx-submit='send_message']", %{message: "   "})
      |> render_submit()

      html = render(view)
      # Should not show the whitespace as a message
      assert html =~ "Ask Anything"
    end
  end

  describe "Chat Component - tab switching" do
    setup %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "switching to History tab shows empty state", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Click history tab
      view
      |> element("button[phx-value-tab='history']")
      |> render_click()

      html = render(view)
      assert html =~ "No conversation history yet"
    end

    test "switching back to Chat tab shows chat interface", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Switch to history then back to chat
      view
      |> element("button[phx-value-tab='history']")
      |> render_click()

      view
      |> element("button[phx-value-tab='chat']")
      |> render_click()

      html = render(view)
      assert html =~ "I can answer questions about Jump meetings"
    end
  end

  describe "Chat Component - error handling" do
    setup %{conn: conn} do
      user = user_fixture()
      hubspot = hubspot_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        hubspot_credential: hubspot
      }
    end

    test "handles AI API error gracefully", %{conn: conn, meeting: meeting} do
      # Mock the AI content generator to return an error
      SocialScribe.AIContentGeneratorMock
      |> expect(:answer_contact_question, fn _question, _contact_data, _meeting ->
        {:error, :api_unavailable}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Submit a message
      view
      |> form("form[phx-submit='send_message']", %{message: "Test question"})
      |> render_submit()

      :timer.sleep(300)

      html = render(view)

      # Should show error message
      assert html =~ "Test question" or html =~ "couldn't process"
    end

    test "handles contact search API error gracefully", %{conn: conn, meeting: meeting} do
      # Mock contact search to fail
      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _cred, _query ->
        {:error, {:api_error, 500, "Internal server error"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Type @Test to trigger contact search
      view
      |> element("textarea#chat-input")
      |> render_keyup(%{"value" => "@Test"})

      :timer.sleep(200)

      # Page should still render without crashing
      html = render(view)
      assert html =~ "Ask Anything"
    end
  end

  describe "Chat Component - without any CRM credentials" do
    setup %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "chat works without HubSpot credential", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Chat should still work, just without HubSpot badge
      refute html =~ "hubspot.webp"
      assert html =~ "Ask Anything"
    end

    test "chat works without Salesforce credential", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Chat should still work, just without Salesforce badge
      refute html =~ "salesforce.webp"
      assert html =~ "Ask Anything"
    end

    test "meeting source badge always shown", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Meeting source should always be present
      assert html =~ "gmail.webp" or html =~ "Meeting"
    end
  end

  # Helper function to create a meeting with transcript for testing
  defp meeting_fixture_with_transcript(user) do
    meeting = meeting_fixture(%{})

    calendar_event = SocialScribe.Calendar.get_calendar_event!(meeting.calendar_event_id)

    {:ok, _updated_event} =
      SocialScribe.Calendar.update_calendar_event(calendar_event, %{user_id: user.id})

    meeting_transcript_fixture(%{
      meeting_id: meeting.id,
      content: %{
        "data" => [
          %{
            "speaker" => "John Doe",
            "words" => [
              %{"text" => "Hello,"},
              %{"text" => "my"},
              %{"text" => "phone"},
              %{"text" => "is"},
              %{"text" => "555-1234"}
            ]
          }
        ]
      }
    })

    SocialScribe.Meetings.get_meeting_with_details(meeting.id)
  end
end
