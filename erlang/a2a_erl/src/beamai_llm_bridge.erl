%%%-------------------------------------------------------------------
%%% @doc BeamAI LLM Bridge.
%%%
%%% Bridge connecting existing YAWL LLM modules to the BeamAI LLM
%%% subsystem. Provides a unified interface that delegates to either
%%% the legacy modules (yawl_claude_headless, yawl_llm_validator,
%%% yawl_model_comparison) or the new BeamAI LLM adapters, depending
%%% on availability and configuration.
%%%
%%% This enables gradual migration: existing code continues to work
%%% through the bridge while new code uses BeamAI APIs directly.
%%%
%%% Responsibilities:
%%% - Connect yawl_claude_headless to beamai_llm_anthropic adapter
%%% - Connect yawl_llm_validator to beamai_output_parser
%%% - Provide unified LLM interface for both old and new code
%%% - Route requests to the appropriate backend
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_llm_bridge).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    chat/2,
    chat/3,
    validate/2,
    validate/3,
    compare_models/2,
    compare_models/3,
    get_provider/1,
    list_providers/0,
    generate_model/1,
    generate_model/2,
    parse_output/2,
    get_status/0
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-define(SERVER, ?MODULE).

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    mode           :: legacy | beamai | hybrid,
    default_provider :: atom(),
    provider_map   :: #{atom() => {module(), map()}},
    legacy_available :: boolean(),
    beamai_available :: boolean(),
    request_count  :: non_neg_integer(),
    error_count    :: non_neg_integer()
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the LLM bridge with default configuration.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the LLM bridge with custom configuration.
%% Options:
%%   mode - 'legacy', 'beamai', or 'hybrid' (default: 'hybrid')
%%   default_provider - Default LLM provider atom (default: anthropic)
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

%% @doc Send a chat message using the default provider.
-spec chat(atom(), binary() | list()) ->
    {ok, binary() | map()} | {error, term()}.
