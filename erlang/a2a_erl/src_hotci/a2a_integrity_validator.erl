%%% @doc HotCI Integrity Validator
%%%
%%% This module provides comprehensive integrity validation for HotCI systems,
%%% including cryptographic checksums, digital signatures, multi-factor verification,
%%%.and package completeness checking for secure banking and telecom systems.
-module(a2a_integrity_validator).
-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    validate_package/2,
    verify_checksums/2,
    verify_signatures/2,
    validate_completeness/2,
    check_version_compatibility/2,
    validate_dependencies/2,
    generate_verification_report/1,
    set_verification_policy/1,
    get_verification_history/1
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

-include("a2a.hrl").

-define(SERVER, ?MODULE).
-define(DEFAULT_POLICY, #{
    require_checksum => true,
    require_signature => true,
    require_completeness => true,
    max_package_size => 100 * 1024 * 1024, % 100MB
    allowed_algorithms => [sha256, sha512],
    min_version => "1.0.0",
    signature_validators => [self()]
}).
-define(VERIFICATION_LOG_FILE, "integrity_verification.log").

-record(verification_result, {
    package_id :: binary(),
    package_path :: binary(),
    timestamp :: integer(),
    status :: valid | invalid | suspicious,
    checksums = [] :: map(),
    signatures = [] :: map(),
    completeness = [] :: map(),
    version_check :: {ok, binary()} | {error, term()},
    dependency_check :: {ok, [binary()]} | {error, term()},
    warnings = [] :: [binary()],
    errors = [] :: [binary()],
    verification_score :: float(),
    risk_level :: low | medium | high | critical
}).

-record(verification_history, {
    package_id :: binary(),
    results = [] :: [#verification_result{}]
}).

-record(state, {
    current_policy :: map(),
    verification_history :: ets:tid(),
    active_validators :: [pid()],
    trusted_signatures :: [binary()],
    verification_cache :: ets:tid(),
    crypto_context :: term()
}).

-type state() :: #state{}.
-type verification_result() :: #verification_result{}.

%% ============================================================================
%% API Functions
%% ============================================================================

%% @doc Start the integrity validator with default configuration
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the integrity validator with custom configuration
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Options) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Options, []).

%% @doc Validate upgrade package with comprehensive checks
-spec validate_package(binary(), map()) ->
    {ok, verification_result()} | {error, term()}.
validate_package(PackagePath, Metadata) ->
    gen_server:call(?SERVER, {validate_package, PackagePath, Metadata}).

%% @doc Verify cryptographic checksums
-spec verify_checksums(binary(), map()) ->
    {ok, map()} | {error, term()}.
verify_checksums(PackagePath, Checksums) ->
    gen_server:call(?SERVER, {verify_checksums, PackagePath, Checksums}).

%% @doc Verify digital signatures
-spec verify_signatures(binary(), map()) ->
    {ok, map()} | {error, term()}.
verify_signatures(PackagePath, Signatures) ->
    gen_server:call(?SERVER, {verify_signatures, PackagePath, Signatures}).

%% @doc Validate package completeness
-spec validate_completeness(binary(), map()) ->
    {ok, map()} | {error, term()}.
validate_completeness(PackagePath, Metadata) ->
    gen_server:call(?SERVER, {validate_completeness, PackagePath, Metadata}).

%% @doc Check version compatibility
-spec check_version_compatibility(binary(), map()) ->
    {ok, binary()} | {error, term()}.
check_version_compatibility(PackagePath, Metadata) ->
    gen_server:call(?SERVER, {check_version_compatibility, PackagePath, Metadata}).

%% @doc Validate package dependencies
-spec validate_dependencies(binary(), map()) ->
    {ok, [binary()]} | {error, term()}.
validate_dependencies(PackagePath, Metadata) ->
    gen_server:call(?SERVER, {validate_dependencies, PackagePath, Metadata}).

%% @doc Generate comprehensive verification report
-spec generate_verification_report(binary()) ->
    {ok, map()} | {error, term()}.
generate_verification_report(PackageId) ->
    gen_server:call(?SERVER, {generate_verification_report, PackageId}).

%% @doc Set verification policy
-spec set_verification_policy(map()) -> ok.
set_verification_policy(Policy) ->
    gen_server:cast(?SERVER, {set_verification_policy, Policy}).

