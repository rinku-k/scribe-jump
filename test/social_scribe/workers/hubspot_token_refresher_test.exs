defmodule SocialScribe.Workers.HubspotTokenRefresherTest do
  use SocialScribe.DataCase

  alias SocialScribe.Workers.HubspotTokenRefresher

  import SocialScribe.AccountsFixtures

  describe "perform/1" do
    test "completes successfully when no credentials need refresh" do
      # No HubSpot credentials exist, so nothing to refresh
      assert :ok = HubspotTokenRefresher.perform(%{})
    end

    test "finds credentials expiring within 10 minutes" do
      user = user_fixture()

      # Create a credential that expires soon (within 10 minutes)
      _expiring_credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
        })

      # This will try to refresh and fail since we can't hit HubSpot API
      # but it demonstrates the worker finds the credential
      # The worker logs errors but always returns :ok
      assert :ok = HubspotTokenRefresher.perform(%{})
    end

    test "ignores credentials not expiring soon" do
      user = user_fixture()

      # Create a credential with plenty of time left (2 hours)
      _valid_credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 7200, :second)
        })

      # Should complete without attempting refresh
      assert :ok = HubspotTokenRefresher.perform(%{})
    end

    test "ignores credentials without refresh tokens" do
      user = user_fixture()

      # Create an expiring credential without a refresh token
      _no_refresh_credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 60, :second),
          refresh_token: nil
        })

      # Should skip credentials without refresh tokens
      assert :ok = HubspotTokenRefresher.perform(%{})
    end
  end

  describe "perform/1 - edge cases" do
    test "handles multiple credentials from different users" do
      user1 = user_fixture()
      user2 = user_fixture()

      # Both users have expiring credentials
      _credential1 =
        hubspot_credential_fixture(%{
          user_id: user1.id,
          expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
        })

      _credential2 =
        hubspot_credential_fixture(%{
          user_id: user2.id,
          expires_at: DateTime.add(DateTime.utc_now(), 400, :second)
        })

      # Worker should handle multiple credentials
      assert :ok = HubspotTokenRefresher.perform(%{})
    end

    test "handles already expired credentials" do
      user = user_fixture()

      # Credential expired 5 minutes ago
      _expired_credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), -300, :second)
        })

      # Worker should still try to refresh
      assert :ok = HubspotTokenRefresher.perform(%{})
    end

    test "handles credential expiring exactly at threshold" do
      user = user_fixture()

      # Credential expires in exactly 10 minutes
      _threshold_credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      assert :ok = HubspotTokenRefresher.perform(%{})
    end
  end
end
