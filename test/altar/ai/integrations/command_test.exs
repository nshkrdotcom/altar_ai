defmodule Altar.AI.Integrations.CommandTest do
  use ExUnit.Case, async: false

  alias Altar.AI.Integrations.Command

  describe "attach_telemetry/0" do
    setup do
      # Ensure handlers are detached before and after each test
      Command.detach_telemetry()
      on_exit(fn -> Command.detach_telemetry() end)
      :ok
    end

    test "attaches telemetry handlers" do
      refute Command.attached?()

      assert :ok = Command.attach_telemetry()
      assert Command.attached?()
    end

    test "is idempotent - can be called multiple times" do
      Command.attach_telemetry()
      Command.attach_telemetry()
      Command.attach_telemetry()

      assert Command.attached?()
    end
  end

  describe "detach_telemetry/0" do
    setup do
      Command.detach_telemetry()
      on_exit(fn -> Command.detach_telemetry() end)
      :ok
    end

    test "detaches telemetry handlers" do
      Command.attach_telemetry()
      assert Command.attached?()

      Command.detach_telemetry()
      refute Command.attached?()
    end

    test "is safe to call when not attached" do
      refute Command.attached?()
      assert :ok = Command.detach_telemetry()
      refute Command.attached?()
    end
  end

  describe "handle_event/4" do
    setup do
      Command.attach_telemetry()
      on_exit(fn -> Command.detach_telemetry() end)
      :ok
    end

    test "handles text_gen stop event with session_id" do
      # This test verifies the handler runs without errors
      # In a real scenario, Command.Costs would be called
      measurements = %{duration: 1_000_000}

      metadata = %{
        command_session_id: "test-session-123",
        model: "gpt-4o",
        provider: :openai,
        tokens: %{prompt: 100, completion: 50}
      }

      # Execute the event directly
      assert :ok =
               Command.handle_event([:altar, :ai, :text_gen, :stop], measurements, metadata, nil)
    end

    test "handles event without session_id - skips cost recording" do
      measurements = %{duration: 1_000_000}

      metadata = %{
        model: "gpt-4o",
        provider: :openai
      }

      # Should complete without error when no session_id
      assert :ok =
               Command.handle_event([:altar, :ai, :text_gen, :stop], measurements, metadata, nil)
    end

    test "handles embed stop event" do
      measurements = %{duration: 500_000}

      metadata = %{
        command_session_id: "test-session-456",
        model: "text-embedding-004",
        provider: :gemini,
        tokens: %{input: 50}
      }

      assert :ok = Command.handle_event([:altar, :ai, :embed, :stop], measurements, metadata, nil)
    end

    test "handles generate stop event (alias for text_gen)" do
      measurements = %{duration: 2_000_000}

      metadata = %{
        command_session_id: "test-session-789",
        command_workflow_id: "workflow-abc",
        model: "claude-sonnet-4",
        provider: :claude,
        tokens: %{prompt: 200, completion: 100}
      }

      assert :ok =
               Command.handle_event([:altar, :ai, :generate, :stop], measurements, metadata, nil)
    end
  end

  describe "calculate_cost/3" do
    test "calculates cost for GPT-4o" do
      # GPT-4o: $5/1M input, $15/1M output
      cost = Command.calculate_cost("gpt-4o", 1000, 500)
      expected = (1000 * 5.0 + 500 * 15.0) / 1_000_000
      assert_in_delta cost, expected, 0.0001
    end

    test "calculates cost for GPT-4o-mini" do
      # GPT-4o-mini: $0.15/1M input, $0.60/1M output
      cost = Command.calculate_cost("gpt-4o-mini", 10_000, 5_000)
      expected = (10_000 * 0.15 + 5_000 * 0.60) / 1_000_000
      assert_in_delta cost, expected, 0.0001
    end

    test "calculates cost for Claude Sonnet" do
      # Claude Sonnet: $3/1M input, $15/1M output
      cost = Command.calculate_cost("claude-3-sonnet-20240229", 5000, 2000)
      expected = (5000 * 3.0 + 2000 * 15.0) / 1_000_000
      assert_in_delta cost, expected, 0.0001
    end

    test "calculates cost for Claude Opus 4" do
      # Claude Opus: $15/1M input, $75/1M output
      cost = Command.calculate_cost("claude-opus-4-20250514", 1000, 1000)
      expected = (1000 * 15.0 + 1000 * 75.0) / 1_000_000
      assert_in_delta cost, expected, 0.0001
    end

    test "calculates cost for Gemini Pro" do
      # Gemini Pro: $0.50/1M input, $1.50/1M output
      cost = Command.calculate_cost("gemini-pro", 10_000, 5_000)
      expected = (10_000 * 0.50 + 5_000 * 1.50) / 1_000_000
      assert_in_delta cost, expected, 0.0001
    end

    test "calculates cost for Gemini 1.5 Flash" do
      # Gemini 1.5 Flash: $0.075/1M input, $0.30/1M output
      cost = Command.calculate_cost("gemini-1.5-flash", 100_000, 50_000)
      expected = (100_000 * 0.075 + 50_000 * 0.30) / 1_000_000
      assert_in_delta cost, expected, 0.0001
    end

    test "calculates cost for embedding models - output price is 0" do
      # text-embedding-004: $0.025/1M input, $0/1M output
      cost = Command.calculate_cost("text-embedding-004", 10_000, 0)
      expected = 10_000 * 0.025 / 1_000_000
      assert_in_delta cost, expected, 0.0001
    end

    test "returns nil for unknown model" do
      assert is_nil(Command.calculate_cost("unknown-model-xyz", 1000, 500))
    end

    test "returns nil for nil model" do
      assert is_nil(Command.calculate_cost(nil, 1000, 500))
    end

    test "returns 0.0 for zero tokens" do
      assert Command.calculate_cost("gpt-4o", 0, 0) == 0.0
    end

    test "handles o1 reasoning model" do
      # o1: $15/1M input, $60/1M output
      cost = Command.calculate_cost("o1", 1000, 500)
      expected = (1000 * 15.0 + 500 * 60.0) / 1_000_000
      assert_in_delta cost, expected, 0.0001
    end

    test "handles o3-mini reasoning model" do
      # o3-mini: $1.10/1M input, $4.40/1M output
      cost = Command.calculate_cost("o3-mini", 5000, 2000)
      expected = (5000 * 1.10 + 2000 * 4.40) / 1_000_000
      assert_in_delta cost, expected, 0.0001
    end
  end

  describe "telemetry event firing through Altar.AI" do
    setup do
      Command.attach_telemetry()
      on_exit(fn -> Command.detach_telemetry() end)

      # Set up a telemetry handler to capture events
      test_pid = self()
      ref = make_ref()

      handler_id = "test-handler-#{inspect(ref)}"

      :telemetry.attach(
        handler_id,
        [:altar, :ai, :text_gen, :stop],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      %{handler_id: handler_id}
    end

    test "Command handler receives telemetry events" do
      # Manually fire a telemetry event
      :telemetry.execute(
        [:altar, :ai, :text_gen, :stop],
        %{duration: 100_000},
        %{
          command_session_id: "test-123",
          model: "gpt-4o",
          provider: :openai,
          tokens: %{prompt: 10, completion: 5}
        }
      )

      # Our test handler should receive the event
      assert_receive {:telemetry_event, _measurements, metadata}
      assert metadata.command_session_id == "test-123"
    end
  end
end
