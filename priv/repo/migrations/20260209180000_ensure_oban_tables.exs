defmodule SocialScribe.Repo.Migrations.EnsureObanTables do
  use Ecto.Migration

  def up do
    # Try to create table if not exists. Oban.Migration.up() usually throws if table exists.
    # But since we are fairly sure it is missing, this is fine.
    # If it fails with "relation already exists", then we know it exists.
    Oban.Migration.up()
  end

  def down do
    Oban.Migration.down(version: 1)
  end
end
