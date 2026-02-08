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
  end
end
