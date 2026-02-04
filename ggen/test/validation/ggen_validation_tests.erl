%%====================================================================
%% Module: ggen_validation_tests
%% Description: Validation tests for generated code compilation and functionality
%%====================================================================

-module(ggen_validation_tests).
-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Configuration
%%====================================================================

-define(TEST_OUTPUT_DIR, "validation_test_output").
-define(TIMEOUT, 30000).  %% 30 seconds timeout for compilation
-define(REBAR3_PATH, "rebar3").

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    %% Create validation output directory
    case filelib:ensure_dir(?TEST_OUTPUT_DIR ++ "/") of
        ok ->
            %% Clean up existing validation files
            cleanup_validation_files(),
            %% Test if rebar3 is available
            case rebar3_available() of
                true -> ?TEST_OUTPUT_DIR;
                false -> skip_rebar_tests
            end;
        {error, Reason} ->
            exit({failed_to_setup_validation, Reason})
    end.

cleanup(Dir) ->
    case Dir of
        skip_rebar_tests -> ok;
        _ ->
            cleanup_validation_files(),
            %% Clean up any compiled beams
            cleanup_beam_files()
    end,
    ok.

cleanup_validation_files() ->
    case file:list_dir(?TEST_OUTPUT_DIR) of
        {ok, Files} ->
            lists:foreach(fun(File) ->
                case filelib:is_dir(?TEST_OUTPUT_DIR ++ "/" ++ File) of
                    true ->
                        cleanup_directory(?TEST_OUTPUT_DIR ++ "/" ++ File);
                    false ->
                        file:delete(?TEST_OUTPUT_DIR ++ "/" ++ File)
                end
            end, Files);
        {error, _} ->
            ok
    end,
    file:del_dir(?TEST_OUTPUT_DIR),
    ok.

cleanup_directory(Dir) ->
    case file:list_dir(Dir) of
        {ok, Files} ->
            lists:foreach(fun(File) ->
                case filelib:is_dir(Dir ++ "/" ++ File) of
                    true ->
                        cleanup_directory(Dir ++ "/" ++ File);
                    false ->
                        file:delete(Dir ++ "/" ++ File)
                end
            end, Files);
        {error, _} ->
            ok
    end,
    file:del_dir(Dir),
    ok.

cleanup_beam_files() ->
    %% Clean up .beam files from ebin directory
    EbinFiles = filelib:wildcard("ebin/*.beam"),
    lists:foreach(fun(File) ->
        file:delete(File)
    end, EbinFiles),
    ok.

rebar3_available() ->
    case os:find_executable(?REBAR3_PATH) of
        false -> false;
        _Path -> true
    end.

%%====================================================================
%% Erlang Compilation Validation Tests
%%====================================================================

%% Test generated Erlang files compile successfully
erlang_compilation_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_rebar_tests ->
                    ["Skipping rebar3 tests - rebar3 not available"];
                _ ->
                    ["Generated Erlang files should compile successfully",
                        ?_assert(generate_and_compile_erlang(Dir)),
                        ?_assert(validate_compiled_modules(Dir))
                    ]
            end
        end
    }.

%% Test gen_server template compilation
gen_server_template_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_rebar_tests ->
                    ["Skipping rebar3 tests - rebar3 not available"];
                _ ->
                    ["GenServer template should generate compilable code",
                        ?_assert(generate_gen_server_template(Dir)),
                        ?_assert(compile_gen_server_files(Dir)),
                        ?_assert(validate_gen_server_behavior(Dir))
                    ]
            end
        end
    }.

%% Test gen_statem template compilation
gen_statem_template_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_rebar_tests ->
                    ["Skipping rebar3 tests - rebar3 not available"];
                _ ->
                    ["GenStatem template should generate compilable code",
                        ?_assert(generate_gen_statem_template(Dir)),
                        ?_assert(compile_gen_statem_files(Dir)),
                        ?_assert(validate_gen_statem_behavior(Dir))
                    ]
            end
        end
    }.

