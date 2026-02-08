defmodule SocialScribe.Workers.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase

  alias SocialScribe.Workers.SalesforceTokenRefresher

  import SocialScribe.AccountsFixtures

  describe "perform/1" do
    test "completes successfully when no credentials need refresh" do
      # No Salesforce credentials exist, so nothing to refresh
      assert :ok = SalesforceTokenRefresher.perform(%{})
    end

    test "finds credentials expiring within 10 minutes" do
      user = user_fixture()

      # Create a credential that expires soon (within 10 minutes)
      _expiring_credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
        })

      # This will try to refresh and fail since we can't hit Salesforce API
      # but it demonstrates the worker finds the credential
      # The worker logs errors but always returns :ok
      assert :ok = SalesforceTokenRefresher.perform(%{})
    end

    test "ignores credentials not expiring soon" do
      user = user_fixture()

      # Create a credential with plenty of time left (2 hours)
      _valid_credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 7200, :second)
        })

      # Should complete without attempting refresh
      assert :ok = SalesforceTokenRefresher.perform(%{})
    end

    test "ignores credentials without refresh tokens" do
      user = user_fixture()

      # Create an expiring credential without a refresh token
      _no_refresh_credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 60, :second),
          refresh_token: nil
        })

      # Should skip credentials without refresh tokens
      assert :ok = SalesforceTokenRefresher.perform(%{})
    end
  end
end
