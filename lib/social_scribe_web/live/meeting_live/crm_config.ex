defmodule SocialScribeWeb.MeetingLive.CrmConfig do
  @moduledoc """
  CRM-specific configuration for the unified CRM modal component.

  Maps each CRM type to its display name, message atoms, button styling,
  and icon path. To add a new CRM integration, simply add a new entry
  to `@configs` and handle its messages in the parent LiveView.

  ## Supported CRMs

  - `:hubspot` - HubSpot CRM
  - `:salesforce` - Salesforce CRM
  """

  @type crm_type :: :hubspot | :salesforce

  @type config :: %{
          display_name: String.t(),
          search_message: atom(),
          generate_message: atom(),
          apply_message: atom(),
          button_class: String.t(),
          icon_path: String.t(),
          modal_id_prefix: String.t()
        }

  @configs %{
    hubspot: %{
      display_name: "HubSpot",
      search_message: :hubspot_search,
      generate_message: :generate_suggestions,
      apply_message: :apply_hubspot_updates,
      button_class: "bg-hubspot-button hover:bg-hubspot-button-hover",
      icon_path: "/images/hubspot-white.webp",
      modal_id_prefix: "hubspot"
    },
    salesforce: %{
      display_name: "Salesforce",
      search_message: :salesforce_search,
      generate_message: :generate_salesforce_suggestions,
      apply_message: :apply_salesforce_updates,
      button_class: "bg-salesforce-brand hover:bg-salesforce-hover",
      icon_path: "/images/salesforce-white.webp",
      modal_id_prefix: "salesforce"
    }
  }

  @doc """
  Returns the configuration map for the given CRM type.

  Raises `KeyError` if the CRM type is not supported.

  ## Examples

      iex> config = CrmConfig.get(:hubspot)
      iex> config.display_name
      "HubSpot"

      iex> config = CrmConfig.get(:salesforce)
      iex> config.display_name
      "Salesforce"

  """
  @spec get(crm_type()) :: config()
  def get(crm_type), do: Map.fetch!(@configs, crm_type)

  @doc """
  Returns a list of all supported CRM types.
  """
  @spec supported_types() :: [crm_type()]
  def supported_types, do: Map.keys(@configs)
end