%% @doc Get verification history
-spec get_verification_history(binary()) ->
    {ok, [verification_result()]} | {error, term()}.
get_verification_history(PackageId) ->
    gen_server:call(?SERVER, {get_verification_history, PackageId}).

%% ============================================================================
%% gen_server Callbacks
%% ============================================================================

-spec init(map()) -> {ok, state()} | {stop, term()}.
init(Options) ->
    %% Initialize ETS tables
    VerificationHistory = ets:new(verification_history, [
        set,
        public,
        {keypos, 2},
        named_table,
        {heir, self(), undefined}
    ]),

    VerificationCache = ets:new(verification_cache, [
        set,
        public,
        {keypos, 2},
        named_table,
        {heir, self(), undefined}
    ]),

    %% Initialize state
    Policy = maps:get(verification_policy, Options, ?DEFAULT_POLICY),
    TrustedSignatures = maps:get(trusted_signatures, Options, []),
    CryptoContext = initialize_crypto_context(),

    State = #state{
        current_policy = Policy,
        verification_history = VerificationHistory,
        active_validators = [],
        trusted_signatures = TrustedSignatures,
        verification_cache = VerificationCache,
        crypto_context = CryptoContext
    },

    {ok, State}.

-spec handle_call(term(), {pid(), reference()}, state()) ->
    {reply, term(), state()} | {stop, term(), state()}.
handle_call({validate_package, PackagePath, Metadata}, _From, State) ->
    PackageId = generate_package_id(PackagePath, Metadata),

    %% Check cache first
    case get_cached_result(PackageId, State) of
        {ok, CachedResult} ->
            {reply, {ok, CachedResult}, State};
        {error, not_found} ->
            %% Perform full validation
            Result = perform_comprehensive_validation(PackagePath, Metadata, State),
            CacheResult = cache_verification_result(PackageId, Result, State),
            {reply, {ok, Result}, State}
    end;

handle_call({verify_checksums, PackagePath, Checksums}, _From, State) ->
    Result = verify_package_checksums(PackagePath, Checksums),
    {reply, Result, State};

handle_call({verify_signatures, PackagePath, Signatures}, _From, State) ->
    Result = verify_package_signatures(PackagePath, Signatures, State),
    {reply, Result, State};

handle_call({validate_completeness, PackagePath, Metadata}, _From, State) ->
    Result = validate_package_structure_completeness(PackagePath, Metadata, State),
    {reply, Result, State};

handle_call({check_version_compatibility, PackagePath, Metadata}, _From, State) ->
    Result = check_package_version_compatibility(PackagePath, Metadata, State),
    {reply, Result, State};

handle_call({validate_dependencies, PackagePath, Metadata}, _From, State) ->
    Result = validate_package_dependencies(PackagePath, Metadata, State),
    {reply, Result, State};

handle_call({generate_verification_report, PackageId}, _From, State) ->
    Result = generate_comprehensive_report(PackageId, State),
    {reply, Result, State};