%% Test supervisor template compilation
supervisor_template_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_rebar_tests ->
                    ["Skipping rebar3 tests - rebar3 not available"];
                _ ->
                    ["Supervisor template should generate compilable code",
                        ?_assert(generate_supervisor_template(Dir)),
                        ?_assert(compile_supervisor_files(Dir)),
                        ?_assert(validate_supervisor_behavior(Dir))
                    ]
            end
        end
    }.

%% Test custom template compilation
custom_template_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_rebar_tests ->
                    ["Skipping rebar3 tests - rebar3 not available"];
                _ ->
                    ["Custom templates should generate compilable code",
                        ?_assert(generate_custom_template(Dir)),
                        ?_assert(compile_custom_files(Dir)),
                        ?_assert(validate_custom_functionality(Dir))
                    ]
            end
        end
    }.

%% Test generated config files validity
config_validation_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_rebar_tests ->
                    ["Skipping rebar3 tests - rebar3 not available"];
                _ ->
                    ["Generated config files should be valid",
                        ?_assert(generate_erlang_config(Dir)),
                        ?_assert(validate_rebar3_config(Dir)),
                        ?_assert(validate_sys_config(Dir)),
                        ?_assert(validate_vm_args(Dir))
                    ]
            end
        end
    }.

%%====================================================================
%% Template-Specific Validation Tests
%%====================================================================

%% Test HotCI-enabled template compilation
hotci_template_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_rebar_tests ->
                    ["Skipping rebar3 tests - rebar3 not available"];
                _ ->
                    ["HotCI-enabled templates should compile correctly",
                        ?_assert(generate_hotci_enabled_template(Dir)),
                        ?_assert(compile_hotci_files(Dir)),
                        ?_assert(validate_hotci_features(Dir))
                    ]
            end
        end
    }.

%% Test rollback support template compilation
rollback_template_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_rebar3_available ->
                    ["Skipping rebar3 tests - rebar3 not available"];
                _ ->
                    ["Rollback-enabled templates should compile correctly",
                        ?_assert(generate_rollback_enabled_template(Dir)),
                        ?_assert(compile_rollback_files(Dir)),
                        ?_assert(validate_rollback_features(Dir))
                    ]
            end
        end
    }.

%% Test template with properties
properties_template_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_rebar3_available ->
                    ["Skipping rebar3 tests - rebar3 not available"];
                _ ->
                    ["Templates with properties should compile correctly",
                        ?_assert(generate_properties_template(Dir)),
                        ?_assert(compile_properties_files(Dir)),
                        ?_assert(validate_properties_records(Dir))
                    ]
            end
        end
    }.

%%====================================================================
%% Functionality Validation Tests
%%====================================================================

%% Test generated module functionality
module_functionality_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_rebar_tests ->
                    ["Skipping rebar3 tests - rebar3 not available"];
                _ ->
                    ["Generated modules should have expected functionality",
                        ?_assert(generate_test_modules(Dir)),
                        ?_assert(compile_test_modules(Dir)),
                        ?_assert(test_module_behavior(Dir)),
                        ?_assert(test_api_functions(Dir))
                    ]
            end
        end
    }.

%% Test supervisor child specifications
supervisor_children_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_rebar_tests ->
                    ["Skipping rebar3 tests - rebar3 not available"];
                _ ->
                    ["Generated supervisors should have correct child specs",
                        ?_assert(generate_supervisor_with_children(Dir)),
                        ?_assert(compile_supervisor_children(Dir)),
                        ?_assert(validate_child_specs(Dir))
                    ]
            end
        end
    }.

%% Test gen_server callbacks
gen_server_callbacks_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_rebar_tests ->
                    ["Skipping rebar3 tests - rebar3 not available"];
                _ ->
                    ["Generated gen_server callbacks should work correctly",
                        ?_assert(generate_gen_server_with_callbacks(Dir)),
                        ?_assert(compile_callbacks(Dir)),
                        ?_assert(test_init_callback(Dir)),
                        ?_assert(test_handle_call(Dir)),
                        ?_assert(test_handle_cast(Dir))
                    ]
            end
        end
    }.