chat(Provider, Message) ->
    chat(Provider, Message, #{}).

%% @doc Send a chat message with options.
-spec chat(atom(), binary() | list(), map()) ->
    {ok, binary() | map()} | {error, term()}.
chat(Provider, Message, Opts) ->
    gen_server:call(?SERVER, {chat, Provider, Message, Opts}, 120000).

%% @doc Validate an LLM-generated model against evidence.
%% Delegates to yawl_llm_validator or beamai_output_parser depending on mode.
-spec validate(map(), map()) -> map() | {ok, map()} | {error, term()}.
validate(Model, Evidence) ->
    validate(Model, Evidence, #{}).

%% @doc Validate with options.
-spec validate(map(), map(), map()) -> map() | {ok, map()} | {error, term()}.
validate(Model, Evidence, Opts) ->
    gen_server:call(?SERVER, {validate, Model, Evidence, Opts}, 60000).

%% @doc Compare two models using yawl_model_comparison.
-spec compare_models(map(), map()) -> map() | {error, term()}.
compare_models(Model1, Model2) ->
    compare_models(Model1, Model2, #{}).

%% @doc Compare models with options.
-spec compare_models(map(), map(), map()) -> map() | {error, term()}.
compare_models(Model1, Model2, Opts) ->
    gen_server:call(?SERVER, {compare_models, Model1, Model2, Opts}, 60000).

%% @doc Get the provider module for a given provider name.
%% Returns the module and its configuration.
-spec get_provider(atom()) -> {ok, {module(), map()}} | {error, not_found}.
get_provider(Provider) ->
    gen_server:call(?SERVER, {get_provider, Provider}).

%% @doc List all available providers.
-spec list_providers() -> [atom()].
list_providers() ->
    gen_server:call(?SERVER, list_providers).

%% @doc Generate a process model from a text description.
%% Uses either yawl_llm_validator or beamai_chat_completion.
-spec generate_model(binary()) -> {ok, map()} | {error, term()}.
generate_model(Description) ->
    generate_model(Description, #{}).

%% @doc Generate a model with options.
-spec generate_model(binary(), map()) -> {ok, map()} | {error, term()}.
generate_model(Description, Opts) ->
    gen_server:call(?SERVER, {generate_model, Description, Opts}, 120000).

%% @doc Parse LLM output using beamai_output_parser.
%% Format is one of: json, xml, csv, pattern.
-spec parse_output(atom(), binary()) -> {ok, term()} | {error, term()}.
parse_output(Format, Text) ->
    case Format of
        json -> beamai_output_parser:parse_json(Text);
        xml  -> beamai_output_parser:parse_xml(Text);
        csv  -> beamai_output_parser:parse_csv(Text);
        _    -> {error, {unsupported_format, Format}}
    end.

%% @doc Get bridge status.
-spec get_status() -> map().
get_status() ->
    gen_server:call(?SERVER, get_status).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init(Opts) ->
    Mode = maps:get(mode, Opts, hybrid),
    DefaultProvider = maps:get(default_provider, Opts, anthropic),

    %% Check availability of legacy and BeamAI modules
    LegacyAvailable = check_module_available(yawl_claude_headless),
    BeamAIAvailable = check_module_available(beamai_chat_completion),

    %% Build provider map
    ProviderMap = build_provider_map(Mode, LegacyAvailable, BeamAIAvailable),

    logger:info("BeamAI LLM bridge started (mode: ~p, legacy: ~p, beamai: ~p)",
                [Mode, LegacyAvailable, BeamAIAvailable]),

    {ok, #state{
        mode = Mode,
        default_provider = DefaultProvider,
        provider_map = ProviderMap,
        legacy_available = LegacyAvailable,
        beamai_available = BeamAIAvailable,
        request_count = 0,
        error_count = 0
    }}.

%% @private
handle_call({chat, Provider, Message, Opts}, _From, State) ->
    Result = do_chat(Provider, Message, Opts, State),
    NewState = update_counters(Result, State),
    {reply, Result, NewState};

handle_call({validate, Model, Evidence, Opts}, _From, State) ->
    Result = do_validate(Model, Evidence, Opts, State),
    NewState = update_counters(Result, State),
    {reply, Result, NewState};

handle_call({compare_models, Model1, Model2, Opts}, _From, State) ->
    Result = do_compare_models(Model1, Model2, Opts, State),
    {reply, Result, State};

handle_call({get_provider, Provider}, _From, #state{provider_map = Map} = State) ->
    Result = case maps:find(Provider, Map) of
        {ok, ProviderInfo} -> {ok, ProviderInfo};
        error -> {error, not_found}
    end,
    {reply, Result, State};

handle_call(list_providers, _From, #state{provider_map = Map} = State) ->
    {reply, maps:keys(Map), State};

handle_call({generate_model, Description, Opts}, _From, State) ->
    Result = do_generate_model(Description, Opts, State),
    NewState = update_counters(Result, State),
    {reply, Result, NewState};

handle_call(get_status, _From, State) ->
    Status = #{
        mode => State#state.mode,
        default_provider => State#state.default_provider,
        legacy_available => State#state.legacy_available,
        beamai_available => State#state.beamai_available,
        providers => maps:keys(State#state.provider_map),
        request_count => State#state.request_count,
        error_count => State#state.error_count
    },
    {reply, Status, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions - Chat
%%====================================================================

%% @private
do_chat(Provider, Message, Opts, #state{mode = Mode} = State) ->
    ResolvedProvider = case Provider of
        default -> State#state.default_provider;
        P -> P
    end,
    case Mode of
        legacy ->
            do_chat_legacy(Message, Opts);
        beamai ->
            do_chat_beamai(ResolvedProvider, Message, Opts);
        hybrid ->
            %% Try BeamAI first, fall back to legacy
            case State#state.beamai_available of
                true ->
                    case do_chat_beamai(ResolvedProvider, Message, Opts) of
                        {ok, _} = Success -> Success;
                        {error, _} ->
                            case State#state.legacy_available of
                                true -> do_chat_legacy(Message, Opts);
                                false -> {error, no_provider_available}
                            end
                    end;
                false ->
                    case State#state.legacy_available of
                        true -> do_chat_legacy(Message, Opts);
                        false -> {error, no_provider_available}
                    end
            end
    end.

%% @private
do_chat_legacy(Message, Opts) ->
    MessageBin = ensure_binary(Message),
    LegacyOpts = maps:fold(fun(K, V, Acc) ->
        case K of
            system_prompt -> [{append_system_prompt, V} | Acc];
            timeout -> [{timeout, V} | Acc];
            output_format -> [{output_format, V} | Acc];
            _ -> Acc
        end
    end, [], Opts),
    try
        yawl_claude_headless:llm_generate(MessageBin, LegacyOpts)
    catch
        _:Reason -> {error, {legacy_error, Reason}}
    end.

%% @private
do_chat_beamai(Provider, Message, Opts) ->
    try
        beamai_chat_completion:complete(Provider, Message, Opts)
    catch
        _:Reason -> {error, {beamai_error, Reason}}
    end.

%%====================================================================
%% Internal Functions - Validation
%%====================================================================

%% @private
do_validate(Model, Evidence, Opts, #state{mode = Mode} = State) ->
    case Mode of
        legacy ->
            do_validate_legacy(Model, Evidence);
        beamai ->
            do_validate_beamai(Model, Evidence, Opts);
        hybrid ->
            %% Use legacy validator for XES-based validation (it's specialized)
            %% Use BeamAI parser for output format validation
            case maps:get(validation_type, Opts, xes) of
                xes ->
                    case State#state.legacy_available of
                        true -> do_validate_legacy(Model, Evidence);
                        false -> do_validate_beamai(Model, Evidence, Opts)
                    end;
                output ->
                    do_validate_beamai(Model, Evidence, Opts);
                _ ->
                    do_validate_legacy(Model, Evidence)
            end
    end.

%% @private
do_validate_legacy(Model, Evidence) ->
    try
        Result = yawl_llm_validator:validate_against_xes(Model, Evidence),
        {ok, Result}
    catch
        _:Reason -> {error, {legacy_validation_error, Reason}}
    end.

%% @private
do_validate_beamai(Model, _Evidence, Opts) ->
    %% Use output parser for structured validation
    Format = maps:get(format, Opts, json),
    ModelBin = case Model of
        M when is_binary(M) -> M;
        M when is_map(M) -> jsx:encode(M)
    end,
    case Format of
        json -> beamai_output_parser:parse_json(ModelBin);
        xml  -> beamai_output_parser:parse_xml(ModelBin);
        _ -> {ok, Model}
    end.

%%====================================================================
%% Internal Functions - Model Comparison
%%====================================================================

%% @private
do_compare_models(Model1, Model2, Opts, _State) ->
    try
        Metric = maps:get(metric, Opts, combined),
        case Metric of
            structural ->
                #{structural => yawl_model_comparison:structural_similarity(Model1, Model2)};
            behavioral ->
                #{behavioral => yawl_model_comparison:behavioral_similarity(Model1, Model2)};
            textual ->
                #{textual => yawl_model_comparison:textual_similarity(Model1, Model2)};
            combined ->
                #{
                    structural => yawl_model_comparison:structural_similarity(Model1, Model2),
                    behavioral => yawl_model_comparison:behavioral_similarity(Model1, Model2),
                    textual => yawl_model_comparison:textual_similarity(Model1, Model2),
                    combined => yawl_model_comparison:combined_similarity(Model1, Model2)
                };
            diff ->
                yawl_model_comparison:compute_diff(Model1, Model2);
            alignment ->
                {Alignment, Score} = yawl_model_comparison:optimal_alignment(Model1, Model2),
                #{alignment => Alignment, score => Score}
        end
    catch
        _:Reason -> {error, {comparison_error, Reason}}
    end.

%%====================================================================
%% Internal Functions - Model Generation
%%====================================================================

%% @private
do_generate_model(Description, Opts, #state{mode = Mode} = State) ->
    case Mode of
        legacy ->
            do_generate_model_legacy(Description);
        beamai ->
            do_generate_model_beamai(Description, Opts, State);
        hybrid ->
            case State#state.beamai_available of
                true -> do_generate_model_beamai(Description, Opts, State);
                false -> do_generate_model_legacy(Description)
            end
    end.

%% @private
do_generate_model_legacy(Description) ->
    try
        yawl_llm_validator:llm_generate_model(Description)
    catch
        _:Reason -> {error, {legacy_error, Reason}}
    end.

%% @private
do_generate_model_beamai(Description, Opts, State) ->
    Provider = maps:get(provider, Opts, State#state.default_provider),
    SystemPrompt = maps:get(system_prompt, Opts,
        <<"You are a workflow modeling expert. Generate YAWL process models "
          "from descriptions. Return valid JSON with activities and transitions.">>),
    ChatOpts = #{
        system_prompt => SystemPrompt,
        temperature => maps:get(temperature, Opts, 0.7)
    },
    case do_chat_beamai(Provider, Description, ChatOpts) of
        {ok, #{text := ResponseText}} ->
            %% Parse the response to extract the model
            case beamai_output_parser:parse_json(ResponseText) of
                {ok, Model} -> {ok, Model};
                {error, _} -> {ok, #{raw_response => ResponseText}}
            end;
        {ok, #{content := Content}} when is_binary(Content) ->
            case beamai_output_parser:parse_json(Content) of
                {ok, Model} -> {ok, Model};
                {error, _} -> {ok, #{raw_response => Content}}
            end;
        {error, _} = Err ->
            Err
    end.

%%====================================================================
%% Internal Functions - Utility
%%====================================================================

%% @private
check_module_available(Module) ->
    case code:ensure_loaded(Module) of
        {module, _} -> true;
        {error, _}  -> false
    end.

%% @private
build_provider_map(Mode, LegacyAvailable, BeamAIAvailable) ->
    Base = #{},
    WithBeamAI = case BeamAIAvailable andalso (Mode =:= beamai orelse Mode =:= hybrid) of
        true ->
            Base#{
                anthropic => {beamai_llm_anthropic, #{}},
                openai => {beamai_llm_openai, #{}}
            };
        false ->
            Base
    end,
    case LegacyAvailable andalso (Mode =:= legacy orelse Mode =:= hybrid) of
        true ->
            WithBeamAI#{
                claude_headless => {yawl_claude_headless, #{}}
            };
        false ->
            WithBeamAI
    end.

%% @private
update_counters({ok, _}, State) ->
    State#state{request_count = State#state.request_count + 1};
update_counters({error, _}, State) ->
    State#state{
        request_count = State#state.request_count + 1,
        error_count = State#state.error_count + 1
    };
update_counters(_, State) ->
    State#state{request_count = State#state.request_count + 1}.

%% @private
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V) ->
    %% Could be a string or a list of messages
    case io_lib:printable_unicode_list(V) of
        true -> list_to_binary(V);
        false -> list_to_binary(io_lib:format("~p", [V]))
    end;
ensure_binary(V) -> list_to_binary(io_lib:format("~p", [V])).