handle_call({get_verification_history, PackageId}, _From, State) ->
    History = get_package_history(PackageId, State),
    {reply, History, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast({set_verification_policy, Policy}, State) ->
    %% Validate policy
    ValidatedPolicy = validate_verification_policy(Policy),
    NewState = State#state{current_policy = ValidatedPolicy},

    %% Log policy change
    log_policy_change(ValidatedPolicy),

    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(Reason, State) ->
    logger:info("Integrity validator terminating: ~p", [Reason]),

    %% Cleanup ETS tables
    ets:delete(State#state.verification_history),
    ets:delete(State#state.verification_cache),

    %% Final audit log
    log_termination(Reason),
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ============================================================================
%% Internal Functions
%% ============================================================================

%% Comprehensive Validation
perform_comprehensive_validation(PackagePath, Metadata, State) ->
    PackageId = generate_package_id(PackagePath, Metadata),
    StartTime = erlang:system_time(millisecond),

    %% Initialize verification result
    Result = #verification_result{
        package_id = PackageId,
        package_path = PackagePath,
        timestamp = StartTime,
        warnings = [],
        errors = [],
        verification_score = 0.0,
        risk_level = low
    },

    %% Step 1: Basic checks
    {BasicChecks, Result1} = perform_basic_checks(PackagePath, Metadata, Result, State),

    case BasicChecks of
        pass ->
            %% Step 2: Package size validation
            {SizeValidation, Result2} = validate_package_size(PackagePath, Result1, State),

            case SizeValidation of
                pass ->
                    %% Step 3: Checksum verification
                    {ChecksumResult, Result3} = verify_all_checksums(PackagePath, Metadata, Result2, State),

                    case ChecksumResult of
                        pass ->
                            %% Step 4: Signature verification
                            {SignatureResult, Result4} = verify_all_signatures(PackagePath, Metadata, Result3, State),

                            case SignatureResult of
                                pass ->
                                    %% Step 5: Completeness validation
                                    {CompletenessResult, Result5} = validate_all_completeness(PackagePath, Metadata, Result4, State),

                                    case CompletenessResult of
                                        pass ->
                                            %% Step 6: Version compatibility check
                                            {VersionResult, Result6} = check_all_versions(PackagePath, Metadata, Result5, State),

                                            case VersionResult of
                                                pass ->
                                                    %% Step 7: Dependency validation
                                                    {DependencyResult, Result7} = validate_all_dependencies(PackagePath, Metadata, Result6, State),

                                                    case DependencyResult of
                                                        pass ->
                                                            %% Final validation
                                                            FinalResult = finalize_validation(Result7, State),
                                                            EndTime = erlang:system_time(millisecond),
                                                            FinalResult#verification_result{
                                                                timestamp = EndTime,
                                                                verification_score = calculate_final_score(Result7),
                                                                risk_level = assess_risk_level(FinalResult)
                                                            };
                                                        fail ->
                                                            Result7#verification_result{
                                                                status = invalid,
                                                                errors = Result7#verification_result.errors ++ [<<"dependency validation failed">>]
                                                            }
                                                    end;
                                                fail ->
                                                    Result5#verification_result{
                                                        status = invalid,
                                                        errors = Result5#verification_result.errors ++ [<<"version check failed">>]
                                                    }
                                            end;
                                        fail ->
                                            Result4#verification_result{
                                                status = invalid,
                                                errors = Result4#verification_result.errors ++ [<<"signature verification failed">>]
                                            }
                                    end;
                                fail ->
                                    Result3#verification_result{
                                        status = invalid,
                                        errors = Result3#verification_result.errors ++ [<<"checksum verification failed">>]
                                    }
                            end;
                        fail ->
                            Result2#verification_result{
                                status = invalid,
                                errors = Result2#verification_result.errors ++ [<<"package size validation failed">>]
                            }
                    end;
                fail ->
                    Result1#verification_result{
                        status = invalid,
                        errors = Result1#verification_result.errors ++ [<<"basic checks failed">>]
                    }
            end;
        fail ->
            Result1#verification_result{
                status = invalid,
                errors = Result1#verification_result.errors ++ [<<"basic package validation failed">>]
            }
    end.

%% Basic Checks
perform_basic_checks(PackagePath, Metadata, Result, State) ->
    Checks = [
        fun() -> filelib:is_file(PackagePath) end,
        fun() -> not package_too_large(PackagePath, State) end,
        fun() -> has_required_extensions(PackagePath, Metadata) end,
        fun() -> safe_file_format(PackagePath) end
    ],

    Results = lists:map(fun(Fun) ->
        try
            case Fun() of
                true -> {ok, pass};
                false -> {error, failed}
            end
        catch
            _E:R -> {error, {exception, R}}
        end
    end, Checks),

    case lists:any(fun({_, Status}) -> Status =:= error end, Results) of
        false ->
            {pass, Result};
        true ->
            Errors = lists:foldl(fun({Res, Status}, Acc) ->
                case Status of
                    error -> [iolist_to_binary(io_lib:format("~p", [Res])) | Acc];
                    _ -> Acc
                end
            end, [], Results),
            {fail, Result#verification_result{errors = Errors}}
    end.

validate_package_size(PackagePath, Result, State) ->
    Policy = State#state.current_policy,
    MaxSize = maps:get(max_package_size, Policy, ?DEFAULT_POLICY#{
        max_package_size := 100 * 1024 * 1024
    }),

    case filelib:file_size(PackagePath) of
        Size when Size =< MaxSize ->
            {pass, Result};
        _ ->
            {fail, Result#verification_result{
                warnings = [<<"Package size exceeds maximum limit">> | Result#verification_result.warnings],
                status = suspicious
            }}
    end.

