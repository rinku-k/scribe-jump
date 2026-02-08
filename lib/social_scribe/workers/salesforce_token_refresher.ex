defmodule SocialScribe.Workers.SalesforceTokenRefresher do
  @moduledoc """
  Oban worker that proactively refreshes Salesforce tokens before they expire.
  Runs on a cron schedule to check for credentials expiring within 10 minutes.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias SocialScribe.Repo
  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.SalesforceTokenRefresher

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    # Find Salesforce credentials expiring within 10 minutes
    ten_minutes_from_now = DateTime.add(DateTime.utc_now(), 600, :second)

    credentials =
      from(c in UserCredential,
        where: c.provider == "salesforce",
        where: c.expires_at <= ^ten_minutes_from_now,
        where: not is_nil(c.refresh_token)
      )
      |> Repo.all()

    Logger.info("SalesforceTokenRefresher: Found #{length(credentials)} credential(s) to refresh")

    Enum.each(credentials, fn credential ->
      case SalesforceTokenRefresher.refresh_credential(credential) do
        {:ok, _updated} ->
          Logger.info(
            "SalesforceTokenRefresher: Successfully refreshed token for credential #{credential.id}"
          )

        {:error, reason} ->
          Logger.error(
            "SalesforceTokenRefresher: Failed to refresh token for credential #{credential.id}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end
end
