defmodule SocialScribe.AccountsSalesforceTest do
  use SocialScribe.DataCase

  alias SocialScribe.Accounts

  import SocialScribe.AccountsFixtures

  describe "get_user_salesforce_credential/1" do
    test "returns nil when user has no Salesforce credential" do
      user = user_fixture()

      assert Accounts.get_user_salesforce_credential(user.id) == nil
    end

    test "returns the Salesforce credential when one exists" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      result = Accounts.get_user_salesforce_credential(user.id)

      assert result.id == credential.id
      assert result.provider == "salesforce"
      assert result.user_id == user.id
    end

    test "returns only Salesforce credential, not HubSpot" do
      user = user_fixture()
      _hubspot = hubspot_credential_fixture(%{user_id: user.id})
      sf_credential = salesforce_credential_fixture(%{user_id: user.id})

      result = Accounts.get_user_salesforce_credential(user.id)

      assert result.id == sf_credential.id
      assert result.provider == "salesforce"
    end
  end

  describe "find_or_create_salesforce_credential/2" do
    test "creates a new credential when none exists" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        provider: "salesforce",
        token: "new_sf_token",
        refresh_token: "new_sf_refresh",
        uid: "https://na1.salesforce.com|00550000001",
        email: "sf@example.com",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      assert {:ok, credential} = Accounts.find_or_create_salesforce_credential(user, attrs)
      assert credential.provider == "salesforce"
      assert credential.token == "new_sf_token"
      assert credential.uid == "https://na1.salesforce.com|00550000001"
    end

    test "updates existing credential when one already exists" do
      user = user_fixture()

      old_credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          token: "old_token"
        })

      new_attrs = %{
        user_id: user.id,
        provider: "salesforce",
        token: "updated_sf_token",
        refresh_token: "updated_sf_refresh",
        uid: "https://na1.salesforce.com|00550000001",
        email: "sf@example.com",
        expires_at: DateTime.add(DateTime.utc_now(), 7200, :second)
      }

      assert {:ok, updated} = Accounts.find_or_create_salesforce_credential(user, new_attrs)
      assert updated.id == old_credential.id
      assert updated.token == "updated_sf_token"
    end
  end

  describe "salesforce_credential_fixture" do
    test "creates a valid Salesforce credential" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      assert credential.provider == "salesforce"
      assert credential.user_id == user.id
      assert credential.token != nil
      assert credential.refresh_token != nil
      assert String.contains?(credential.uid, "|")
    end

    test "uid format contains instance_url and user_id" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      [instance_url, user_id] = String.split(credential.uid, "|")

      assert String.starts_with?(instance_url, "https://")
      assert String.starts_with?(user_id, "sf_user_")
    end
  end
end
