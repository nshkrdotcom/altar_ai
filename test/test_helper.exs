# Start the application for testing
{:ok, _} = Application.ensure_all_started(:altar_ai)

# Configure ExUnit
ExUnit.start()

# Mox for mocking
Mox.defmock(Altar.AI.Test.MockProvider, for: Altar.AI.Behaviours.TextGen)
Mox.defmock(Altar.AI.Test.MockEmbedProvider, for: Altar.AI.Behaviours.Embed)
Mox.defmock(Altar.AI.Test.MockClassifyProvider, for: Altar.AI.Behaviours.Classify)
Mox.defmock(Altar.AI.Test.MockCodeProvider, for: Altar.AI.Behaviours.CodeGen)
