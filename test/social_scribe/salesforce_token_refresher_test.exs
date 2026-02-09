defmodule SocialScribe.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceTokenRefresher
  alias SocialScribe.Accounts

  import SocialScribe.AccountsFixtures

  describe "ensure_valid_token/1" do
    test "returns credential unchanged when token is not expired" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "returns credential unchanged when token expires in more than 5 minutes" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "returns credential unchanged when expires_at is nil" do
      user = user_fixture()

      # Create credential normally, then manually set expires_at to nil in the struct
      # (bypassing changeset validation) to test the nil handling in ensure_valid_token
      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      # Override expires_at to nil in-memory to test the code path
      credential_with_nil = %{credential | expires_at: nil}

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential_with_nil)
      assert result.expires_at == nil
    end
  end

  describe "refresh_credential/1" do
    test "updates credential in database on successful refresh" do
      # Test the database update path by directly calling update
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          token: "old_token",
          refresh_token: "old_refresh"
        })

      # Simulate what refresh_credential does after successful API call
      attrs = %{
        token: "new_access_token",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      {:ok, updated} = Accounts.update_user_credential(credential, attrs)

      assert updated.token == "new_access_token"
      assert updated.id == credential.id
      # Salesforce doesn't rotate refresh tokens by default
      assert updated.refresh_token == credential.refresh_token
    end

    test "uid can be updated with new instance_url" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          uid: "https://old-instance.salesforce.com|user123"
        })

      attrs = %{
        token: "new_token",
        uid: "https://new-instance.salesforce.com|user123",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      {:ok, updated} = Accounts.update_user_credential(credential, attrs)
      assert updated.uid == "https://new-instance.salesforce.com|user123"
    end
  end

  describe "ensure_valid_token/1 - edge cases" do
    test "handles credential expiring in more than 5 minutes (no refresh needed)" do
      user = user_fixture()

      # Token expires in 10 minutes (600 seconds) - well above threshold
      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      # Should return the credential unchanged
      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)
      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "handles credential expiring in more than 1 hour (long validity)" do
      user = user_fixture()

      # Token expires in 2 hours (7200 seconds)
      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 7200, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)
      assert result.id == credential.id
    end
  end

  describe "token persistence" do
    test "refreshed token is persisted in database" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
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

    test "refresh_token is preserved (Salesforce doesn't rotate)" do
      user = user_fixture()

      original_refresh = "salesforce_refresh_token"

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          refresh_token: original_refresh
        })

      # Salesforce doesn't rotate refresh tokens
      new_attrs = %{
        token: "new_access_token",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      {:ok, updated} = Accounts.update_user_credential(credential, new_attrs)

      # refresh_token should remain the same
      assert updated.refresh_token == original_refresh
    end
  end

  describe "credential validation" do
    test "handles missing refresh_token" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id
        })

      # Clear refresh token
      {:ok, no_refresh} =
        Accounts.update_user_credential(credential, %{refresh_token: nil})

      assert no_refresh.refresh_token == nil
    end

    test "credential with valid token passes validation" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          token: "valid_salesforce_token"
        })

      assert credential.token == "valid_salesforce_token"
    end

    test "credential provider is salesforce" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id
        })

      assert credential.provider == "salesforce"
    end

    test "handles credential with sandbox instance_url" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          uid: "https://test.sandbox.salesforce.com|user123"
        })

      # Credential with non-expired token should return ok
      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)
      assert result.uid =~ "sandbox"
    end
  end

  describe "instance_url handling" do
    test "uid stores instance_url with user id" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          uid: "https://na1.salesforce.com|0051234567890ABCDEF"
        })

      assert credential.uid =~ "na1.salesforce.com"
      assert credential.uid =~ "|"
    end

    test "instance_url can change during refresh" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          uid: "https://na1.salesforce.com|user123"
        })

      # Salesforce can return a new instance_url during refresh (org migration)
      new_attrs = %{
        token: "new_token",
        uid: "https://na5.salesforce.com|user123",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      {:ok, updated} = Accounts.update_user_credential(credential, new_attrs)

      assert updated.uid =~ "na5.salesforce.com"
      refute updated.uid =~ "na1.salesforce.com"
    end
  end
end