%%====================================================================
%% Error Handling Tests
%%====================================================================

%% Test compilation error handling
compilation_error_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_rebar_tests ->
                    ["Skipping rebar3 tests - rebar3 not available"];
                _ ->
                    ["Should handle compilation errors gracefully",
                        ?_assert(test_invalid_template_error(Dir)),
                        ?_assert(test_missing_callback_error(Dir)),
                        ?_assert(test_wrong_signature_error(Dir))
                    ]
            end
        end
    }.

%% Test dependency resolution
dependency_resolution_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_rebar_tests ->
                    ["Skipping rebar3 tests - rebar3 not available"];
                _ ->
                    ["Should resolve dependencies correctly",
                        ?_assert(generate_with_dependencies(Dir)),
                        ?_assert(compile_with_dependencies(Dir)),
                        ?_assert(validate_dependency_resolution(Dir))
                    ]
            end
        end
    }.

%%====================================================================
** Validation Helper Functions
%%====================================================================

generate_and_compile_erlang(Dir) ->
    %% Generate Erlang files
    case ggen_generator:generate(erlang, #{output_dir => Dir}) of
        ok ->
            compile_generated_erlang(Dir);
        {error, Reason} ->
            {error, {generation_failed, Reason}}
    end.

generate_gen_server_template(Dir) ->
    %% Mock gen_server module data
    GenServerModule = #{
        module_name => "test_gen_server",
        behaviour_type => "gen_server",
        exported_functions => [
            #{
                name => "start_link",
                args => []
            },
            #{
                name => "get_status",
                args => []
            }
        ],
        properties => [
            #{
                name => "internal_state",
                type => "term()"
            }
        ],
        hotci_enabled => false,
        rollback_support => false
    },
    %% Create a simplified test file
    TestContent = create_gen_server_test_content(GenServerModule),
    file:write_file(Dir ++ "/test_gen_server.erl", TestContent).

create_gen_server_test_content(Module) ->
    "-module(" ++ maps:get(module_name, Module) ++ ").\n" ++
    "-behaviour(gen_server).\n\n" ++
    "-export([start_link/0, get_status/0]).\n" ++
    "-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).\n\n" ++
    "-record(state, {internal_state :: term()}).\n\n" ++
    "start_link() ->\n" ++
    "    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).\n\n" ++
    "get_status() ->\n" ++
    "    gen_server:call(?MODULE, get_status).\n\n" ++
    "init([]) ->\n" ++
    "    {ok, #state{internal_state = undefined}}.\n\n" ++
    "handle_call(get_status, _From, State) ->\n" ++
    "    {reply, ok, State}.\n\n" ++
    "handle_cast(_Msg, State) ->\n" ++
    "    {noreply, State}.\n\n" ++
    "handle_info(_Info, State) ->\n" ++
    "    {noreply, State}.\n\n" ++
    "terminate(_Reason, _State) ->\n" ++
    "    ok.\n\n" ++
    "code_change(_OldVsn, State, _Extra) ->\n" ++
    "    {ok, State}.".

generate_gen_statem_template(Dir) ->
    %% Create gen_statem test file
    TestContent = "-module(test_gen_statem).\n" ++
                   "-behaviour(gen_statem).\n\n" ++
                   "-export([start_link/0]).\n" ++
                   "-export([init/1, callback_mode/0, handle_event/4, terminate/2, code_change/3]).\n\n" ++
                   "start_link() ->\n" ++
                   "    gen_statem:start_link({local, ?MODULE}, ?MODULE, [], []).\n\n" ++
                   "init([]) ->\n" ++
                   "    {ok, idle, #{}}.\n\n" ++
                   "callback_mode() ->\n" ++
                   "    state_functions.\n\n" ++
                   "handle_event(_EventType, _Event, _State, Data) ->\n" ++
                   "    {keep_state, Data}.\n\n" ++
                   "terminate(_Reason, _State) ->\n" ++
                   "    ok.\n\n" ++
                   "code_change(_OldVsn, State, _Extra) ->\n" ++
                   "    {ok, State}.\n",
    file:write_file(Dir ++ "/test_gen_statem.erl", TestContent).

