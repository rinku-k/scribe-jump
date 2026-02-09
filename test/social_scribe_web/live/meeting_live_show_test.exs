defmodule SocialScribeWeb.MeetingLiveShowTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures
  import SocialScribe.AutomationsFixtures
  import Mox

  setup :verify_on_exit!

  describe "MeetingLive.Show - basic rendering" do
    setup %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "renders meeting details page", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert html =~ meeting.title
    end

    test "shows meeting title", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert html =~ "Meeting Details"
    end

    test "shows transcript section", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert html =~ "Transcript" or html =~ "Hello"
    end

    test "shows chat toggle button", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert has_element?(view, "button[phx-click='toggle_chat']")
    end
  end

  describe "MeetingLive.Show - permission checks" do
    setup %{conn: conn} do
      user1 = user_fixture()
      user2 = user_fixture()
      meeting = meeting_fixture_with_transcript(user1)

      %{
        conn: log_in_user(conn, user2),
        user: user2,
        owner: user1,
        meeting: meeting
      }
    end

    test "redirects when user doesn't own the meeting", %{conn: conn, meeting: meeting} do
      # User2 trying to access User1's meeting should be redirected
      result = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Should redirect to meetings list
      assert {:error, {:redirect, %{to: path, flash: flash}}} = result
      assert path == "/dashboard/meetings"
      assert flash["error"] =~ "permission"
    end
  end

  describe "MeetingLive.Show - with CRM integrations" do
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

    test "shows HubSpot button when credential exists", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert html =~ "HubSpot" or html =~ "hubspot"
    end

    test "shows Salesforce button when credential exists", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert html =~ "Salesforce" or html =~ "salesforce"
    end

    test "can navigate to HubSpot modal", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      assert has_element?(view, "#hubspot-modal-wrapper")
    end

    test "can navigate to Salesforce modal", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      assert has_element?(view, "#salesforce-modal-wrapper")
    end
  end

  describe "MeetingLive.Show - without CRM integrations" do
    setup %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "does not show HubSpot button when no credential", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      refute html =~ "Update HubSpot Contact"
    end

    test "does not show Salesforce button when no credential", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      refute html =~ "Update Salesforce Contact"
    end
  end

  describe "MeetingLive.Show - toggle_chat event" do
    setup %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "toggle_chat shows and hides chat drawer", %{conn: conn, meeting: meeting} do
      {:ok, view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Initially hidden (translate-x-full)
      assert html =~ "translate-x-full"

      # Toggle chat using first toggle button (Ask AI button) - more specific selector
      view
      |> element("button[phx-click='toggle_chat']", "Ask AI")
      |> render_click()

      html = render(view)
      # Chat should be visible (translate-x-0)
      assert html =~ "translate-x-0"
    end
  end

  describe "MeetingLive.Show - with automations" do
    setup %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)
      automation = automation_fixture(%{user_id: user.id, is_active: true})

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        automation: automation
      }
    end

    test "shows automation section when user has automations", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Page should render successfully even with automations
      assert html =~ meeting.title
    end
  end

  describe "MeetingLive.Show - follow-up email" do
    setup %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)

      # Update meeting with follow-up email
      {:ok, meeting} =
        SocialScribe.Meetings.update_meeting(meeting, %{
          follow_up_email: "This is a test follow-up email draft."
        })

      meeting = SocialScribe.Meetings.get_meeting_with_details(meeting.id)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "shows follow-up email when available", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert html =~ "follow-up" or html =~ "Follow" or html =~ "email"
    end
  end

  describe "MeetingLive.Show - edge cases" do
    setup %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "handles meeting without transcript gracefully", %{conn: conn} do
      user = user_fixture()
      # Create meeting without transcript
      meeting = SocialScribe.MeetingsFixtures.meeting_fixture()

      calendar_event = SocialScribe.Calendar.get_calendar_event!(meeting.calendar_event_id)

      {:ok, _updated_event} =
        SocialScribe.Calendar.update_calendar_event(calendar_event, %{user_id: user.id})

      meeting = SocialScribe.Meetings.get_meeting_with_details(meeting.id)

      conn = log_in_user(build_conn(), user)

      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Should render without crashing
      assert html =~ meeting.title
    end

    test "handles meeting with empty transcript data", %{conn: conn, user: user} do
      meeting = SocialScribe.MeetingsFixtures.meeting_fixture()

      calendar_event = SocialScribe.Calendar.get_calendar_event!(meeting.calendar_event_id)

      {:ok, _updated_event} =
        SocialScribe.Calendar.update_calendar_event(calendar_event, %{user_id: user.id})

      # Create transcript with empty data
      SocialScribe.MeetingsFixtures.meeting_transcript_fixture(%{
        meeting_id: meeting.id,
        content: %{"data" => []}
      })

      meeting = SocialScribe.Meetings.get_meeting_with_details(meeting.id)

      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Should render without crashing
      assert html =~ meeting.title
    end
  end

  describe "MeetingLive.Show - unauthenticated access" do
    test "redirects unauthenticated users", %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)

      # Don't log in, try to access meeting
      result = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      case result do
        {:error, {:redirect, %{to: path}}} ->
          assert path =~ "log_in" or path =~ "users"

        {:error, {:live_redirect, %{to: path}}} ->
          assert path =~ "log_in" or path =~ "users"
      end
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
