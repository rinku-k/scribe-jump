defmodule SocialScribe.Repo.Migrations.ExtendCalendarEventsStringColumns do
  use Ecto.Migration

  def change do
    alter table(:calendar_events) do
      modify :location, :text, from: :string
      modify :hangout_link, :text, from: :string
      modify :html_link, :text, from: :string
      modify :meeting_url, :text, from: :string
    end
  end
end