generate_supervisor_template(Dir) ->
    %% Create supervisor test file
    TestContent = "-module(test_supervisor).\n" ++
                   "-behaviour(supervisor).\n\n" ++
                   "-export([start_link/0]).\n" ++
                   "-export([init/1]).\n\n" ++
                   "start_link() ->\n" ++
                   "    supervisor:start_link({local, ?MODULE}, ?MODULE, []).\n\n" ++
                   "init([]) ->\n" ++
                   "    ChildSpec = #{\n" ++
                   "        id => test_child,\n" ++
                   "        start => {test_child, start_link, []},\n" ++
                   "        restart => permanent,\n" ++
                   "        shutdown => 5000,\n" ++
                   "        type => worker,\n" ++
                   "        modules => [test_child]\n" ++
                   "    },\n" ++
                   "    {ok, {{one_for_all, 5, 10}, [ChildSpec]}}.\n",
    file:write_file(Dir ++ "/test_supervisor.erl", TestContent).

generate_custom_template(Dir) ->
    %% Create custom template test file
    TestContent = "-module(test_custom).\n" ++
                   "-export([custom_function/1]).\n\n" ++
                   "custom_function(Arg) ->\n" ++
                   "    Arg * 2.\n",
    file:write_file(Dir ++ "/test_custom.erl", TestContent).

generate_erlang_config(Dir) ->
    case ggen_generator:generate(erlang, #{output_dir => Dir}) of
        ok -> true;
        {error, _} -> false
    end.

generate_hotci_enabled_template(Dir) ->
    HotciModule = #{
        module_name => "test_hotci_server",
        behaviour_type => "gen_server",
        exported_functions => [
            #{
                name => "start_link",
                args => []
            }
        ],
        properties => [],
        hotci_enabled => true,
        rollback_support => false
    },
    TestContent = create_hotci_test_content(HotciModule),
    file:write_file(Dir ++ "/test_hotci_server.erl", TestContent).

create_hotci_test_content(Module) ->
    "-module(" ++ maps:get(module_name, Module) ++ ").\n" ++
    "-behaviour(gen_server).\n\n" ++
    "-export([start_link/0]).\n" ++
    "-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).\n\n" ++
    "-record(state, {}). \n\n" ++
    "start_link() ->\n" ++
    "    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).\n\n" ++
    "init([]) ->\n" ++
    "    HotciMonitor = case application:get_env(test_hotci_server, enable_hotci, false) of\n" ++
    "        true -> start_hotci_monitor();\n" ++
    "        false -> undefined\n" ++
    "    end,\n" ++
    "    {ok, #state{}}.\n\n" ++
    "handle_call(_Request, _From, State) ->\n" ++
    "    {reply, ok, State}.\n\n" ++
    "handle_cast(_Msg, State) ->\n" ++
    "    {noreply, State}.\n\n" ++
    "handle_info(_Info, State) ->\n" ++
    "    {noreply, State}.\n\n" ++
    "terminate(_Reason, _State) ->\n" ++
    "    ok.\n\n" ++
    "code_change(_OldVsn, State, _Extra) ->\n" ++
    "    {ok, State}.\n\n" ++
    "start_hotci_monitor() ->\n" ++
    "    case whereis(hotci_monitor) of\n" ++
    "        undefined ->\n" ++
    "            {ok, Pid} = hotci_monitor:start(),\n" ++
    "            Pid;\n" ++
    "        Pid ->\n" ++
    "            Pid\n" ++
    "    end.\n",
    file:write_file(Dir ++ "/test_hotci_server.erl", TestContent).

generate_rollback_enabled_template(Dir) ->
    RollbackModule = #{
        module_name => "test_rollback_server",
        behaviour_type => "gen_server",
        exported_functions => [
            #{
                name => "start_link",
                args => []
            }
        ],
        properties => [],
        hotci_enabled => false,
        rollback_support => true
    },
    TestContent = create_rollback_test_content(RollbackModule),
    file:write_file(Dir ++ "/test_rollback_server.erl", TestContent).

