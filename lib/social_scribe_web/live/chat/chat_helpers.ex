defmodule SocialScribeWeb.Chat.ChatHelpers do
  @moduledoc """
  Helper functions for the Chat component.

  This module contains pure functions for:
  - Parsing message content with contact mentions
  - Detecting @mention patterns in text
  - Formatting contact display (initials, avatar colors)
  - Converting provider types for icons

  These functions are extracted from ChatComponent to improve readability
  and make them easier to test independently.
  """

  @doc """
  Detects an @mention pattern at the end of the text.

  Returns `{:mention, query}` if a mention is detected, `:none` otherwise.

  ## Examples

      iex> detect_mention("Hello @john")
      {:mention, "john"}

      iex> detect_mention("Hello world")
      :none

  """
  @spec detect_mention(String.t()) :: {:mention, String.t()} | :none
  def detect_mention(text) do
    case Regex.run(~r/@(\w*)$/, text) do
      [_, query] -> {:mention, query}
      _ -> :none
    end
  end

  @doc """
  Replaces the last @mention partial with the full contact name.

  ## Examples

      iex> replace_last_mention("Hello @jo", "John Doe")
      "Hello @John Doe "

  """
  @spec replace_last_mention(String.t(), String.t()) :: String.t()
  def replace_last_mention(text, full_name) do
    Regex.replace(~r/@\w*$/, text, "@#{full_name} ")
  end

  @doc """
  Parses message content into segments of text and contact references.

  For user messages (`:user` mode), matches `@FullName` patterns.
  For assistant messages (`:assistant` mode), matches plain name patterns.

  Returns a list of segments, each being either:
  - `%{type: :text, text: "..."}` for plain text
  - `%{type: :contact, name: "...", initials: "...", provider: "..."}` for contacts

  ## Examples

      iex> parse_content_segments("Hello @John Doe", [%{name: "John Doe", provider: "hubspot"}], :user)
      [%{type: :text, text: "Hello "}, %{type: :contact, name: "John Doe", initials: "JD", provider: "hubspot"}]

  """
  @spec parse_content_segments(String.t(), list(), :user | :assistant) :: list()
  def parse_content_segments(content, contacts, _mode) when contacts == [] or is_nil(contacts) do
    [%{type: :text, text: content}]
  end

  def parse_content_segments(content, contacts, :user) do
    # For user messages, match @FullName patterns
    build_and_split(content, contacts, "@")
  end

  def parse_content_segments(content, contacts, :assistant) do
    # For AI messages, match plain Name patterns (no @ prefix)
    build_and_split(content, contacts, "")
  end

  @doc """
  Gets the initials from a contact name.

  ## Examples

      iex> contact_initials("John Doe")
      "JD"

      iex> contact_initials("Alice")
      "A"

  """
  @spec contact_initials(String.t()) :: String.t()
  def contact_initials(name) do
    name
    |> String.split()
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  @doc """
  Returns the Tailwind CSS class for avatar background based on provider.

  ## Examples

      iex> avatar_bg_class("hubspot")
      "bg-[#ff7a59]"

      iex> avatar_bg_class("salesforce")
      "bg-[#00a1e0]"

  """
  @spec avatar_bg_class(String.t()) :: String.t()
  def avatar_bg_class("salesforce"), do: "bg-[#00a1e0]"
  def avatar_bg_class("hubspot"), do: "bg-[#ff7a59]"
  def avatar_bg_class("meeting"), do: "bg-black"
  def avatar_bg_class("jump"), do: "bg-white"
  def avatar_bg_class("gmail"), do: "bg-white"
  def avatar_bg_class("emoney"), do: "bg-white"
  def avatar_bg_class(_), do: "bg-gray-400"

  @doc """
  Converts a type (atom or string) to its corresponding atom for icon rendering.

  ## Examples

      iex> entry_type(:hubspot)
      :hubspot

      iex> entry_type("salesforce")
      :salesforce

  """
  @spec entry_type(atom() | String.t() | any()) :: atom()
  def entry_type(type) when is_atom(type), do: type
  def entry_type(type) when is_binary(type), do: String.to_existing_atom(type)
  def entry_type(_), do: :unknown

  # --- Private helpers ---

  # Build regex from contact names and split content into tagged segments
  defp build_and_split(content, contacts, prefix) do
    # Collect name variants: full name + first name, sorted longest first
    name_variants =
      contacts
      |> Enum.flat_map(fn contact ->
        first_name = contact.name |> String.split() |> List.first()

        if first_name != contact.name,
          do: [{contact.name, contact}, {first_name, contact}],
          else: [{contact.name, contact}]
      end)
      |> Enum.sort_by(fn {name, _} -> -String.length(name) end)

    pattern_parts =
      name_variants
      |> Enum.map(fn {name, _} -> "#{prefix}#{Regex.escape(name)}" end)
      |> Enum.uniq()

    case pattern_parts do
      [] ->
        [%{type: :text, text: content}]

      parts ->
        pattern_str = Enum.join(parts, "|")

        case Regex.compile(pattern_str) do
          {:ok, regex} ->
            regex
            |> Regex.split(content, include_captures: true)
            |> Enum.map(fn part ->
              clean = String.replace_prefix(part, "@", "")
              match = find_contact_by_name(clean, name_variants)

              case match do
                nil ->
                  %{type: :text, text: part}

                contact ->
                  %{
                    type: :contact,
                    name: contact.name,
                    initials: contact_initials(contact.name),
                    provider: Map.get(contact, :provider, "unknown")
                  }
              end
            end)
            |> Enum.reject(&(&1.type == :text && &1.text == ""))

          {:error, _} ->
            [%{type: :text, text: content}]
        end
    end
  end

  defp find_contact_by_name(clean_name, name_variants) do
    downcased = String.downcase(clean_name)

    case Enum.find(name_variants, fn {name, _} -> String.downcase(name) == downcased end) do
      {_, contact} -> contact
      nil -> nil
    end
  end
end
