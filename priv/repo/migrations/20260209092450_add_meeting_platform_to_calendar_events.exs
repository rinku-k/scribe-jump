defmodule SocialScribe.Repo.Migrations.AddMeetingPlatformToCalendarEvents do
  use Ecto.Migration

  def change do
    alter table(:calendar_events) do
      add :meeting_platform, :string  # google_meet, zoom, microsoft_teams, or nil
      add :meeting_url, :string       # The actual meeting URL to join
    end
  end
end