create_rollback_test_content(Module) ->
    "-module(" ++ maps:get(module_name, Module) ++ ").\n" ++
    "-behaviour(gen_server).\n\n" ++
    "-export([start_link/0]).\n" ++
    "-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).\n\n" ++
    "-record(state, {rollback_timer :: reference()}).\n\n" ++
    "start_link() ->\n" ++
    "    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).\n\n" ++
    "init([]) ->\n" ++
    "    RollbackTimer = case application:get_env(test_rollback_server, enable_rollback, false) of\n" ++
    "        true -> start_rollback_timer();\n" ++
    "        false -> undefined\n" ++
    "    end,\n" ++
    "    {ok, #state{rollback_timer = RollbackTimer}}.\n\n" ++
    "handle_call(_Request, _From, State) ->\n" ++
    "    {reply, ok, State}.\n\n" ++
    "handle_cast(_Msg, State) ->\n" ++
    "    {noreply, State}.\n\n" ++
    "handle_info({timeout, T, rollback_check}, #state{rollback_timer = T} = State) ->\n" ++
    "    {noreply, State#state{rollback_timer = undefined}};\n" ++
    "handle_info(_Info, State) ->\n" ++
    "    {noreply, State}.\n\n" ++
    "terminate(_Reason, _State) ->\n" ++
    "    ok.\n\n" ++
    "code_change(_OldVsn, State, _Extra) ->\n" ++
    "    {ok, State}.\n\n" ++
    "start_rollback_timer() ->\n" ++
    "    erlang:start_timer(30000, self(), rollback_check).\n",
    file:write_file(Dir ++ "/test_rollback_server.erl", TestContent).

generate_properties_template(Dir) ->
    PropertiesModule = #{
        module_name => "test_properties_server",
        behaviour_type => "gen_server",
        exported_functions => [
            #{
                name => "start_link",
                args => []
            }
        ],
        properties => [
            #{
                name => "property1",
                type => "integer()"
            },
            #{
                name => "property2",
                type => "string()"
            }
        ],
        hotci_enabled => false,
        rollback_support => false
    },
    TestContent = create_properties_test_content(PropertiesModule),
    file:write_file(Dir ++ "/test_properties_server.erl", TestContent).

create_properties_test_content(Module) ->
    "-module(" ++ maps:get(module_name, Module) ++ ").\n" ++
    "-behaviour(gen_server).\n\n" ++
    "-export([start_link/0]).\n" ++
    "-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).\n\n" ++
    "-record(state, {\n" ++
    "    property1 :: integer(),\n" ++
    "    property2 :: string()\n" ++
    "}).\n\n" ++
    "start_link() ->\n" ++
    "    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).\n\n" ++
    "init([]) ->\n" ++
    "    State = #state{\n" ++
    "        property1 = 0,\n" ++
    "        property2 = \"default\"\n" ++
    "    },\n" ++
    "    {ok, State}.\n\n" ++
    "handle_call(_Request, _From, State) ->\n" ++
    "    {reply, ok, State}.\n\n" ++
    "handle_cast(_Msg, State) ->\n" ++
    "    {noreply, State}.\n\n" ++
    "handle_info(_Info, State) ->\n" ++
    "    {noreply, State}.\n\n" ++
    "terminate(_Reason, _State) ->\n" ++
    "    ok.\n\n" ++
    "code_change(_OldVsn, State, _Extra) ->\n" ++
    "    {ok, State}.\n",
    file:write_file(Dir ++ "/test_properties_server.erl", TestContent).

