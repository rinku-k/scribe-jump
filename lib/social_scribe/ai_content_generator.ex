defmodule SocialScribe.AIContentGenerator do
  @moduledoc "Generates content using Google Gemini."

  @behaviour SocialScribe.AIContentGeneratorApi

  alias SocialScribe.Meetings
  alias SocialScribe.Automations

  @gemini_model "gemini-2.5-flash-lite"
  @gemini_api_base_url "https://generativelanguage.googleapis.com/v1beta/models"

  @impl SocialScribe.AIContentGeneratorApi
  def generate_follow_up_email(meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        Based on the following meeting transcript, please draft a concise and professional follow-up email.
        The email should summarize the key discussion points and clearly list any action items assigned, including who is responsible if mentioned.
        Keep the tone friendly and action-oriented.

        #{meeting_prompt}
        """

        call_gemini(prompt)
    end
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_automation(automation, meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        #{Automations.generate_prompt_for_automation(automation)}

        #{meeting_prompt}
        """

        call_gemini(prompt)
    end
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_hubspot_suggestions(meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        You are an AI assistant that extracts contact information updates from meeting transcripts.

        Analyze the following meeting transcript and extract any information that could be used to update a CRM contact record.

        Look for mentions of:
        - Phone numbers (phone, mobilephone)
        - Email addresses (email)
        - Company name (company)
        - Job title/role (jobtitle)
        - Physical address details (address, city, state, zip, country)
        - Website URLs (website)
        - LinkedIn profile (linkedin_url)
        - Twitter handle (twitter_handle)

        IMPORTANT: Only extract information that is EXPLICITLY mentioned in the transcript. Do not infer or guess.

        The transcript includes timestamps in [MM:SS] format at the start of each line.

        Return your response as a JSON array of objects. Each object should have:
        - "field": the CRM field name (use exactly: firstname, lastname, email, phone, mobilephone, company, jobtitle, address, city, state, zip, country, website, linkedin_url, twitter_handle)
        - "value": the extracted value
        - "context": a brief quote of where this was mentioned
        - "timestamp": the timestamp in MM:SS format where this was mentioned

        If no contact information updates are found, return an empty array: []

        Example response format:
        [
          {"field": "phone", "value": "555-123-4567", "context": "John mentioned 'you can reach me at 555-123-4567'", "timestamp": "01:23"},
          {"field": "company", "value": "Acme Corp", "context": "Sarah said she just joined Acme Corp", "timestamp": "05:47"}
        ]

        ONLY return valid JSON, no other text.

        Meeting transcript:
        #{meeting_prompt}
        """

        case call_gemini(prompt) do
          {:ok, response} ->
            parse_hubspot_suggestions(response)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_salesforce_suggestions(meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        You are an AI assistant that extracts contact information updates from meeting transcripts.

        Analyze the following meeting transcript and extract any information that could be used to update a Salesforce CRM contact record.

        Look for mentions of:
        - Phone numbers (phone, mobilephone)
        - Email addresses (email)
        - Company name (company)
        - Job title/role (jobtitle)
        - Physical address details (address, city, state, zip, country)
        - First name or last name corrections (firstname, lastname)

        IMPORTANT: Only extract information that is EXPLICITLY mentioned in the transcript. Do not infer or guess.

        The transcript includes timestamps in [MM:SS] format at the start of each line.

        Return your response as a JSON array of objects. Each object should have:
        - "field": the CRM field name (use exactly: firstname, lastname, email, phone, mobilephone, company, jobtitle, address, city, state, zip, country)
        - "value": the extracted value
        - "context": a brief quote of where this was mentioned
        - "timestamp": the timestamp in MM:SS format where this was mentioned

        If no contact information updates are found, return an empty array: []

        Example response format:
        [
          {"field": "phone", "value": "555-123-4567", "context": "John mentioned 'you can reach me at 555-123-4567'", "timestamp": "01:23"},
          {"field": "company", "value": "Acme Corp", "context": "Sarah said she just joined Acme Corp", "timestamp": "05:47"}
        ]

        ONLY return valid JSON, no other text.

        Meeting transcript:
        #{meeting_prompt}
        """

        case call_gemini(prompt) do
          {:ok, response} ->
            parse_crm_suggestions(response)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl SocialScribe.AIContentGeneratorApi
  def answer_contact_question(question, contact_data, meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        # Determine which sources are available
        has_crm_data = map_size(contact_data) > 0
        crm_sources = extract_crm_sources(contact_data)

        contact_info =
          if has_crm_data do
            contact_data
            |> Enum.map(fn {source, contact} ->
              details =
                contact
                |> Enum.map(fn {field, value} -> "  - #{field}: #{value || "N/A"}" end)
                |> Enum.join("\n")

              "Source: #{source}\n#{details}"
            end)
            |> Enum.join("\n\n")
          else
            ""
          end

        prompt = build_context_aware_prompt(question, meeting_prompt, contact_info, has_crm_data, crm_sources)

        case call_gemini(prompt) do
          {:ok, response} ->
            parse_structured_chat_response(response, has_crm_data, crm_sources)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # Build a context-aware prompt based on available data sources
  defp build_context_aware_prompt(question, meeting_prompt, contact_info, has_crm_data, crm_sources) do
    sources_list = if has_crm_data, do: ["Meeting"] ++ crm_sources, else: ["Meeting"]
    valid_sources_hint = Enum.join(sources_list, ", ")

    if has_crm_data do
      """
      You are an AI assistant helping a financial advisor with meeting and CRM contact information.

      The advisor is asking a question. You have access to both the meeting transcript AND CRM contact data.
      Use the appropriate data source(s) to provide a helpful, concise answer.

      IMPORTANT INSTRUCTIONS FOR SOURCES:
      - If the answer comes ONLY from the Meeting transcript, set sources to ["Meeting"]
      - If the answer comes ONLY from CRM data (#{valid_sources_hint}), set sources to the specific CRM source(s) used
      - If the answer combines information from both the meeting AND CRM data, include all relevant sources
      - Be accurate about which sources you actually used to form your answer
      - Do NOT include a source if you didn't use information from it

      CRM Contact Information:
      #{contact_info}

      Meeting Transcript:
      #{meeting_prompt}

      Question: #{question}

      Respond in the following JSON format ONLY (no additional text):
      {
        "answer": "Your clear, concise answer here. If referencing specific parts of the transcript, mention the approximate timestamp.",
        "sources": ["Meeting"] or ["Salesforce"] or ["HubSpot"] or ["Meeting", "Salesforce"] etc.
      }
      """
    else
      """
      You are an AI assistant helping a financial advisor with meeting information.

      The advisor is asking a question about a meeting. Use ONLY the meeting transcript to answer.
      No CRM or external contact data is available for this question.

      IMPORTANT: Since only the meeting transcript is available, your answer must come from the meeting only.

      Meeting Transcript:
      #{meeting_prompt}

      Question: #{question}

      Respond in the following JSON format ONLY (no additional text):
      {
        "answer": "Your clear, concise answer here. If referencing specific parts of the transcript, mention the approximate timestamp. If you don't have enough information to answer, say so clearly.",
        "sources": ["Meeting"]
      }
      """
    end
  end

  # Extract CRM source names from contact_data keys
  defp extract_crm_sources(contact_data) do
    contact_data
    |> Map.keys()
    |> Enum.map(fn key ->
      cond do
        String.contains?(key, "HubSpot") -> "HubSpot"
        String.contains?(key, "Salesforce") -> "Salesforce"
        true -> key
      end
    end)
    |> Enum.uniq()
  end

  # Parse the structured JSON response from Gemini
  defp parse_structured_chat_response(response, has_crm_data, available_crm_sources) do
    cleaned =
      response
      |> String.trim()
      |> String.replace(~r/^```json\n?/, "")
      |> String.replace(~r/\n?```$/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, %{"answer" => answer, "sources" => sources}} when is_binary(answer) and is_list(sources) ->
        # Convert string sources to atoms and validate
        parsed_sources =
          sources
          |> Enum.map(&normalize_source_name/1)
          |> Enum.filter(&(&1 != nil))
          |> Enum.uniq()

        # Ensure we have at least Meeting source
        final_sources = if Enum.empty?(parsed_sources), do: [:meeting], else: parsed_sources

        {:ok, %{answer: answer, sources: final_sources}}

      {:ok, %{"answer" => answer}} when is_binary(answer) ->
        # Fallback if sources not provided
        default_sources = if has_crm_data, do: [:meeting | Enum.map(available_crm_sources, &String.downcase/1) |> Enum.map(&String.to_atom/1)], else: [:meeting]
        {:ok, %{answer: answer, sources: default_sources}}

      {:error, _} ->
        # If JSON parsing fails, treat entire response as answer with meeting source
        {:ok, %{answer: response, sources: [:meeting]}}

      _ ->
        # Unexpected format
        {:ok, %{answer: response, sources: [:meeting]}}
    end
  end

  # Normalize source name strings to atoms
  defp normalize_source_name(source) when is_binary(source) do
    case String.downcase(String.trim(source)) do
      "meeting" -> :meeting
      "hubspot" -> :hubspot
      "salesforce" -> :salesforce
      _ -> nil
    end
  end

  defp normalize_source_name(_), do: nil


  defp parse_crm_suggestions(response) do
    cleaned =
      response
      |> String.trim()
      |> String.replace(~r/^```json\n?/, "")
      |> String.replace(~r/\n?```$/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, suggestions} when is_list(suggestions) ->
        formatted =
          suggestions
          |> Enum.filter(&is_map/1)
          |> Enum.map(fn s ->
            field = normalize_field(s["field"])

            %{
              field: field,
              value: s["value"],
              context: s["context"],
              timestamp: s["timestamp"]
            }
          end)
          |> Enum.filter(fn s -> s.field != nil and s.value != nil end)

        {:ok, formatted}

      {:ok, _} ->
        {:ok, []}

      {:error, _} ->
        {:ok, []}
    end
  end

  defp parse_hubspot_suggestions(response) do
    # Clean up the response - remove markdown code blocks if present
    cleaned =
      response
      |> String.trim()
      |> String.replace(~r/^```json\n?/, "")
      |> String.replace(~r/\n?```$/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, suggestions} when is_list(suggestions) ->
        formatted =
          suggestions
          |> Enum.filter(&is_map/1)
          |> Enum.map(fn s ->
            field = normalize_field(s["field"])

            %{
              field: field,
              value: s["value"],
              context: s["context"],
              timestamp: s["timestamp"]
            }
          end)
          |> Enum.filter(fn s -> s.field != nil and s.value != nil end)

        {:ok, formatted}

      {:ok, _} ->
        {:ok, []}

      {:error, _} ->
        # If JSON parsing fails, return empty suggestions
        {:ok, []}
    end
  end

  defp normalize_field(nil), do: nil
  defp normalize_field(f) when is_binary(f), do: String.downcase(String.trim(f))
  defp normalize_field(_), do: nil

  defp call_gemini(prompt_text, opts \\ []) do
    retries_left = Keyword.get(opts, :retries_left, 1)
    api_key = Application.get_env(:social_scribe, :gemini_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, {:config_error, "Gemini API key is missing - set GEMINI_API_KEY env var"}}
    else
      path = "/#{@gemini_model}:generateContent?key=#{api_key}"

      payload = %{
        contents: [
          %{
            parts: [%{text: prompt_text}]
          }
        ]
      }

      case Tesla.post(client(), path, payload) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          text_path = [
            "candidates",
            Access.at(0),
            "content",
            "parts",
            Access.at(0),
            "text"
          ]

          case get_in(body, text_path) do
            nil -> {:error, {:parsing_error, "No text content found in Gemini response", body}}
            text_content -> {:ok, text_content}
          end

        {:ok, %Tesla.Env{status: 429, body: error_body}} when retries_left > 0 ->
          wait_seconds = parse_retry_delay_seconds(error_body) || 35
          Process.sleep(min(wait_seconds, 60) * 1000)
          call_gemini(prompt_text, retries_left: retries_left - 1)

        {:ok, %Tesla.Env{status: status, body: error_body}} ->
          {:error, {:api_error, status, error_body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end
  end

  # Parse RetryInfo.retry_delay from Gemini 429 response (e.g. "32s" -> 32)
  defp parse_retry_delay_seconds(body) when is_map(body) do
    details = get_in(body, ["error", "details"])

    with details when is_list(details) <- details,
         %{"retryDelay" => delay} <-
           Enum.find(details, fn d ->
             is_map(d) and Map.get(d, "@type") == "type.googleapis.com/google.rpc.RetryInfo"
           end),
         delay when is_binary(delay) <- delay,
         [seconds_str] <- Regex.run(~r/(\d+)s/, delay, capture: :all_but_first),
         {seconds, ""} <- Integer.parse(seconds_str) do
      seconds
    else
      _ -> nil
    end
  end

  defp parse_retry_delay_seconds(_), do: nil

  defp client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, @gemini_api_base_url},
      Tesla.Middleware.JSON
    ])
  end
end