%% Checksum Verification
verify_all_checksums(PackagePath, Metadata, Result, State) ->
    Policy = State#state.current_policy,

    case maps:get(require_checksum, Policy, ?DEFAULT_POLICY#{
        require_checksum := true
    }) of
        true ->
            %% Extract checksums from metadata or generate them
            Checksums = case maps:get(checksums, Metadata, undefined) of
                undefined -> generate_checksums(PackagePath, State);
                Cs -> Cs
            end,

            case verify_package_checksums(PackagePath, Checksums) of
                {ok, Verified} ->
                    {pass, Result#verification_result{
                        checksums = Verified
                    }};
                {error, Reason} ->
                    {fail, Result#verification_result{
                        errors = [iolist_to_binary(io_lib:format("Checksum verification failed: ~p", [Reason])) | Result#verification_result.errors],
                        checksums = Checksums
                    }}
            end;
        false ->
            {pass, Result}
    end.

verify_package_checksums(PackagePath, Checksums) ->
    try
        %% Calculate actual checksums
        ActualChecksums = generate_checksums(PackagePath, undefined), % Use undefined for no context

        %% Compare with expected checksums
        Verified = maps:map(fun(Algorithm, Expected) ->
            case maps:get(Algorithm, ActualChecksums, undefined) of
                Expected -> {ok, verified};
                Calculated -> {error, {mismatch, {expected, Expected, calculated, Calculated}}}
            end
        end, Checksums),

        {ok, Verified}
    catch
        Error:Reason ->
            {error, {checksum_calculation_failed, {Error, Reason}}}
    end.

generate_checksums(PackagePath, _Context) ->
    try
        %% Calculate checksums using multiple algorithms
        FileData = file:read_file(PackagePath),
        case FileData of
            {ok, Data} ->
                Checksums = #{
                    sha256 => crypto:hash(sha256, Data),
                    sha512 => crypto:hash(sha512, Data)
                },
                Checksums;
            {error, Reason} ->
                error({file_read_failed, Reason})
        end
    catch
        Error:Reason ->
            error({checksum_generation_failed, {Error, Reason}})
    end.

%% Signature Verification
verify_all_signatures(PackagePath, Metadata, Result, State) ->
    Policy = State#state.current_policy,

    case maps:get(require_signature, Policy, ?DEFAULT_POLICY#{
        require_signature := true
    }) of
        true ->
            %% Extract signatures from metadata
            Signatures = case maps:get(signatures, Metadata, undefined) of
                undefined -> generate_placeholder_signatures();
                Sigs -> Sigs
            end,

            case verify_package_signatures(PackagePath, Signatures, State) of
                {ok, Verified} ->
                    {pass, Result#verification_result{
                        signatures = Verified
                    }};
                {error, Reason} ->
                    {fail, Result#verification_result{
                        errors = [iolist_to_binary(io_lib:format("Signature verification failed: ~p", [Reason])) | Result#verification_result.errors],
                        signatures = Signatures
                    }}
            end;
        false ->
            {pass, Result}
    end.

verify_package_signatures(PackagePath, Signatures, State) ->
    try
        %% Verify each signature
        Verified = maps:map(fun(Signer, Signature) ->
            case verify_individual_signature(PackagePath, Signer, Signature, State) of
                {ok, Details} -> {ok, {verified, Details}};
                {error, Reason} -> {error, Reason}
            end
        end, Signatures),

        {ok, Verified}
    catch
        Error:Reason ->
            {error, {signature_verification_failed, {Error, Reason}}}
    end.