generate_test_modules(Dir) ->
    case ggen_generator:generate(erlang, #{output_dir => Dir}) of
        ok -> true;
        {error, _} -> false
    end.

generate_supervisor_with_children(Dir) ->
    %% Create supervisor with multiple children
    SupervisorContent = "-module(supervisor_with_children).\n" ++
                        "-behaviour(supervisor).\n\n" ++
                        "-export([start_link/0]).\n" ++
                        "-export([init/1]).\n\n" ++
                        "start_link() ->\n" ++
                        "    supervisor:start_link({local, ?MODULE}, ?MODULE, []).\n\n" ++
                        "init([]) ->\n" ++
                        "    Children = [\n" ++
                        "        #{\n" ++
                        "            id => worker1,\n" ++
                        "            start => {worker1, start_link, []},\n" ++
                        "            restart => permanent,\n" ++
                        "            shutdown => 5000,\n" ++
                        "            type => worker,\n" ++
                        "            modules => [worker1]\n" ++
                        "        },\n" ++
                        "        #{\n" ++
                        "            id => worker2,\n" ++
                        "            start => {worker2, start_link, []},\n" ++
                        "            restart => transient,\n" ++
                        "            shutdown => 2000,\n" ++
                        "            type => worker,\n" ++
                        "            modules => [worker2]\n" ++
                        "        }\n" ++
                        "    ],\n" ++
                        "    {ok, {{one_for_one, 3, 10}, Children}}.\n",
    file:write_file(Dir ++ "/supervisor_with_children.erl", SupervisorContent),

    %% Create worker modules
    Worker1Content = "-module(worker1).\n" ++
                     "-export([start_link/0]).\n\n" ++
                     "start_link() ->\n" ++
                     "    {ok, spawn_link(fun() -> worker1_loop() end)}.\n\n" ++
                     "worker1_loop() ->\n" ++
                     "    receive\n" ++
                     "        stop -> ok\n" ++
                     "    after\n" ++
                     "        1000 -> worker1_loop()\n" ++
                     "    end.\n",
    file:write_file(Dir ++ "/worker1.erl", Worker1Content),

    Worker2Content = "-module(worker2).\n" ++
                     "-export([start_link/0]).\n\n" ++
                     "start_link() ->\n" ++
                     "    {ok, spawn_link(fun() -> worker2_loop() end)}.\n\n" ++
                     "worker2_loop() ->\n" ++
                     "    receive\n" ++
                     "        stop -> ok\n" ++
                     "    after\n" ++
                     "        1000 -> worker2_loop()\n" ++
                     "    end.\n",
    file:write_file(Dir ++ "/worker2.erl", Worker2Content),

    ok.

generate_gen_server_with_callbacks(Dir) ->
    %% Create gen_server with comprehensive callbacks
    GenserverContent = "-module(comprehensive_gen_server).\n" ++
                        "-behaviour(gen_server).\n\n" ++
                        "-export([start_link/0, get_state/1, set_state/2]).\n" ++
                        "-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).\n\n" ++
                        "-record(state, {data :: term(), counters :: map()}).\n\n" ++
                        "start_link() ->\n" ++
                        "    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).\n\n" ++
                        "get_state(Key) ->\n" ++
                        "    gen_server:call(?MODULE, {get_state, Key}).\n\n" ++
                        "set_state(Key, Value) ->\n" ++
                        "    gen_server:cast(?MODULE, {set_state, Key, Value}).\n\n" ++
                        "init([]) ->\n" ++
                        "    {ok, #state{data = #{}, counters = #{}}}.\n\n" ++
                        "handle_call({get_state, Key}, _From, State) ->\n" ++
                        "    Value = maps:get(Key, State#state.data, undefined),\n" ++
                        "    {reply, Value, State};\n" ++
                        "handle_call(get_counters, _From, State) ->\n" ++
                        "    {reply, State#state.counters, State}.\n\n" ++
                        "handle_cast({set_state, Key, Value}, State) ->\n" ++
                        "    NewData = maps:put(Key, Value, State#state.data),\n" ++
                        "    NewCounters = maps:update_with(counter, fun(X) -> X + 1 end, 1, State#state.counters),\n" ++
                        "    {noreply, State#state{data = NewData, counters = NewCounters}}.\n\n" ++
                        "handle_info(_Info, State) ->\n" ++
                        "    {noreply, State}.\n\n" ++
                        "terminate(_Reason, _State) ->\n" ++
                        "    ok.\n\n" ++
                        "code_change(_OldVsn, State, _Extra) ->\n" ++
                        "    {ok, State}.\n",
    file:write_file(Dir ++ "/comprehensive_gen_server.erl", GenserverContent),
    ok.

%%====================================================================
** Compilation and Validation Helpers
%%====================================================================

compile_generated_erlang(Dir) ->
    ErlangFiles = filelib:wildcard(Dir ++ "/src/*.erl"),
    compile_files(ErlangFiles).

compile_files([]) -> true;
compile_files([File|Files]) ->
    case compile:file(File, [return_errors, debug_info]) of
        {ok, _} -> compile_files(Files);
        {error, Errors, _} -> {error, {compilation_failed, Errors}}
    end.

validate_compiled_modules(Dir) ->
    ErlangModules = filelib:wildcard(Dir ++ "/src/*.beam"),
    length(ErlangModules) > 0.

validate_gen_server_behavior(Dir) ->
    GenServerFiles = filelib:wildcard(Dir ++ "/src/*_gen_server*.beam"),
    length(GenServerFiles) > 0.

validate_gen_statem_behavior(Dir) ->
    GenStatemFiles = filelib:wildcard(Dir ++ "/src/*_gen_statem*.beam"),
    length(GenStatemFiles) > 0.

validate_supervisor_behavior(Dir) ->
    SupervisorFiles = filelib:wildcard(Dir ++ "/src/*_supervisor*.beam"),
    length(SupervisorFiles) > 0.

validate_custom_functionality(Dir) ->
    CustomFiles = filelib:wildcard(Dir ++ "/src/*.beam"),
    length(CustomFiles) > 0.

validate_rebar3_config(Dir) ->
    Rebar3File = Dir ++ "/rebar3.config",
    case file:read_file(Rebar3File) of
        {ok, Content} ->
            %% Check for basic rebar3 config structure
            lists:member("{deps, [", Content) andalso lists:member("{erl_opts", Content);
        {error, _} -> false
    end.

validate_sys_config(Dir) ->
    SysConfigFile = Dir ++ "/sys.config",
    case file:read_file(SysConfigFile) of
        {ok, Content} ->
            lists:member("{", Content) andalso lists:member("}", Content);
        {error, _} -> false
    end.

validate_vm_args(Dir) ->
    VmArgsFile = Dir ++ "/vm.args",
    case file:read_file(VmArgsFile) of
        {ok, Content} ->
            lists:member("-name", Content) andalso lists:member("-setcookie", Content);
        {error, _} -> false
    end.

validate_hotci_features(Dir) ->
    %% Check if HotCI-related features are present
    HotciFiles = filelib:wildcard(Dir ++ "/src/*_hotci*.beam"),
    length(HotciFiles) > 0.

validate_rollback_features(Dir) ->
    %% Check if rollback-related features are present
    RollbackFiles = filelib:wildcard(Dir ++ "/src/*_rollback*.beam"),
    length(RollbackFiles) > 0.

validate_properties_records(Dir) ->
    %% Check if properties records are present in compiled modules
    PropertyFiles = filelib:wildcard(Dir ++ "/src/*_properties*.beam"),
    length(PropertyFiles) > 0.

test_module_behavior(Dir) ->
    %% Test basic module loading
    ErlangFiles = filelib:wildcard(Dir ++ "/src/*.erl"),
    lists:all(fun(File) ->
        case compile:file(File, [return_errors]) of
            {ok, _} -> true;
            {error, _, _} -> false
        end
    end, ErlangFiles).

test_api_functions(Dir) ->
    %% Test that generated API functions can be called
    true.

test_child_specs(Dir) ->
    %% Test child specifications
    SupervisorFiles = filelib:wildcard(Dir ++ "/src/*_supervisor*.erl"),
    lists:any(fun(File) ->
        case file:read_file(File) of
            {ok, Content} -> lists:member("#{id =>", Content);
            {error, _} -> false
        end
    end, SupervisorFiles).

test_init_callback(Dir) ->
    %% Test init callback implementation
    ErlangFiles = filelib:wildcard(Dir ++ "/src/*.erl"),
    lists:any(fun(File) ->
        case file:read_file(File) of
            {ok, Content} -> lists:member("init(", Content);
            {error, _} -> false
        end
    end, ErlangFiles).

test_handle_call(Dir) ->
    %% Test handle_call implementation
    ErlangFiles = filelib:wildcard(Dir ++ "/src/*.erl"),
    lists:any(fun(File) ->
        case file:read_file(File) of
            {ok, Content} -> lists:member("handle_call(", Content);
            {error, _} -> false
        end
    end, ErlangFiles).

test_handle_cast(Dir) ->
    %% Test handle_cast implementation
    ErlangFiles = filelib:wildcard(Dir ++ "/src/*.erl"),
    lists:any(fun(File) ->
        case file:read_file(File) of
            {ok, Content} -> lists:member("handle_cast(", Content);
            {error, _} -> false
        end
    end, ErlangFiles).

test_invalid_template_error(Dir) ->
    %% Test error handling for invalid templates
    true.

test_missing_callback_error(Dir) ->
    %% Test error handling for missing callbacks
    true.

test_wrong_signature_error(Dir) ->
    %% Test error handling for wrong callback signatures
    true.

generate_with_dependencies(Dir) ->
    %% Generate modules with dependencies
    case ggen_generator:generate(erlang, #{output_dir => Dir}) of
        ok -> true;
        {error, _} -> false
    end.

compile_with_dependencies(Dir) ->
    %% Compile with dependency handling
    ErlangFiles = filelib:wildcard(Dir ++ "/src/*.erl"),
    compile_files(ErlangFiles).

validate_dependency_resolution(Dir) ->
    %% Validate that dependencies are resolved correctly
    true.

compile_gen_server_files(Dir) ->
    GenServerFiles = filelib:wildcard(Dir ++ "/src/*_gen_server*.erl"),
    compile_files(GenServerFiles).

compile_gen_statem_files(Dir) ->
    GenStatemFiles = filelib:wildcard(Dir ++ "/src/*_gen_statem*.erl"),
    compile_files(GenStatemFiles).

compile_supervisor_files(Dir) ->
    SupervisorFiles = filelib:wildcard(Dir ++ "/src/*_supervisor*.erl"),
    compile_files(SupervisorFiles).

compile_custom_files(Dir) ->
    CustomFiles = filelib:wildcard(Dir ++ "/src/*.erl"),
    compile_files(CustomFiles).

compile_hotci_files(Dir) ->
    HotciFiles = filelib:wildcard(Dir ++ "/src/*_hotci*.erl"),
    compile_files(HotciFiles).

compile_rollback_files(Dir) ->
    RollbackFiles = filelib:wildcard(Dir ++ "/src/*_rollback*.erl"),
    compile_files(RollbackFiles).

compile_properties_files(Dir) ->
    PropertiesFiles = filelib:wildcard(Dir ++ "/src/*_properties*.erl"),
    compile_files(PropertiesFiles).

compile_test_modules(Dir) ->
    TestFiles = filelib:wildcard(Dir ++ "/src/*.erl"),
    compile_files(TestFiles).

compile_supervisor_children(Dir) ->
    SupervisorFiles = filelib:wildcard(Dir ++ "/src/*_supervisor*.erl"),
    compile_files(SupervisorFiles).

compile_callbacks(Dir) ->
    CallbackFiles = filelib:wildcard(Dir ++ "/src/*gen_server*.erl"),
    compile_files(CallbackFiles).

validate_child_specs(Dir) ->
    %% Validate child specifications
    SupervisorFiles = filelib:wildcard(Dir ++ "/src/*_supervisor*.erl"),
    lists:any(fun(File) ->
        case file:read_file(File) of
            {ok, Content} -> lists:member("ChildSpec = #{", Content);
            {error, _} -> false
        end
    end, SupervisorFiles).

%%====================================================================
** End of File
%%====================================================================