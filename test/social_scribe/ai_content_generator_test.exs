defmodule SocialScribe.AIContentGeneratorApiTest do
  use SocialScribe.DataCase

  import Mox

  setup :verify_on_exit!

  describe "generate_salesforce_suggestions/1" do
    test "delegates to implementation" do
      meeting = %{id: 1, title: "Test Meeting"}

      expected_suggestions = [
        %{field: "phone", value: "555-1234", context: "Mentioned phone"},
        %{field: "email", value: "john@example.com", context: "Shared email"}
      ]

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn m ->
        assert m == meeting
        {:ok, expected_suggestions}
      end)

      assert {:ok, ^expected_suggestions} =
               SocialScribe.AIContentGeneratorApi.generate_salesforce_suggestions(meeting)
    end

    test "returns error when generation fails" do
      meeting = %{id: 1, title: "Test Meeting"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _m ->
        {:error, :api_error}
      end)

      assert {:error, :api_error} =
               SocialScribe.AIContentGeneratorApi.generate_salesforce_suggestions(meeting)
    end
  end

  describe "answer_contact_question/3" do
    test "delegates to implementation with correct args" do
      question = "What is John's phone number?"
      contact_data = %{name: "John Doe", phone: "555-1234"}
      meeting = %{id: 1, title: "Test Meeting"}

      expected_answer = "John's phone number is 555-1234, as mentioned in the meeting."

      SocialScribe.AIContentGeneratorMock
      |> expect(:answer_contact_question, fn q, cd, m ->
        assert q == question
        assert cd == contact_data
        assert m == meeting
        {:ok, expected_answer}
      end)

      assert {:ok, ^expected_answer} =
               SocialScribe.AIContentGeneratorApi.answer_contact_question(
                 question,
                 contact_data,
                 meeting
               )
    end

    test "returns error when answering fails" do
      SocialScribe.AIContentGeneratorMock
      |> expect(:answer_contact_question, fn _q, _cd, _m ->
        {:error, :api_unavailable}
      end)

      assert {:error, :api_unavailable} =
               SocialScribe.AIContentGeneratorApi.answer_contact_question(
                 "test question",
                 %{},
                 %{}
               )
    end
  end

  describe "generate_hubspot_suggestions/1" do
    test "still delegates to implementation correctly" do
      meeting = %{id: 1, title: "Test Meeting"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _m ->
        {:ok, [%{field: "phone", value: "555-1234", context: "test"}]}
      end)

      assert {:ok, [suggestion]} =
               SocialScribe.AIContentGeneratorApi.generate_hubspot_suggestions(meeting)

      assert suggestion.field == "phone"
    end

    test "returns error when HubSpot suggestion generation fails" do
      meeting = %{id: 1, title: "Test Meeting"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _m ->
        {:error, {:api_error, 429, %{"error" => "Rate limit exceeded"}}}
      end)

      assert {:error, {:api_error, 429, _}} =
               SocialScribe.AIContentGeneratorApi.generate_hubspot_suggestions(meeting)
    end

    test "returns empty list when no suggestions extracted" do
      meeting = %{id: 1, title: "Test Meeting"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _m ->
        {:ok, []}
      end)

      assert {:ok, []} =
               SocialScribe.AIContentGeneratorApi.generate_hubspot_suggestions(meeting)
    end
  end

  describe "generate_follow_up_email/1" do
    test "delegates to implementation for email generation" do
      meeting = %{id: 1, title: "Test Meeting"}

      expected_email = "Hi Team,\n\nThank you for joining the meeting..."

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_follow_up_email, fn m ->
        assert m == meeting
        {:ok, expected_email}
      end)

      assert {:ok, ^expected_email} =
               SocialScribe.AIContentGeneratorApi.generate_follow_up_email(meeting)
    end

    test "returns error when email generation fails" do
      meeting = %{id: 1, title: "Test Meeting"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_follow_up_email, fn _m ->
        {:error, {:config_error, "API key missing"}}
      end)

      assert {:error, {:config_error, _}} =
               SocialScribe.AIContentGeneratorApi.generate_follow_up_email(meeting)
    end
  end

  describe "generate_automation/2" do
    test "delegates to implementation for automation content" do
      automation = %{id: 1, name: "Test Automation", prompt: "Generate summary"}
      meeting = %{id: 1, title: "Test Meeting"}

      expected_content = "Meeting Summary: The team discussed..."

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_automation, fn a, m ->
        assert a == automation
        assert m == meeting
        {:ok, expected_content}
      end)

      assert {:ok, ^expected_content} =
               SocialScribe.AIContentGeneratorApi.generate_automation(automation, meeting)
    end

    test "returns error when automation generation fails" do
      automation = %{id: 1, name: "Test Automation"}
      meeting = %{id: 1, title: "Test Meeting"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_automation, fn _a, _m ->
        {:error, {:http_error, :timeout}}
      end)

      assert {:error, {:http_error, :timeout}} =
               SocialScribe.AIContentGeneratorApi.generate_automation(automation, meeting)
    end
  end

  describe "answer_contact_question/3 - edge cases" do
    test "handles empty contact data" do
      question = "What was discussed in the meeting?"
      contact_data = %{}
      meeting = %{id: 1, title: "Test Meeting"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:answer_contact_question, fn _q, cd, _m ->
        assert cd == %{}
        {:ok, %{answer: "The meeting covered...", sources: [:meeting]}}
      end)

      assert {:ok, %{answer: _, sources: [:meeting]}} =
               SocialScribe.AIContentGeneratorApi.answer_contact_question(
                 question,
                 contact_data,
                 meeting
               )
    end

    test "handles multiple CRM sources in answer" do
      question = "Tell me about John"
      contact_data = %{"HubSpot - John" => %{name: "John", email: "john@example.com"}}
      meeting = %{id: 1, title: "Test Meeting"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:answer_contact_question, fn _q, _cd, _m ->
        {:ok, %{answer: "John's details...", sources: [:meeting, :hubspot]}}
      end)

      assert {:ok, %{sources: [:meeting, :hubspot]}} =
               SocialScribe.AIContentGeneratorApi.answer_contact_question(
                 question,
                 contact_data,
                 meeting
               )
    end

    test "handles Salesforce source in answer" do
      question = "Tell me about Jane"
      contact_data = %{"Salesforce - Jane" => %{name: "Jane", phone: "555-1234"}}
      meeting = %{id: 1, title: "Test Meeting"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:answer_contact_question, fn _q, _cd, _m ->
        {:ok, %{answer: "Jane's phone is 555-1234", sources: [:salesforce]}}
      end)

      assert {:ok, %{sources: [:salesforce]}} =
               SocialScribe.AIContentGeneratorApi.answer_contact_question(
                 question,
                 contact_data,
                 meeting
               )
    end
  end

  describe "API error handling" do
    test "handles 429 rate limit errors" do
      meeting = %{id: 1, title: "Test Meeting"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _m ->
        {:error, {:api_error, 429, %{"error" => %{"message" => "Resource exhausted"}}}}
      end)

      result = SocialScribe.AIContentGeneratorApi.generate_salesforce_suggestions(meeting)
      assert {:error, {:api_error, 429, _}} = result
    end

    test "handles 500 server errors" do
      meeting = %{id: 1, title: "Test Meeting"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _m ->
        {:error, {:api_error, 500, %{"error" => "Internal server error"}}}
      end)

      result = SocialScribe.AIContentGeneratorApi.generate_hubspot_suggestions(meeting)
      assert {:error, {:api_error, 500, _}} = result
    end

    test "handles network timeout errors" do
      meeting = %{id: 1, title: "Test Meeting"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_follow_up_email, fn _m ->
        {:error, {:http_error, :timeout}}
      end)

      result = SocialScribe.AIContentGeneratorApi.generate_follow_up_email(meeting)
      assert {:error, {:http_error, :timeout}} = result
    end

    test "handles configuration errors (missing API key)" do
      meeting = %{id: 1, title: "Test Meeting"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _m ->
        {:error, {:config_error, "Gemini API key is missing - set GEMINI_API_KEY env var"}}
      end)

      result = SocialScribe.AIContentGeneratorApi.generate_salesforce_suggestions(meeting)
      assert {:error, {:config_error, message}} = result
      assert message =~ "API key"
    end
  end
end
