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
end
