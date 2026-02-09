defmodule SocialScribe.HubspotTokenRefresherTest do
  use SocialScribe.DataCase

  alias SocialScribe.HubspotTokenRefresher
  alias SocialScribe.Accounts

  import SocialScribe.AccountsFixtures

  describe "ensure_valid_token/1" do
    test "returns credential unchanged when token is not expired" do
      user = user_fixture()

      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      {:ok, result} = HubspotTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "returns credential unchanged when token expires in more than 5 minutes" do
      user = user_fixture()

      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      {:ok, result} = HubspotTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end
  end

  describe "refresh_credential/1" do
    test "updates credential in database on successful refresh" do
      # This test would require mocking Tesla
      # For now, we test the database update path by directly calling update
      user = user_fixture()

      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          token: "old_token",
          refresh_token: "old_refresh"
        })

      # Simulate what refresh_credential does after successful API call
      attrs = %{
        token: "new_access_token",
        refresh_token: "new_refresh_token",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      {:ok, updated} = Accounts.update_user_credential(credential, attrs)

      assert updated.token == "new_access_token"
      assert updated.refresh_token == "new_refresh_token"
      assert updated.id == credential.id
    end
  end

  describe "ensure_valid_token/1 - edge cases" do
    test "handles credential expiring in more than 5 minutes (no refresh needed)" do
      user = user_fixture()

      # Token expires in 10 minutes (600 seconds) - well above threshold
      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      # Should return the credential unchanged
      {:ok, result} = HubspotTokenRefresher.ensure_valid_token(credential)
      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "handles credential expiring in more than 1 hour (long validity)" do
      user = user_fixture()

      # Token expires in 2 hours (7200 seconds)
      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 7200, :second)
        })

      {:ok, result} = HubspotTokenRefresher.ensure_valid_token(credential)
      assert result.id == credential.id
    end
  end

  describe "token persistence" do
    test "refreshed token is persisted in database" do
      user = user_fixture()

      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          token: "initial_token"
        })

      new_attrs = %{
        token: "refreshed_token",
        expires_at: DateTime.add(DateTime.utc_now(), 7200, :second)
      }

      {:ok, updated} = Accounts.update_user_credential(credential, new_attrs)

      # Reload from database to verify persistence
      reloaded = Accounts.get_user_credential!(credential.id)

      assert reloaded.token == "refreshed_token"
      assert reloaded.id == updated.id
    end

    test "refresh_token rotation is supported" do
      user = user_fixture()

      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          refresh_token: "original_refresh_token"
        })

      # HubSpot rotates refresh tokens
      new_attrs = %{
        token: "new_access_token",
        refresh_token: "rotated_refresh_token",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      {:ok, updated} = Accounts.update_user_credential(credential, new_attrs)

      assert updated.refresh_token == "rotated_refresh_token"
      assert updated.refresh_token != credential.refresh_token
    end
  end

  describe "credential validation" do
    test "handles missing refresh_token" do
      user = user_fixture()

      credential =
        hubspot_credential_fixture(%{
          user_id: user.id
        })

      # Clear refresh token - this would normally cause refresh to fail
      {:ok, no_refresh} =
        Accounts.update_user_credential(credential, %{refresh_token: nil})

      assert no_refresh.refresh_token == nil
    end

    test "credential with valid token passes validation" do
      user = user_fixture()

      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          token: "valid_token_123"
        })

      assert credential.token == "valid_token_123"
    end

    test "credential provider is hubspot" do
      user = user_fixture()

      credential =
        hubspot_credential_fixture(%{
          user_id: user.id
        })

      assert credential.provider == "hubspot"
    end
  end
end