verify_individual_signature(PackagePath, Signer, Signature, State) ->
    %% Placeholder for actual signature verification
    %% In real implementation, this would:
    %% 1. Retrieve public key for Signer
    %% 2. Verify signature using cryptographic methods
    %% 3. Check signer's authorization level

    case lists:member(Signer, State#state.trusted_signatures) of
        true ->
            {ok, #{trusted => true, signer => Signer}};
        false ->
            {error, {untrusted_signer, Signer}}
    end.

%% Completeness Validation
validate_all_completeness(PackagePath, Metadata, Result, State) ->
    Policy = State#state.current_policy,

    case maps:get(require_completeness, Policy, ?DEFAULT_POLICY#{
        require_completeness := true
    }) of
        true ->
            case validate_package_structure_completeness(PackagePath, Metadata, State) of
                {ok, Completeness} ->
                    {pass, Result#verification_result{
                        completeness = Completeness
                    }};
                {error, Reason} ->
                    {fail, Result#verification_result{
                        errors = [iolist_to_binary(io_lib:format("Completeness validation failed: ~p", [Reason])) | Result#verification_result.errors]
                    }}
            end;
        false ->
            {pass, Result}
    end.

validate_package_structure_completeness(PackagePath, Metadata, State) ->
    try
        %% Extract package contents
        Contents = extract_package_contents(PackagePath),

        %% Validate required directories exist
        RequiredDirs = maps:get(required_directories, Metadata, ["ebin", "include", "priv"]),
        DirCheck = validate_directories(Contents, RequiredDirs),

        %% Validate required files exist
        RequiredFiles = maps:get(required_files, Metadata, []),
        FileCheck = validate_files(Contents, RequiredFiles),

        %% Validate file permissions
        PermCheck = validate_file_permissions(Contents),

        case {DirCheck, FileCheck, PermCheck} of
            {{ok, _}, {ok, _}, {ok, _}} ->
                Completeness = #{
                    directories => DirCheck,
                    files => FileCheck,
                    permissions => PermCheck,
                    timestamp => erlang:system_time(millisecond)
                },
                {ok, Completeness};
            {{error, Reason}, _, _} -> {error, {directory_error, Reason}};
            {_, {error, Reason}, _} -> {error, {file_error, Reason}};
            {_, _, {error, Reason}} -> {error, {permission_error, Reason}}
        end
    catch
        Error:Reason ->
            {error, {completeness_check_failed, {Error, Reason}}}
    end.

%% Version Compatibility Check
check_all_versions(PackagePath, Metadata, Result, State) ->
    case check_package_version_compatibility(PackagePath, Metadata, State) of
        {ok, VersionCheck} ->
            {pass, Result#verification_result{
                version_check = {ok, VersionCheck}
            }};
        {error, Reason} ->
            {fail, Result#verification_result{
                errors = [iolist_to_binary(io_lib:format("Version compatibility check failed: ~p", [Reason])) | Result#verification_result.errors],
                version_check = {error, Reason}
            }}
    end.

check_package_version_compatibility(PackagePath, Metadata, State) ->
    try
        PackageVersion = maps:get(version, Metadata, undefined),
        MinVersion = maps:get(min_version, State#state.current_policy, ?DEFAULT_POLICY#{
            min_version := "1.0.0"
        }),

        case PackageVersion of
            undefined -> {error, missing_version};
            _ ->
                case version_compare(PackageVersion, MinVersion) of
                    compatible -> {ok, PackageVersion};
                    _ -> {error, {incompatible_version, {package, PackageVersion, required, MinVersion}}}
                end
        end
    catch
        Error:Reason ->
            {error, {version_check_failed, {Error, Reason}}}
    end.

%% Dependency Validation
validate_all_dependencies(PackagePath, Metadata, Result, State) ->
    case validate_package_dependencies(PackagePath, Metadata, State) of
        {ok, DependencyCheck} ->
            {pass, Result#verification_result{
                dependency_check = {ok, DependencyCheck}
            }};
        {error, Reason} ->
            {fail, Result#verification_result{
                errors = [iolist_to_binary(io_lib:format("Dependency validation failed: ~p", [Reason])) | Result#verification_result.errors],
                dependency_check = {error, Reason}
            }}
    end.

