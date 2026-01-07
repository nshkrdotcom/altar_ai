defmodule Altar.AI.Integrations.Synapse do
  @moduledoc """
  Synapse integration module providing ReqLLM-compatible interface.

  This module provides a drop-in replacement for Synapse's ReqLLM module,
  allowing Synapse actions to use Altar.AI adapters seamlessly.

  ## Usage in Synapse Actions

      defmodule MyApp.Actions.GenerateCritique do
        use Jido.Action, name: "generate_critique", ...

        alias Altar.AI.Integrations.Synapse, as: LLM

        def run(params, context) do
          case LLM.chat_completion(%{prompt: params.prompt}, profile: :openai) do
            {:ok, response} -> {:ok, response}
            {:error, error} -> {:error, error}
          end
        end
      end

  ## Configuration

  The module can load configuration from the `:synapse` application environment:

      config :synapse, Synapse.ReqLLM,
        default_profile: :openai,
        profiles: %{
          openai: [model: "gpt-4", temperature: 0.7],
          gemini: [model: "gemini-pro"]
        }

  Or you can pass a config directly:

      config = Altar.AI.Integrations.Synapse.from_application_env()
      LLM.chat_completion(%{prompt: "Hello"}, config: config, profile: :openai)
  """

  alias Altar.AI.{Config, Telemetry}
  alias Altar.AI.{Generator, Response}

  @doc """
  Chat completion interface compatible with Synapse.ReqLLM.chat_completion/2.

  ## Parameters

    * `params` - Map with:
      * `:prompt` - The main prompt (required)
      * `:messages` - List of prior messages (optional)
      * `:temperature` - Sampling temperature (optional)
      * `:max_tokens` - Maximum tokens (optional)

    * `opts` - Options:
      * `:config` - An `Altar.AI.Config` struct (optional, defaults to loading from app env)
      * `:profile` - The profile to use (optional, defaults to config's default)

  ## Returns

    * `{:ok, response}` - On success, response contains:
      * `:content` - Generated text
      * `:metadata` - Map with `:total_tokens` if available
    * `{:error, error}` - On failure

  ## Examples

      {:ok, response} = chat_completion(%{prompt: "What is 2+2?"}, profile: :openai)

      # With messages
      {:ok, response} = chat_completion(%{
        prompt: "What is AI?",
        messages: [%{role: "system", content: "You are an expert."}]
      })
  """
  @spec chat_completion(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def chat_completion(params, opts \\ []) do
    config = Keyword.get_lazy(opts, :config, &from_application_env/0)
    profile = Keyword.get(opts, :profile, config.default_profile)

    prompt = build_prompt(params, config, profile)
    call_opts = build_call_opts(params, config, profile)

    with_adapter(config, profile, fn adapter ->
      metadata =
        %{provider: adapter_name(adapter), profile: profile}
        |> Map.merge(extract_command_metadata(opts))

      Telemetry.span(:generate, metadata, fn ->
        generate_response(adapter, prompt, call_opts)
      end)
    end)
  end

  @doc """
  Simple generate interface.

  ## Options

    * `:config` - Config struct (optional)
    * `:profile` - Profile to use (optional)
    * Other options passed through to adapter

  ## Examples

      {:ok, response} = generate("Hello world", profile: :gemini)
  """
  @spec generate(String.t(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  def generate(prompt, opts \\ []) do
    config = Keyword.get_lazy(opts, :config, &from_application_env/0)
    {profile, call_opts} = Keyword.pop(opts, :profile, config.default_profile)

    resolved_opts =
      call_opts
      |> Keyword.delete(:config)
      |> then(&Config.resolve_opts(config, profile, &1))

    with_adapter(config, profile, fn adapter ->
      metadata =
        %{provider: adapter_name(adapter), profile: profile}
        |> Map.merge(extract_command_metadata(opts))

      Telemetry.span(:generate, metadata, fn ->
        Generator.generate(adapter, prompt, resolved_opts)
      end)
    end)
  end

  @doc """
  Streaming generate interface.

  ## Options

    * `:config` - Config struct (optional)
    * `:profile` - Profile to use (optional)
    * Other options passed through to adapter

  ## Examples

      {:ok, stream} = stream("Tell me a story", profile: :openai)
      Enum.each(stream, &IO.write/1)
  """
  @spec stream(String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(prompt, opts \\ []) do
    config = Keyword.get_lazy(opts, :config, &from_application_env/0)
    {profile, call_opts} = Keyword.pop(opts, :profile, config.default_profile)

    resolved_opts =
      call_opts
      |> Keyword.delete(:config)
      |> then(&Config.resolve_opts(config, profile, &1))

    with_adapter(config, profile, fn adapter ->
      metadata =
        %{provider: adapter_name(adapter), profile: profile, streaming: true}
        |> Map.merge(extract_command_metadata(opts))

      Telemetry.span(:generate, metadata, fn ->
        Generator.stream(adapter, prompt, resolved_opts)
      end)
    end)
  end

  @doc """
  Converts Synapse ReqLLM configuration format to Altar.AI.Config.

  ## Synapse Config Format

      %{
        default_profile: :openai,
        system_prompt: "You are helpful.",
        profiles: %{
          openai: [model: "gpt-4", temperature: 0.7],
          gemini: [model: "gemini-pro"]
        }
      }

  ## Examples

      config = from_synapse_config(synapse_config)
  """
  @spec from_synapse_config(map()) :: Config.t()
  def from_synapse_config(synapse_config) when is_map(synapse_config) do
    default_profile = Map.get(synapse_config, :default_profile, :default)
    profiles = Map.get(synapse_config, :profiles, %{})
    system_prompt = Map.get(synapse_config, :system_prompt)

    global_opts =
      if system_prompt do
        [system_prompt: system_prompt]
      else
        []
      end

    Config.new(
      default_profile: default_profile,
      profiles: profiles,
      global_opts: global_opts
    )
  end

  @doc """
  Loads configuration from the `:synapse` application environment.

  Reads from `config :synapse, Synapse.ReqLLM, ...`.

  ## Examples

      config = from_application_env()
  """
  @spec from_application_env() :: Config.t()
  def from_application_env do
    synapse_config =
      Application.get_env(:synapse, Synapse.ReqLLM, [])
      |> Map.new()

    from_synapse_config(synapse_config)
  end

  # Private helpers

  defp build_prompt(params, config, profile) do
    messages = Map.get(params, :messages, [])
    main_prompt = Map.get(params, :prompt, "")
    system_prompt = Config.system_prompt(config, profile)

    # Build combined prompt from system + messages + main prompt
    parts = []

    parts =
      if system_prompt do
        ["[system]: #{system_prompt}" | parts]
      else
        parts
      end

    parts =
      Enum.reduce(messages, parts, fn msg, acc ->
        role = Map.get(msg, :role, Map.get(msg, "role", "user"))
        content = Map.get(msg, :content, Map.get(msg, "content", ""))
        ["[#{role}]: #{content}" | acc]
      end)

    parts = [main_prompt | parts]

    parts
    |> Enum.reverse()
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp build_call_opts(params, config, profile) do
    base_opts = Config.resolve_opts(config, profile, [])

    param_opts =
      params
      |> Map.take([:temperature, :max_tokens, :model])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.to_list()

    Keyword.merge(base_opts, param_opts)
  end

  defp normalize_response(%Response{} = response) do
    metadata = %{total_tokens: response.tokens.total}

    %{
      content: response.content,
      model: response.model,
      provider: response.provider,
      finish_reason: response.finish_reason,
      metadata: metadata
    }
  end

  defp generate_response(adapter, prompt, opts) do
    case Generator.generate(adapter, prompt, opts) do
      {:ok, response} -> {:ok, normalize_response(response)}
      {:error, _} = error -> error
    end
  end

  defp adapter_name(adapter) when is_struct(adapter) do
    adapter.__struct__
    |> Module.split()
    |> List.last()
    |> String.downcase()
    |> String.to_atom()
  end

  defp adapter_name(_), do: :unknown

  defp with_adapter(config, profile, fun) do
    case Config.get_adapter(config, profile) do
      nil ->
        {:error,
         %Altar.AI.Error{type: :invalid_request, message: "No adapter for profile #{profile}"}}

      adapter ->
        fun.(adapter)
    end
  end

  defp extract_command_metadata(opts) do
    [:command_session_id, :command_workflow_id, :command_user_id, :correlation_id, :request_id]
    |> Enum.reduce(%{}, fn key, acc ->
      case Keyword.get(opts, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end
end
