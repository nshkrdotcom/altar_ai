defmodule Altar.AI.Integrations.FlowStone.TelemetryTest do
  use ExUnit.Case, async: false

  alias Altar.AI.Integrations.FlowStone.Telemetry

  setup do
    # Ensure handlers are detached before each test
    Telemetry.detach()
    :ok
  end

  describe "attach/0" do
    test "attaches telemetry handlers" do
      assert :ok = Telemetry.attach()
    end

    test "is idempotent - does not error on multiple attaches" do
      assert :ok = Telemetry.attach()
      # Second attach should not raise (telemetry replaces existing handler)
      assert :ok = Telemetry.attach()
    end
  end

  describe "detach/0" do
    test "detaches handlers when attached" do
      Telemetry.attach()
      assert :ok = Telemetry.detach()
    end

    test "returns error when not attached" do
      assert {:error, :not_found} = Telemetry.detach()
    end
  end

  describe "event forwarding" do
    setup do
      Telemetry.attach()

      test_pid = self()

      handler_id = "test-flowstone-handler-#{System.unique_integer()}"

      :telemetry.attach_many(
        handler_id,
        [
          [:flowstone, :ai, :generate, :start],
          [:flowstone, :ai, :generate, :stop],
          [:flowstone, :ai, :generate, :exception],
          [:flowstone, :ai, :embed, :start],
          [:flowstone, :ai, :embed, :stop],
          [:flowstone, :ai, :embed, :exception]
        ],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
        Telemetry.detach()
      end)

      :ok
    end

    test "forwards [:altar, :ai, :generate, :start] events" do
      measurements = %{system_time: System.system_time()}
      metadata = %{adapter: :test, prompt: "test prompt"}

      :telemetry.execute([:altar, :ai, :generate, :start], measurements, metadata)

      assert_receive {:telemetry_event, [:flowstone, :ai, :generate, :start], ^measurements,
                      ^metadata}
    end

    test "forwards [:altar, :ai, :generate, :stop] events" do
      measurements = %{duration: 1000}
      metadata = %{adapter: :test}

      :telemetry.execute([:altar, :ai, :generate, :stop], measurements, metadata)

      assert_receive {:telemetry_event, [:flowstone, :ai, :generate, :stop], ^measurements,
                      ^metadata}
    end

    test "forwards [:altar, :ai, :generate, :exception] events" do
      measurements = %{duration: 500}
      metadata = %{kind: :error, reason: :timeout, stacktrace: []}

      :telemetry.execute([:altar, :ai, :generate, :exception], measurements, metadata)

      assert_receive {:telemetry_event, [:flowstone, :ai, :generate, :exception], ^measurements,
                      ^metadata}
    end

    test "forwards [:altar, :ai, :embed, :start] events" do
      measurements = %{system_time: System.system_time()}
      metadata = %{adapter: :test, text: "test text"}

      :telemetry.execute([:altar, :ai, :embed, :start], measurements, metadata)

      assert_receive {:telemetry_event, [:flowstone, :ai, :embed, :start], ^measurements,
                      ^metadata}
    end

    test "forwards [:altar, :ai, :embed, :stop] events" do
      measurements = %{duration: 2000}
      metadata = %{adapter: :test}

      :telemetry.execute([:altar, :ai, :embed, :stop], measurements, metadata)

      assert_receive {:telemetry_event, [:flowstone, :ai, :embed, :stop], ^measurements,
                      ^metadata}
    end

    test "forwards [:altar, :ai, :embed, :exception] events" do
      measurements = %{duration: 300}
      metadata = %{kind: :error, reason: :rate_limit, stacktrace: []}

      :telemetry.execute([:altar, :ai, :embed, :exception], measurements, metadata)

      assert_receive {:telemetry_event, [:flowstone, :ai, :embed, :exception], ^measurements,
                      ^metadata}
    end

    test "preserves all metadata" do
      measurements = %{system_time: 123, custom: "value"}
      metadata = %{adapter: :gemini, prompt: "test", nested: %{key: "value"}, list: [1, 2, 3]}

      :telemetry.execute([:altar, :ai, :generate, :start], measurements, metadata)

      assert_receive {:telemetry_event, [:flowstone, :ai, :generate, :start],
                      received_measurements, received_metadata}

      assert received_measurements == measurements
      assert received_metadata == metadata
    end
  end
end
