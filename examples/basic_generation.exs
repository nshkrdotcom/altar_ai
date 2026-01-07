# Basic Altar.AI usage with the Mock adapter.
#
# Run:
#   mix run examples/basic_generation.exs

alias Altar.AI.{Client, Config}
alias Altar.AI.Adapters.{Fallback, Mock}

config =
  Config.new()
  |> Config.add_profile(:mock, adapter: Mock.new())
  |> Config.add_profile(:fallback, adapter: Fallback.new())
  |> Map.put(:default_profile, :mock)

client = Client.new(config: config)

{:ok, response} =
  Client.generate(client, "Explain Elixir pattern matching in one sentence.")

IO.puts("Generate: #{response.content}")

{:ok, embedding} = Client.embed(client, "Elixir")
IO.puts("Embedding size: #{length(embedding)}")

{:ok, classification} = Client.classify(client, "I love Elixir", ["positive", "negative"])
IO.puts("Classification: #{classification.label} (#{classification.confidence})")

{:ok, stream} = Client.stream(client, "Stream demo")
IO.puts("Stream:")
Enum.each(stream, &IO.puts/1)