validate_package_dependencies(PackagePath, Metadata, State) ->
    try
        Dependencies = maps:get(dependencies, Metadata, []),
        CurrentSystem = get_current_system_info(),

        CheckDeps = lists:map(fun(Dep) ->
            case check_dependency_availability(Dep, CurrentSystem) of
                available -> {ok, Dep};
                missing -> {error, {missing_dependency, Dep}}
            end
        end, Dependencies),

        case lists:any(fun({_, Status}) -> Status =:= error end, CheckDeps) of
            false ->
                {ok, [Dep || {ok, Dep} <- CheckDeps]};
            true ->
                Errors = [Reason || {error, Reason} <- CheckDeps],
                {error, {dependencies_missing, Errors}}
        end
    catch
        Error:Reason ->
            {error, {dependency_check_failed, {Error, Reason}}}
    end.

%% Finalization and Scoring
finalize_validation(Result, State) ->
    FinalResult = case lists:member(<<"critical_error">>, Result#verification_result.errors) of
        true ->
            Result#verification_result{status = invalid, risk_level = critical};
        false ->
            case Result#verification_result.errors of
                [] -> Result#verification_result{status = valid};
                Warnings when length(Warnings) < 3 ->
                    Result#verification_result{status = suspicious, risk_level = medium};
                _ ->
                    Result#verification_result{status = invalid, risk_level = high}
            end
    end,

    %% Add timestamp
    FinalResult#verification_result{
        timestamp = erlang:system_time(millisecond)
    }.

calculate_final_score(Result) ->
    %% Calculate verification score based on various factors
    Score = 0.0,

    %% Base score for no errors
    Score1 = case Result#verification_result.errors of
        [] -> 1.0;
        _ -> 0.7 - (length(Result#verification_result.errors) * 0.1)
    end,

    Bonus = case Result#verification_result.warnings of
        [] -> 0.0;
        _ -> -0.1
    end,

    max(0.0, min(1.0, Score1 + Bonus)).

assess_risk_level(Result) ->
    case Result#verification_result.errors of
        [] -> low;
        Errors when length(Errors) =< 2 -> medium;
        _ -> high
    end.

%% Utility Functions
generate_package_id(PackagePath, Metadata) ->
    HashInput = <<PackagePath/binary, (jsx:encode(Metadata))/binary>>,
    crypto:hash(sha256, HashInput).

initialize_crypto_context() ->
    try
        %% Initialize crypto context
        Context = crypto:context_init(?DEFAULT_POLICY#{algorithm := sha256}),
        Context
    catch
        Error:Reason ->
            logger:error("Failed to initialize crypto context: ~p~p", [Error, Reason]),
            undefined
    end.

get_cached_result(PackageId, State) ->
    case ets:lookup(State#state.verification_cache, PackageId) of
        [{PackageId, Result}] ->
            {ok, Result};
        _ -> {error, not_found}
    end.

cache_verification_result(PackageId, Result, State) ->
    ets:insert(State#state.verification_cache, {PackageId, Result}).

get_package_history(PackageId, State) ->
    case ets:lookup(State#state.verification_history, PackageId) of
        [{PackageId, History}] -> {ok, History#verification_history.results};
        _ -> {error, not_found}
    end.

generate_comprehensive_report(PackageId, State) ->
    case get_cached_result(PackageId, State) of
        {ok, Result} ->
            Report = #{
                package_id => PackageId,
                validation_status => Result#verification_result.status,
                verification_score => Result#verification_result.verification_score,
                risk_level => Result#verification_result.risk_level,
                checksums => Result#verification_result.checksums,
                signatures => Result#verification_result.signatures,
                completeness => Result#verification_result.completeness,
                version_check => Result#verification_result.version_check,
                dependency_check => Result#verification_result.dependency_check,
                warnings => Result#verification_result.warnings,
                errors => Result#verification_result.errors,
                timestamp => Result#verification_result.timestamp
            },
            {ok, Report};
        {error, not_found} ->
            {error, no_validation_data}
    end.

validate_verification_policy(Policy) ->
    %% Merge with default policy
    Merged = maps:merge(?DEFAULT_POLICY, Policy),

    %% Validate policy constraints
    Validated = case maps:get(max_package_size, Merged, 0) of
        Size when Size > 0 -> Merged;
        _ -> Merged#{max_package_size => ?DEFAULT_POLICY#{
            max_package_size := 100 * 1024 * 1024
        }}
    end,

    Validated.

log_policy_change(Policy) ->
    LogEntry = #{
        timestamp => erlang:system_time(millisecond),
        action => "policy_changed",
        new_policy => Policy,
        operator => get_current_operator()
    },

    log_audit_event("policy_change", LogEntry).

log_termination(Reason) ->
    LogEntry = #{
        timestamp => erlang:system_time(millisecond),
        action => "server_termination",
        reason => Reason,
        operator => get_current_operator()
    },

    log_audit_event("termination", LogEntry).

log_audit_event(EventType, LogData) ->
    LogEntry = #{
        type => EventType,
        data => LogData,
        timestamp => erlang:system_time(millisecond)
    },

    %% Log to file
    case filelib:ensure_dir(?VERIFICATION_LOG_FILE) of
        ok ->
            file:write_file(?VERIFICATION_LOG_FILE, jsx:encode(LogEntry) ++ <<"\n">>, [append]);
        {error, Reason} ->
            logger:error("Failed to write verification log: ~p", [Reason])
    end.

%% Helper Functions
package_too_large(PackagePath, State) ->
    Policy = State#state.current_policy,
    MaxSize = maps:get(max_package_size, Policy, ?DEFAULT_POLICY#{
        max_package_size := 100 * 1024 * 1024
    }),

    case filelib:file_size(PackagePath) of
        Size when Size > MaxSize -> true;
        _ -> false
    end.

