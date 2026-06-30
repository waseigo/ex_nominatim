# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.Client do
  alias ExNominatim.Client.{Cache, Geohash, Request}
  alias ExNominatim.{Report, Validations}

  @config ExNominatim.get_config()
  @config_specific_keys [
    :base_url, :force, :process, :atomize, :cache, :test_adapter, :rate_limit,
    :rate_limit_retry, :req_opts, :geohash,
    :timeout, :user_agent, :retry, :circuit_breaker, :max_concurrency,
    :cache_errors, :cache_error_ttl
  ]
  @validation_keys [:errors, :valid?]
  @endpoints [:search, :reverse, :status, :lookup, :details]

  @moduledoc """
  Functions for preparing an HTTP request, including validating the base URL of the target Nominatim API server setting the User-Agent header automatically, selecting all the non-nil request parameters, creating a validated request, and dispatching it to the requested endpoint.

  The `opts` keyword list of the endpoint request functions can optionally include the following:
  * `:base_url` with a string value setting the base URL of the target Nominatim API server (it defaults to the public server).
  * `:force` with a boolean value, where `true` means that validation errors will be ignored and the HTTP GET request to the API will run regardless.

  """
  @moduledoc since: "1.0.0"

  @doc """
  Use the `/search` API endpoint. Delegated to from `ExNominatim.search/1`, which is documented.
  """
  def search(opts), do: generic(:search, opts)

  @doc """
  Use the `/reverse` API endpoint. Delegated to from `ExNominatim.reverse/1`, which is documented.
  """
  def reverse(opts), do: generic(:reverse, opts)

  @doc """
  Use the `/lookup` API endpoint. Delegated to from `ExNominatim.lookup/1`, which is documented.
  """
  def lookup(opts), do: generic(:lookup, opts)

  @doc """
  Use the `/details` API endpoint. Delegated to from `ExNominatim.details/1`, which is documented.
  """
  def details(opts), do: generic(:details, opts)

  @doc """
  Use the `/status` API endpoint. Delegated to from `ExNominatim.status/1`, which is documented.
  """
  def status(opts), do: generic(:status, opts)

  @doc """
  Use the `/status` API endpoint without setting any request parameters. Delegated to from `ExNominatim.status/0`, which is documented.
  """
  def status, do: generic(:status, [])

  # ---- Pipeline ----

  defp generic(action, opts) when is_list(opts) and action in @endpoints do
    with {:keyword?, true} <- {:keyword?, Keyword.keyword?(opts)},
         {:new, {:ok, {m, config_opts}}} when is_struct(m) <-
           {:new, make_new_struct(opts, action)} do
      cache = Keyword.get(config_opts, :cache)
      key = Cache.key(action, m, @validation_keys)
      base_url = Keyword.get(config_opts, :base_url)

      case Cache.get(cache, key) do
        {:ok, data} ->
          ExNominatim.Telemetry.cache_hit(action)
          {:ok, data}

        {:error, _} = cached_error ->
          ExNominatim.Telemetry.cache_hit(action)
          cached_error

        :miss ->
          ExNominatim.Telemetry.cache_miss(action)
          handle_cache_miss(action, m, config_opts, cache, key, base_url)
      end
    else
      {:keyword?, false} -> {:error, %{code: :validation, descr: "Opts must be a keyword list"}}
      {:new, {:error, reason}} -> {:error, reason}
    end
  end

  defp handle_cache_miss(action, m, config_opts, cache, key, base_url) do
    case ExNominatim.CircuitBreaker.check(base_url, config_opts) do
      :ok ->
        do_request_with_retry(action, m, config_opts, cache, key)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---- Rate-limit-aware retry loop (pre-HTTP) ----

  defp do_request_with_retry(action, m, config_opts, cache, key) do
    base_url = config_opts[:base_url]

    case check_rate_limit(config_opts) do
      :ok ->
        case ExNominatim.Concurrency.acquire(base_url, config_opts) do
          :ok ->
            result = execute_with_network_retry(action, m, config_opts, cache, key, 1)
            ExNominatim.Concurrency.release(base_url)
            result

          {:error, reason} ->
            {:error, reason}
        end

      {:error, %{code: :rate_limited, retry_after_ms: retry_after}} ->
        ExNominatim.Telemetry.rate_limit_deny(action, base_url, retry_after)

        if rate_limit_retries_left?(config_opts) do
          Process.sleep(retry_after)
          do_request_with_retry(action, m, config_opts, cache, key)
        else
          {:error,
           %{code: :rate_limited, descr: "Rate limit exceeded", retry_after_ms: retry_after}}
        end
    end
  end

  defp rate_limit_retries_left?(config_opts) do
    # Rate-limit retry uses the existing :rate_limit_retry config as an
    # *attempt budget* similar to the legacy approach — any positive value
    # means "retry at least once".
    case Keyword.get(config_opts, :rate_limit_retry, false) do
      true -> true
      n when is_integer(n) and n > 0 -> true
      _ -> false
    end
  end

  # ---- Network-level retry loop (post-HTTP, for transport / 5xx) ----

  defp execute_with_network_retry(action, m, config_opts, cache, key, attempt) do
    base_url = config_opts[:base_url]
    start = System.monotonic_time()
    result = generic_request(action, m, config_opts)
    result = Geohash.add(result, config_opts)
    duration = System.monotonic_time() - start

    case result do
      {:ok, %{status: status} = data} ->
        :telemetry.execute([:ex_nominatim, :request, :stop], %{duration: duration}, %{
          endpoint: action, base_url: base_url, status: status
        })
        ExNominatim.CircuitBreaker.record_success(base_url)
        Cache.store(cache, key, {:ok, data})
        {:ok, data}

      {:error, reason} ->
        :telemetry.execute([:ex_nominatim, :request, :exception], %{duration: duration}, %{
          endpoint: action, base_url: base_url, error: reason
        })

        if retryable_error?(result) and attempt < network_max_attempts(config_opts) do
          ExNominatim.Telemetry.retry_attempt(action, base_url, attempt, reason)
          backoff_ms = network_backoff(attempt, config_opts)
          Process.sleep(backoff_ms)
          execute_with_network_retry(action, m, config_opts, cache, key, attempt + 1)
        else
          ExNominatim.CircuitBreaker.record_failure(base_url, config_opts)
          Cache.store_error(cache, key, result, config_opts)
          result
        end
    end
  end

  defp retryable_error?({:error, %{code: :api_error, status: status}}) when status >= 500, do: true
  defp retryable_error?({:error, %{code: :api_error, status: 429}}), do: true
  defp retryable_error?({:error, %{code: :api_error}}), do: false
  defp retryable_error?({:error, %{code: _other}}), do: false
  defp retryable_error?({:error, _}), do: true

  defp network_max_attempts(config_opts) do
    case Keyword.get(config_opts, :retry, false) do
      false -> 1
      true -> 4
      n when is_integer(n) and n > 0 -> min(n + 1, 10)
      opts when is_list(opts) -> (Keyword.get(opts, :max_retries, 3) || 3) + 1
    end
  end

  defp network_backoff(attempt, config_opts) do
    retry_config = Keyword.get(config_opts, :retry, false)

    base_delay =
      if is_list(retry_config), do: Keyword.get(retry_config, :base_delay, 100), else: 100

    max_delay =
      if is_list(retry_config), do: Keyword.get(retry_config, :max_delay, 5_000), else: 5_000

    jitter? =
      if is_list(retry_config), do: Keyword.get(retry_config, :jitter, true), else: true

    delay = min(max_delay, base_delay * 2 ** (attempt - 1))

    if jitter? do
      trunc(delay * (1 + :rand.uniform() * 0.5))
    else
      delay
    end
  end

  # ---- Struct construction ----

  defp make_new_struct(opts, action) do
    provided = Keyword.keys(opts) -- @config_specific_keys
    module = get_module(action)

    extraneous = provided -- permitted_keys(struct(module))

    if extraneous != [] do
      {:error,
       %{
         code: :validation,
         descr: "Extraneous fields: #{inspect(extraneous)}",
         extraneous_fields: extraneous
       }}
    else
      app_config = ExNominatim.get_config()

      opts_new =
        @config[:all]
        |> Keyword.merge(app_config[action])
        |> Keyword.merge(app_config[:all])
        |> Keyword.merge(opts)

      config_opts = Keyword.take(opts_new, @config_specific_keys)

      case module.new(opts_new) do
        {:ok, m} when is_struct(m) ->
          {:ok, {m, config_opts}}

        {:error, v} ->
          {:error, v}
      end
    end
  end

  defp permitted_keys(m) when is_struct(m) do
    m |> Map.from_struct() |> Map.keys() |> Kernel.--(@validation_keys)
  end

  # ---- HTTP request ---- #

  defp generic_request(action, params_struct, config_opts)
       when action in @endpoints and is_struct(params_struct) and is_list(config_opts) do
    s = get_module(action)

    force? = Keyword.get(config_opts, :force)
    base_url = Keyword.get(config_opts, :base_url)
    process? = Keyword.get(config_opts, :process)
    atomize? = Keyword.get(config_opts, :atomize)
    test_adapter = Keyword.get(config_opts, :test_adapter)

    # skip validation if force: true in config_opts
    maybe_validated =
      if force?, do: {:ok, params_struct}, else: Validations.validate(params_struct)

    with {:ok, %^s{} = maybe_valid_params} <- maybe_validated,
         {:ok, %Req.Request{} = req} <- prepare(action, maybe_valid_params, base_url),
         req <- Request.apply_req_opts(req, config_opts),
         req <- Request.apply_http_options(req, config_opts),
         {:ok, %Req.Response{} = resp} <-
           req |> maybe_attach_adapter(test_adapter) |> Req.request() do
      output = {:ok, resp}

      case {process?, atomize?} do
        {true, true} ->
          {status, processed} = Report.process(output)
          {status, Report.atomize(processed)}

        {true, false} ->
          Report.process(output)

        {false, true} ->
          {status, unprocessed} = output
          {status, Report.atomize(unprocessed)}

        {false, false} ->
          output
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_module(action) when action in @endpoints do
    [
      __MODULE__,
      action |> to_string() |> Kernel.<>("_params") |> Macro.camelize() |> String.to_atom()
    ]
    |> Module.safe_concat()
  end

  @doc """
  Create a new request params struct from the provided keyword list `opts`, taking into account any required fields listed as atoms in the `required` list. Delegated to from the `new/1` functions of the modules of `SearchParams`, `ReverseParams`, etc. (the `module`).
  """
  def new(opts, required, module) when is_list(opts) and is_list(required) and is_atom(module) do
    with {:keyword?, true} <- {:keyword?, Keyword.keyword?(opts)},
         {:required, ^required} <-
           {:required, opts |> Keyword.take(required) |> Keyword.keys()} do
      new(Map.new(opts), module)
    else
      {:keyword?, false} -> {:error, %{code: :validation, descr: "Opts must be a keyword list"}}
      {:required, _} ->
        {:error, %{code: :validation, descr: "Missing required parameters: #{inspect(required)}", missing: required}}
    end
  end

  defp new(params, module) when is_map(params) and is_atom(module) do
    {:ok, module |> struct() |> Map.merge(params)}
  end

  # ---- HTTP request preparation ----

  @doc """
  Prepares an HTTP request to the `endpoint` at `base_url` with the `params` map containing request parameters.

  * `endpoint` is one of `:search`, `:reverse`, `:lookup`, `:status`, `:details`.
  * `params` is a map (not a keyword list!) with the request parameters.
  * `base_url` is the the base URL of the target Nominatim API server.

  You can use this function directly if you want to bypass the more user-friendly delegate functions in the main ExNominatim module and define the `params` map directly. This function does not perform any validation of the validity of the keys in `params` for the selected endpoint, or of their respective values vs. the API endpoint's specification.
  """

  def prepare(endpoint, params, base_url)
      when endpoint in @endpoints and is_map(params) and params != %{} and is_binary(base_url) do
    case Request.base(base_url) do
      {:ok, %Req.Request{} = req} ->
        params = keep_query_params(params)

        {:ok,
         req
         |> Req.merge(url: endpoint_url(endpoint))
         |> Req.merge(params: params)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def prepare(endpoint, _, _) when not is_atom(endpoint) and endpoint not in @endpoints do
    {:error, %{code: :validation, descr: "Invalid endpoint: #{inspect(endpoint)}"}}
  end

  def prepare(_, params, _) when params == %{} do
    {:error, %{code: :validation, descr: "Params must not be empty"}}
  end

  def prepare(_, params, _) when not is_map(params) do
    {:error, %{code: :validation, descr: "Params must be a map"}}
  end

  defp endpoint_url(endpoint) when is_atom(endpoint), do: to_string(endpoint)

  defp keep_query_params(m) when is_struct(m) do
    m |> Map.from_struct() |> keep_query_params()
  end

  defp keep_query_params(m) when is_map(m) do
    Map.filter(m, fn {k, v} ->
      not (is_nil(v) or k in (@validation_keys ++ @config_specific_keys))
    end)
  end

  # --- Rate limiting ---

  defp check_rate_limit(config_opts) do
    base_url = Keyword.get(config_opts, :base_url)

    case Keyword.get(config_opts, :rate_limit, :auto) do
      false ->
        :ok

      :auto ->
        if ExNominatim.RateLimiter.public_server?(base_url) do
          ExNominatim.RateLimiter.check(base_url, 1000)
        else
          :ok
        end

      true ->
        ExNominatim.RateLimiter.check(base_url, 1000)

      rps when is_integer(rps) and rps > 0 ->
        ExNominatim.RateLimiter.check(base_url, max(1, round(1000 / rps)))

      _ ->
        :ok
    end
  end

  # --- Test adapter ---

  defp maybe_attach_adapter(req, nil), do: req

  defp maybe_attach_adapter(req, {Req.Test, _module} = adapter) do
    req |> Req.merge(plug: adapter) |> Req.merge(retry: false)
  end

  defp maybe_attach_adapter(req, plug_module) when is_atom(plug_module) do
    req |> Req.merge(plug: plug_module) |> Req.merge(retry: false)
  end

end
