defmodule SocialScribe.SalesforceApi do
  @moduledoc """
  Salesforce CRM API client for contacts operations.
  Implements automatic token refresh on 401/expired token errors.
  """

  @behaviour SocialScribe.SalesforceApiBehaviour

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.SalesforceTokenRefresher

  require Logger

  @api_version "v59.0"

  # Use only fields that exist on Contact in all Salesforce orgs/editions.
  # Birthdate and Description are not available in all orgs and cause INVALID_FIELD errors.
  @contact_fields [
    "Id",
    "FirstName",
    "LastName",
    "Email",
    "Phone",
    "MobilePhone",
    "Title",
    "Department",
    "MailingStreet",
    "MailingCity",
    "MailingState",
    "MailingPostalCode",
    "MailingCountry",
    "Account.Name"
  ]

  defp client(access_token, instance_url) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, instance_url},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{access_token}"},
         {"Content-Type", "application/json"}
       ]}
    ])
  end

  @doc """
  Searches for contacts by query string using SOSL.
  Returns up to 10 matching contacts with basic properties.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def search_contacts(%UserCredential{} = credential, query) when is_binary(query) do
    with_token_refresh(credential, fn cred ->
      instance_url = get_instance_url(cred)
      sanitized_query = sanitize_sosl_query(query)

      sosl_query =
        "FIND {#{sanitized_query}} IN ALL FIELDS RETURNING Contact(#{Enum.join(field_names(), ", ")} LIMIT 10)"

      encoded_query = URI.encode(sosl_query)
      url = "/services/data/#{@api_version}/search/?q=#{encoded_query}"

      case Tesla.get(client(cred.token, instance_url), url) do
        {:ok, %Tesla.Env{status: 200, body: %{"searchRecords" => results}}} ->
          contacts = Enum.map(results, &format_contact/1)
          {:ok, contacts}

        {:ok, %Tesla.Env{status: 200, body: body}} when is_list(body) ->
          contacts = Enum.map(body, &format_contact/1)
          {:ok, contacts}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Gets a single contact by ID with all properties.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def get_contact(%UserCredential{} = credential, contact_id) do
    with_token_refresh(credential, fn cred ->
      instance_url = get_instance_url(cred)
      fields_param = Enum.join(field_names(), ",")
      url = "/services/data/#{@api_version}/sobjects/Contact/#{contact_id}?fields=#{fields_param}"

      case Tesla.get(client(cred.token, instance_url), url) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          {:ok, format_contact(body)}

        {:ok, %Tesla.Env{status: 404, body: _body}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Updates a contact's properties.
  `updates` should be a map of Salesforce field names to new values.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def update_contact(%UserCredential{} = credential, contact_id, updates)
      when is_map(updates) do
    with_token_refresh(credential, fn cred ->
      instance_url = get_instance_url(cred)
      url = "/services/data/#{@api_version}/sobjects/Contact/#{contact_id}"

      # Convert internal field names (e.g. firstname) to Salesforce API names (e.g. FirstName)
      request_body =
        updates
        |> Enum.reduce(%{}, fn {k, v}, acc ->
          key = if is_binary(k), do: k, else: to_string(k)
          sf_key = crm_field_to_salesforce(key)
          # Skip company when value is not an Account Id (Salesforce requires AccountId, not name)
          if sf_key == "AccountId" and not salesforce_id?(v), do: acc, else: Map.put(acc, sf_key, v)
        end)

      case Tesla.patch(client(cred.token, instance_url), url, request_body) do
        {:ok, %Tesla.Env{status: status}} when status in [200, 204] ->
          # Salesforce returns 204 No Content on successful PATCH, so refetch the contact
          get_contact(credential, contact_id)

        {:ok, %Tesla.Env{status: 404, body: _body}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Batch updates multiple properties on a contact.
  This is a convenience wrapper around update_contact/3.
  """
  def apply_updates(%UserCredential{} = credential, contact_id, updates_list)
      when is_list(updates_list) do
    updates_map =
      updates_list
      |> Enum.filter(fn update -> update[:apply] == true end)
      |> Enum.reduce(%{}, fn update, acc ->
        sf_field = crm_field_to_salesforce(update.field)
        Map.put(acc, sf_field, update.new_value)
      end)

    if map_size(updates_map) > 0 do
      update_contact(credential, contact_id, updates_map)
    else
      {:ok, :no_updates}
    end
  end

  defp salesforce_id?(v) when is_binary(v) do
    len = String.length(v)
    (len == 15 or len == 18) and String.match?(v, ~r/^[a-zA-Z0-9]+$/)
  end

  defp salesforce_id?(_), do: false

  # Map internal CRM field names to Salesforce API field names
  defp crm_field_to_salesforce(field) do
    field_map = %{
      "firstname" => "FirstName",
      "lastname" => "LastName",
      "email" => "Email",
      "phone" => "Phone",
      "mobilephone" => "MobilePhone",
      "company" => "AccountId",
      "jobtitle" => "Title",
      "address" => "MailingStreet",
      "city" => "MailingCity",
      "state" => "MailingState",
      "zip" => "MailingPostalCode",
      "country" => "MailingCountry"
    }

    Map.get(field_map, field, field)
  end

  # Field names without relationship fields for SOQL queries
  defp field_names do
    @contact_fields
    |> Enum.reject(&String.contains?(&1, "."))
  end

  # Format a Salesforce contact response into a cleaner structure
  defp format_contact(%{"Id" => id} = contact) do
    account_name =
      case contact do
        %{"Account" => %{"Name" => name}} -> name
        _ -> contact["AccountName"] || contact["Company__c"]
      end

    %{
      id: id,
      firstname: contact["FirstName"],
      lastname: contact["LastName"],
      email: contact["Email"],
      phone: contact["Phone"],
      mobilephone: contact["MobilePhone"],
      company: account_name,
      jobtitle: contact["Title"],
      address: contact["MailingStreet"],
      city: contact["MailingCity"],
      state: contact["MailingState"],
      zip: contact["MailingPostalCode"],
      country: contact["MailingCountry"],
      display_name: format_display_name(contact)
    }
  end

  defp format_contact(_), do: nil

  defp format_display_name(contact) do
    firstname = contact["FirstName"] || ""
    lastname = contact["LastName"] || ""
    email = contact["Email"] || ""

    name = String.trim("#{firstname} #{lastname}")

    if name == "" do
      email
    else
      name
    end
  end

  defp get_instance_url(credential) do
    # Instance URL stored in uid field as "instance_url|user_id" or in a separate field
    # We store it combined in the credential
    case credential do
      %{uid: uid} when is_binary(uid) ->
        case String.split(uid, "|") do
          [instance_url, _user_id] -> instance_url
          _ -> "https://login.salesforce.com"
        end

      _ ->
        "https://login.salesforce.com"
    end
  end

  defp sanitize_sosl_query(query) do
    query
    |> String.replace(~r/[{}\[\]()~!^&|:\\'"\/]/, "")
    |> String.trim()
  end

  # Wrapper that handles token refresh on auth errors
  defp with_token_refresh(%UserCredential{} = credential, api_call) do
    with {:ok, credential} <- SalesforceTokenRefresher.ensure_valid_token(credential) do
      case api_call.(credential) do
        {:error, {:api_error, status, body}} when status in [401, 400] ->
          if is_token_error?(status, body) do
            Logger.info("Salesforce token expired, refreshing and retrying...")
            retry_with_fresh_token(credential, api_call)
          else
            Logger.error("Salesforce API error: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}
          end

        other ->
          other
      end
    end
  end

  defp retry_with_fresh_token(credential, api_call) do
    case SalesforceTokenRefresher.refresh_credential(credential) do
      {:ok, refreshed_credential} ->
        case api_call.(refreshed_credential) do
          {:error, {:api_error, status, body}} ->
            Logger.error("Salesforce API error after refresh: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}

          {:error, {:http_error, reason}} ->
            Logger.error("Salesforce HTTP error after refresh: #{inspect(reason)}")
            {:error, {:http_error, reason}}

          success ->
            success
        end

      {:error, refresh_error} ->
        Logger.error("Failed to refresh Salesforce token: #{inspect(refresh_error)}")
        {:error, {:token_refresh_failed, refresh_error}}
    end
  end

  defp is_token_error?(401, _), do: true

  defp is_token_error?(_, body) when is_list(body) do
    Enum.any?(body, fn
      %{"errorCode" => code} ->
        code in ["INVALID_SESSION_ID", "INVALID_AUTH_HEADER"]

      _ ->
        false
    end)
  end

  defp is_token_error?(_, %{"error" => error}) do
    error in ["invalid_grant", "invalid_token", "expired_token"]
  end

  defp is_token_error?(_, _), do: false
end