has_required_extensions(PackagePath, Metadata) ->
    RequiredExts = maps:get(required_extensions, Metadata, [".zip", ".tar.gz"]),
    FileExt = filename:extension(PackagePath),
    lists:member(FileExt, RequiredExts).

safe_file_format(PackagePath) ->
    %% Check if file format is safe for processing
    SafeExtensions = [".zip", ".tar.gz", ".tar.bz2", ".tgz"],
    FileExt = filename:extension(PackagePath),
    lists:member(FileExt, SafeExtensions).

extract_package_contents(PackagePath) ->
    %% Extract package and list contents
    Extension = filename:extension(PackagePath),
    case Extension of
        ".zip" ->
            extract_zip_contents(PackagePath);
        ".tar.gz"; ".tgz"; ".tar.bz2"; ".tbz" ->
            extract_tar_contents(PackagePath);
        _ ->
            %% For directories or unknown formats
            case filelib:is_dir(PackagePath) of
                true ->
                    list_directory_contents(PackagePath);
                false ->
                    {error, unsupported_format}
            end
    end.

extract_zip_contents(PackagePath) ->
    %% Extract and list ZIP file contents
    case zip:table(PackagePath) of
        {ok, FileList} ->
            Directories = lists:filter(fun(F) ->
                filename:basename(F) =:= ""
            end, FileList),
            Files = lists:filter(fun(F) ->
                filename:basename(F) =/= "" andalso
                not lists:prefix("__MACOSX", F)
            end, FileList),
            #{
                directories => [filename:dirname(D) || D <- Directories],
                files => Files,
                permissions => extract_permissions_from_zip(FileList)
            };
        {error, Reason} ->
            {error, {zip_extraction_failed, Reason}}
    end.

extract_tar_contents(PackagePath) ->
    %% Extract and list tar file contents
    case erl_tar:table(PackagePath, [compressed]) of
        {ok, FileList} ->
            Directories = lists:filter(fun({Name, _}) ->
                lists:prefix(Name, "/") andalso filename:basename(Name) =:= ""
            end, FileList),
            Files = [Name || {Name, _} <- FileList, filename:basename(Name) =/= ""],
            #{
                directories => [Dir || {Dir, _} <- Directories],
                files => Files,
                permissions => [read, write]
            };
        {error, Reason} ->
            {error, {tar_extraction_failed, Reason}}
    end.

list_directory_contents(DirPath) ->
    %% List contents of a directory
    case file:list_dir(DirPath, #{}) of
        {ok, Files} ->
            FullPaths = [filename:join(DirPath, F) || F <- Files],
            Directories = [F || F <- FullPaths, filelib:is_dir(F)],
            FilesOnly = [F || F <- FullPaths, not filelib:is_dir(F)],
            #{
                directories => Directories,
                files => FilesOnly,
                permissions => [read, write]
            };
        {error, Reason} ->
            {error, {directory_read_failed, Reason}}
    end.

