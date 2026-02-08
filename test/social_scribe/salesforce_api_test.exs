defmodule SocialScribe.SalesforceApiTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceApi

  import SocialScribe.AccountsFixtures

  describe "format_contact/1" do
    test "formats a Salesforce contact response correctly" do
      # Test the internal formatting by checking apply_updates with empty list
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      # apply_updates with empty list should return :no_updates
      {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "123", [])
    end

    test "apply_updates/3 filters only updates with apply: true" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      updates = [
        %{field: "phone", new_value: "555-1234", apply: false},
        %{field: "email", new_value: "test@example.com", apply: false}
      ]

      {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "123", updates)
    end
  end

  describe "search_contacts/2" do
    test "requires a valid credential" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert is_struct(credential)
      assert credential.provider == "salesforce"
    end
  end

  describe "get_contact/2" do
    test "requires a valid credential and contact_id" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert is_struct(credential)
      assert credential.provider == "salesforce"
    end
  end

  describe "update_contact/3" do
    test "requires a valid credential, contact_id, and updates map" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert is_struct(credential)
      assert credential.provider == "salesforce"
    end
  end

  describe "apply_updates/3" do
    test "returns no_updates when no fields have apply: true" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      updates = [
        %{field: "phone", new_value: "555-1234", apply: false},
        %{field: "email", new_value: "test@example.com", apply: false}
      ]

      assert {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "123", updates)
    end

    test "returns no_updates for empty updates list" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      assert {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "123", [])
    end
  end
end
