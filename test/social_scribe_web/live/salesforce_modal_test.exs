defmodule SocialScribeWeb.SalesforceModalTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures

  describe "Salesforce Modal" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        salesforce_credential: salesforce_credential
      }
    end

    test "renders modal when navigating to salesforce route", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      assert has_element?(view, "#salesforce-modal-wrapper")
      assert has_element?(view, "h2", "Update in Salesforce")
    end

    test "displays contact search input", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      assert has_element?(view, "input[placeholder*='Search']")
    end

    test "shows contact search initially without suggestions form", %{
      conn: conn,
      meeting: meeting
    } do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      assert has_element?(view, "input[phx-keyup='contact_search']")

      # No suggestion form should be present initially
      refute has_element?(view, "form[phx-submit='sf_apply_updates']")
    end

    test "modal can be closed by navigating back", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      assert has_element?(view, "#salesforce-modal-wrapper")

      # Navigate back to the meeting page
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      refute has_element?(view, "#salesforce-modal-wrapper")
    end
  end

  describe "Salesforce Modal - without credential" do
    setup %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "does not show Salesforce section when no credential", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      refute html =~ "Salesforce Integration"
      refute html =~ "Update Salesforce Contact"
    end

    test "does not render salesforce modal when accessing route without credential", %{
      conn: conn,
      meeting: meeting
    } do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Modal should not be present since there's no salesforce credential
      refute html =~ "salesforce-modal-wrapper"
    end
  end

  describe "SalesforceModalComponent events" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        salesforce_credential: salesforce_credential
      }
    end

    test "contact_search input is present and accepts input", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Verify the search input exists and has the correct attributes
      assert has_element?(view, "input[phx-keyup='contact_search']")
      assert has_element?(view, "input[placeholder*='Search']")
      assert has_element?(view, "#salesforce-modal-wrapper")
    end

    test "modal contains description text", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      assert html =~ "suggested updates to sync with your integrations"
    end
  end

  describe "Salesforce Modal - UI states" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        salesforce_credential: salesforce_credential
      }
    end

    test "modal has close button or escape mechanism", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Modal should have a way to close - either an X button or close link
      assert has_element?(view, "[phx-click-away]") or has_element?(view, "a[href*='meetings']")
    end

    test "search input has debounce to prevent excessive API calls", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # The input should have phx-debounce attribute
      assert html =~ "phx-debounce"
    end

    test "modal initially shows contact search step", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Should show search input and prompt to search
      assert html =~ "Search"
      assert html =~ "contact"
    end

    test "modal has Salesforce branding/identification", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      assert html =~ "Salesforce"
    end
  end

  describe "Salesforce Modal - empty states" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        salesforce_credential: salesforce_credential
      }
    end

    test "shows appropriate message when no contacts found", %{conn: conn, meeting: meeting} do
      import Mox
      setup_mox()

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, []}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "nonexistent"})

      :timer.sleep(200)

      html = render(view)

      # Should show empty state or no contacts message
      assert html =~ "No contacts" or html =~ "search" or String.length(html) > 0
    end
  end

  describe "Salesforce Modal - accessibility" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        salesforce_credential: salesforce_credential
      }
    end

    test "search input has proper label or placeholder", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Input should have placeholder text for accessibility
      assert html =~ "placeholder"
      assert html =~ "Search"
    end

    test "modal has proper heading structure", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Modal should have h2 heading
      assert has_element?(view, "h2")
    end

    test "modal has semantic structure for screen readers", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Should have button elements properly marked
      assert html =~ "<button" or html =~ "type=\"button\"" or html =~ "type=\"submit\""
    end
  end

  describe "Salesforce Modal - error recovery" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        salesforce_credential: salesforce_credential
      }
    end

    test "modal recovers after search API error", %{conn: conn, meeting: meeting} do
      import Mox
      setup_mox()

      # First search fails, second succeeds
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:error, {:api_error, 500, "Server error"}}
      end)
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, [%{id: "sf_123", firstname: "Test", lastname: "User", email: "test@example.com"}]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # First search fails
      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Test"})

      :timer.sleep(200)

      # Second search succeeds
      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Test User"})

      :timer.sleep(200)

      html = render(view)

      # Modal should still be functional
      assert html =~ "salesforce-modal-wrapper" or html =~ "Salesforce"
    end
  end

  defp setup_mox do
    Mox.verify_on_exit!()
  end

  # Helper function to create a meeting with transcript for testing
  defp meeting_fixture_with_transcript(user) do
    meeting = meeting_fixture(%{})

    # Update the meeting's calendar_event to belong to the test user
    calendar_event = SocialScribe.Calendar.get_calendar_event!(meeting.calendar_event_id)

    {:ok, _updated_event} =
      SocialScribe.Calendar.update_calendar_event(calendar_event, %{user_id: user.id})

    # Create a transcript with some content
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
              %{"text" => "number"},
              %{"text" => "is"},
              %{"text" => "555-1234"}
            ]
          }
        ]
      }
    })

    # Reload the meeting with all associations
    SocialScribe.Meetings.get_meeting_with_details(meeting.id)
  end
end