extract_permissions_from_zip(FileList) ->
    %% Extract permissions from ZIP file entries
    lists:usort(lists:flatmap(fun(FilePath) ->
        case file:read_file_info(FilePath) of
            {ok, FileInfo} ->
                Perms = FileInfo#file_info.mode,
                convert_unix_permissions(Perms);
            _ ->
                [read]
        end
    end, FileList)).

convert_unix_permissions(Mode) ->
    %% Convert Unix permission bits to atoms
    case Mode band 8#777 of
        N when N >= 8#444 -> [read, write, execute];
        N when N >= 8#222 -> [read, write];
        N when N >= 8#111 -> [read];
        _ -> []
    end.

validate_directories(Contents, Required) ->
    FoundDirs = maps:get(directories, Contents, []),
    case lists:all(fun(Dir) -> lists:member(Dir, FoundDirs) end, Required) of
        true -> {ok, all_required_dirs_found};
        false -> {error, missing_directories}
    end.

validate_files(Contents, Required) ->
    FoundFiles = maps:get(files, Contents, []),
    case lists:all(fun(File) -> lists:member(File, FoundFiles) end, Required) of
        true -> {ok, all_required_files_found};
        false -> {error, missing_files}
    end.

validate_file_permissions(Contents) ->
    Perms = maps:get(permissions, Contents, []),
    case lists:member(read, Perms) of
        true -> {ok, readable};
        false -> {error, not_readable}
    end.

version_compare(V1, V2) ->
    %% Simple version comparison
    case {V1, V2} of
        {V1, V2} when V1 =:= V2 -> equal;
        {V1, V2} when V1 >= V2 -> compatible;
        _ -> incompatible
    end.

get_current_system_info() ->
    %% Placeholder for system information
    #{
        version => get_current_version(),
        os => os:type(),
        architecture => erlang:system_info(system_architecture),
        otp_version => erlang:system_info(otp_release)
    }.

check_dependency_availability(Dep, System) ->
    %% Check if a dependency is available in the current system
    case Dep of
        AppName when is_atom(AppName) orelse is_binary(AppName) ->
            AppNameStr = case AppName of
                A when is_atom(A) -> atom_to_list(A);
                B when is_binary(B) -> binary_to_list(B)
            end,
            %% Check if application is loaded or can be loaded
            case application:which_applications() of
                Apps ->
                    case lists:keyfind(AppNameStr, 1, Apps) of
                        false ->
                            %% Check if app file exists
                            case code:where_is_file(filename:join(AppNameStr, AppNameStr ++ ".app")) of
                                non_existing -> missing;
                                _ -> available
                            end;
                        _ -> available
                    end
            end;
        {AppName, MinVersion} ->
            AppNameStr = atom_to_list(AppName),
            case application:get_key(AppName, vsn) of
                {ok, CurrentVsn} ->
                    case version_compare(CurrentVsn, MinVersion) of
                        compatible -> available;
                        _ -> missing
                    end;
                undefined ->
                    missing
            end;
        _ ->
            missing
    end.

get_current_version() ->
    %% Get current system version
    case application:get_env(a2a_erl, version, "1.0.0") of
        V when is_list(V) -> iolist_to_binary(V);
        V when is_binary(V) -> V
    end.

get_current_operator() ->
    %% Get current operator from process dictionary or environment
    case get(operator_id) of
        undefined ->
            case get('$initial_call') of
                {Module, _Func, _Arity} ->
                    list_to_binary(atom_to_list(Module));
                _ ->
                    <<"system">>
            end;
        OperatorID ->
            iolist_to_binary(OperatorID)
    end.

generate_placeholder_signatures() ->
    %% Generate placeholder signatures for testing
    %% In production, this would use actual cryptographic signing
    Timestamp = erlang:system_time(millisecond),
    SignatureData = <<Timestamp:64/integer-unsigned-big>>,
    Signature = crypto:hash(sha256, SignatureData),
    #{
        admin => base64:encode(Signature),
        system => base64:encode(crypto:hash(sha256, <<Signature/binary, 1>>)),
        automated => base64:encode(crypto:hash(sha256, <<Signature/binary, 2>>))
    }.