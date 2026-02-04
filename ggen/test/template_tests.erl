%%====================================================================
%% Module: template_tests
%% Description: Template rendering and validation tests
%%====================================================================

-module(template_tests).
-include_lib("eunit/include/eunit.hrl").

%%====================================================================
** Test Data
%%====================================================================

-define(TEST_OUTPUT_DIR, "template_test_output").
-define(MODULE_DATA, #{
    module_name => "test_module",
    behaviour_type => "gen_server",
    exported_functions => [
        #{
            name => "start_link",
            args => []
        },
        #{
            name => "get_state",
            args => ["string()"]
        }
    ],
    properties => [
        #{
            name => "internal_state",
            type => "map()"
        },
        #{
            name => "counter",
            type => "integer()"
        }
    ],
    hotci_enabled => true,
    rollback_support => true
}).

%%====================================================================
** Setup and Cleanup
%%====================================================================

setup() ->
    %% Create test output directory
    case filelib:ensure_dir(?TEST_OUTPUT_DIR ++ "/") of
        ok ->
            %% Clean up existing test files
            case file:list_dir(?TEST_OUTPUT_DIR) of
                {ok, Files} ->
                    lists:foreach(fun(File) ->
                        file:delete(?TEST_OUTPUT_DIR ++ "/" ++ File)
                    end, Files);
                {error, _} ->
                    ok
            end,
            ?TEST_OUTPUT_DIR;
        {error, Reason} ->
            exit({failed_to_setup_template_tests, Reason})
    end.

cleanup(Dir) ->
    %% Clean up test files and directories
    case file:list_dir(Dir) of
        {ok, Files} ->
            lists:foreach(fun(File) ->
                file:delete(Dir ++ "/" ++ File)
            end, Files);
        {error, _} ->
            ok
    end,
    case file:del_dir(Dir) of
        ok -> ok;
        {error, _} -> ok
    end,
    ok.

%%====================================================================
** Template Rendering Tests
%%====================================================================

%% Test gen_server template rendering
gen_server_template_rendering_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["GenServer template should render correctly",
                ?_assert(render_gen_server_template(Dir, ?MODULE_DATA)),
                ?_assert(validate_gen_server_output(Dir))
            ]
        end
    }.

%% Test gen_statem template rendering
gen_statem_template_rendering_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["GenStatem template should render correctly",
                ?_assert(render_gen_statem_template(Dir, ?MODULE_DATA#{behaviour_type := "gen_statem"})),
                ?_assert(validate_gen_statem_output(Dir))
            ]
        end
    }.

%% Test supervisor template rendering
supervisor_template_rendering_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Supervisor template should render correctly",
                ?_assert(render_supervisor_template(Dir, ?MODULE_DATA#{behaviour_type := "supervisor"})),
                ?_assert(validate_supervisor_output(Dir))
            ]
        end
    }.

%% Test template with properties
template_with_properties_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Template with properties should render correctly",
                ?_assert(render_template_with_properties(Dir, ?MODULE_DATA)),
                ?_assert(validate_properties_records(Dir))
            ]
        end
    }.

%% Test template with HotCI features
hotci_template_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["HotCI-enabled template should render correctly",
                ?_assert(render_hotci_template(Dir, ?MODULE_DATA#{hotci_enabled := true})),
                ?_assert(validate_hotci_features(Dir))
            ]
        end
    }.

%% Test template with rollback features
rollback_template_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Rollback-enabled template should render correctly",
                ?_assert(render_rollback_template(Dir, ?MODULE_DATA#{rollback_support := true})),
                ?_assert(validate_rollback_features(Dir))
            ]
        end
    }.

%% Test template error handling
template_error_handling_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Template should handle errors gracefully",
                ?_assert(render_template_with_missing_data(Dir)),
                ?_assert(validate_error_handling(Dir))
            ]
        end
    }.

%% Test template variable substitution
variable_substitution_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Template variable substitution should work correctly",
                ?_assert(render_template_with_variables(Dir)),
                ?_assert(validate_variable_substitution(Dir))
            ]
        end
    }.

%% Test template conditional rendering
conditional_rendering_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Template conditional rendering should work correctly",
                ?_assert(render_template_with_conditions(Dir)),
                ?_assert(validate_conditional_rendering(Dir))
            ]
        end
    }.

%%====================================================================
** Template Validation Tests
%%====================================================================

%% Test generated code compilation
code_compilation_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Generated code should compile successfully",
                ?_assert(render_gen_server_template(Dir, ?MODULE_DATA)),
                ?_assert(compile_generated_code(Dir)),
                ?_assert(validate_compiled_modules(Dir))
            ]
        end
    }.

%% Test module functionality
module_functionality_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Generated modules should have expected functionality",
                ?_assert(render_gen_server_template(Dir, ?MODULE_DATA)),
                ?_assert(compile_generated_code(Dir)),
                ?_assert(test_basic_functionality(Dir))
            ]
        end
    }.

%% Test template consistency
template_consistency_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Template rendering should be consistent",
                ?_assert(render_multiple_times(Dir)),
                ?_assert(validate_consistent_output(Dir))
            ]
        end
    }.

%%====================================================================
** Performance Tests
**====================================================================

%% Test template rendering speed
template_rendering_speed_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Template rendering should be fast",
                ?_assert(measure_rendering_speed(Dir)),
                ?_assert(validate_rendering_performance(Dir))
            ]
        end
    }.

%% Test multiple template rendering
multiple_template_rendering_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Multiple template rendering should be efficient",
                ?_assert(render_multiple_templates(Dir)),
                ?_assert(validate_multiple_output(Dir))
            ]
        end
    }.

%%====================================================================
** Helper Functions
**====================================================================

%% GenServer template rendering
render_gen_server_template(Dir, ModuleData) ->
    ModuleName = maps:get(module_name, ModuleData),
    Behaviour = maps:get(behaviour_type, ModuleData),
    ExportedFunctions = maps:get(exported_functions, ModuleData, []),
    Properties = maps:get(properties, ModuleData, []),
    HotciEnabled = maps:get(hotci_enabled, ModuleData, false),
    RollbackSupport = maps:get(rollback_support, ModuleData, false),

    %% Generate exports
    ExportLines = lists:map(fun(Fun) ->
        FunName = maps:get(name, Fun),
        Args = case maps:get(args, Fun, []) of
            [] -> "";
            ArgsList -> "(" ++ string:join(ArgsList, ", ") ++ ")"
        end,
        "    " ++ FunName ++ Args
    end, ExportedFunctions),

    %% Generate record fields
    RecordFields = lists:map(fun(Property) ->
        PropName = maps:get(name, Property),
        PropType = maps:get(type, Property, "term()"),
        "    " ++ PropName ++ " :: " ++ PropType
    end, Properties),

    %% Generate content
    Content = "-module(" ++ ModuleName ++ ").\n" ++
              "-behaviour(" ++ Behaviour ++ ").\n\n" ++
              "-export([start_link/0" ++
              case ExportedFunctions of
                  [] -> "";
                  _ -> ", " ++ string:join(lists:map(fun(F) -> maps:get(name, F) end, ExportedFunctions), ", ")
              end ++
              "]).\n" ++
              "\n" ++
              "%%====================================================================\n" ++
              "%% Records\n" ++
              "%%====================================================================\n" ++
              "\n" ++
              "-record(state, {\n" ++
              RecordFields ++
              "}).\n\n" ++
              "%%====================================================================\n" ++
              "%% API Functions\n" ++
              "%%====================================================================\n" ++
              "\n" ++
              "start_link() ->\n" ++
              "    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).\n" ++
              generate_function_definitions(ExportedFunctions) ++
              "\n" ++
              "%%====================================================================\n" ++
              "%% gen_server Callbacks\n" ++
              "%%====================================================================\n" ++
              "\n" ++
              "init([]) ->\n" ++
              "    State = #state{},\n" ++
              "    {ok, State}.\n" ++
              "\n" ++
              "handle_call(_Request, _From, State) ->\n" ++
              "    {reply, ok, State}.\n" ++
              "\n" ++
              "handle_cast(_Msg, State) ->\n" ++
              "    {noreply, State}.\n" ++
              "\n" ++
              "handle_info(_Info, State) ->\n" ++
              "    {noreply, State}.\n" ++
              "\n" ++
              "terminate(_Reason, _State) ->\n" ++
              "    ok.\n" ++
              "\n" ++
              "code_change(_OldVsn, State, _Extra) ->\n" ++
              "    {ok, State}.\n" ++
              "\n" ++
              "%%====================================================================\n" ++
              "%% Internal Functions\n" ++
              "%%====================================================================\n" ++
              generate_internal_functions(ExportedFunctions) ++
              "\n" ++
              "%%====================================================================\n" ++
              "%% End of File\n" ++
              "%%====================================================================\n",

    Filename = Dir ++ "/" ++ ModuleName ++ ".erl",
    file:write_file(Filename, Content).

%% GenStatem template rendering
render_gen_statem_template(Dir, ModuleData) ->
    ModuleName = maps:get(module_name, ModuleData),
    Behaviour = maps:get(behaviour_type, ModuleData),
    ExportedFunctions = maps:get(exported_functions, ModuleData, []),

    Content = "-module(" ++ ModuleName ++ ").\n" ++
              "-behaviour(" ++ Behaviour ++ ").\n\n" ++
              "-export([start_link/0" ++
              case ExportedFunctions of
                  [] -> "";
                  _ -> ", " ++ string:join(lists:map(fun(F) -> maps:get(name, F) end, ExportedFunctions), ", ")
              end ++
              "]).\n" ++
              "-export([init/1, callback_mode/0, handle_event/4, terminate/2, code_change/3]).\n\n" ++
              "start_link() ->\n" ++
              "    gen_statem:start_link({local, ?MODULE}, ?MODULE, [], []).\n" ++
              "\n" ++
              "init([]) ->\n" ++
              "    {ok, idle, #{}}.\n" ++
              "\n" ++
              "callback_mode() ->\n" ++
              "    state_functions.\n" ++
              "\n" ++
              "handle_event(_EventType, _Event, State, Data) ->\n" ++
              "    {keep_state, Data}.\n" ++
              "\n" ++
              "terminate(_Reason, State) ->\n" ++
              "    ok.\n" ++
              "\n" ++
              "code_change(_OldVsn, State, _Extra) ->\n" ++
              "    {ok, State}.\n",

    Filename = Dir ++ "/" ++ ModuleName ++ ".erl",
    file:write_file(Filename, Content).

%% Supervisor template rendering
render_supervisor_template(Dir, ModuleData) ->
    ModuleName = maps:get(module_name, ModuleData),
    Behaviour = maps:get(behaviour_type, ModuleData),

    Content = "-module(" ++ ModuleName ++ ").\n" ++
              "-behaviour(" ++ Behaviour ++ ").\n\n" ++
              "-export([start_link/0]).\n" ++
              "-export([init/1]).\n\n" ++
              "start_link() ->\n" ++
              "    supervisor:start_link({local, ?MODULE}, ?MODULE, []).\n" ++
              "\n" ++
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

    Filename = Dir ++ "/" ++ ModuleName ++ ".erl",
    file:write_file(Filename, Content).

%% Template with properties rendering
render_template_with_properties(Dir, ModuleData) ->
    render_gen_server_template(Dir, ModuleData).

%% HotCI template rendering
render_hotci_template(Dir, ModuleData) ->
    ModuleName = maps:get(module_name, ModuleData),
    Behaviour = maps:get(behaviour_type, ModuleData),

    Content = "-module(" ++ ModuleName ++ ").\n" ++
              "-behaviour(" ++ Behaviour ++ ").\n\n" ++
              "-export([start_link/0, get_metrics/0]).\n" ++
              "-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).\n\n" ++
              "start_link() ->\n" ++
              "    gen_server:start_link({local, ?MODULE}, ?MODULE, []).\n" ++
              "\n" ++
              "get_metrics() ->\n" ++
              "    gen_server:call(?MODULE, get_metrics).\n" ++
              "\n" ++
              "init([]) ->\n" ++
              "    HotciMonitor = case application:get_env(" ++ ModuleName ++ ", enable_hotci, false) of\n" ++
              "        true -> start_hotci_monitor();\n" ++
              "        false -> undefined\n" ++
              "    end,\n" ++
              "    {ok, #{hotci_monitor => HotciMonitor}}.\n" ++
              "\n" ++
              "handle_call(_Request, _From, State) ->\n" ++
              "    {reply, ok, State}.\n" ++
              "\n" ++
              "handle_cast(_Msg, State) ->\n" ++
              "    {noreply, State}.\n" ++
              "\n" ++
              "handle_info(_Info, State) ->\n" ++
              "    {noreply, State}.\n" ++
              "\n" ++
              "terminate(_Reason, State) ->\n" ++
              "    ok.\n" ++
              "\n" ++
              "code_change(_OldVsn, State, _Extra) ->\n" ++
              "    {ok, State}.\n" ++
              "\n" ++
              "start_hotci_monitor() ->\n" ++
              "    case whereis(hotci_monitor) of\n" ++
              "        undefined ->\n" ++
              "            {ok, Pid} = hotci_monitor:start(),\n" ++
              "            Pid;\n" ++
              "        Pid ->\n" ++
              "            Pid\n" ++
              "    end.\n",

    Filename = Dir ++ "/" ++ ModuleName ++ ".erl",
    file:write_file(Filename, Content).

%% Rollback template rendering
render_rollback_template(Dir, ModuleData) ->
    ModuleName = maps:get(module_name, ModuleData),
    Behaviour = maps:get(behaviour_type, ModuleData),

    Content = "-module(" ++ ModuleName ++ ").\n" ++
              "-behaviour(" ++ Behaviour ++ ").\n\n" ++
              "-export([start_link/0, check_rollback/0]).\n" ++
              "-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).\n\n" ++
              "start_link() ->\n" ++
              "    gen_server:start_link({local, ?MODULE}, ?MODULE, []).\n" ++
              "\n" ++
              "check_rollback() ->\n" ++
              "    gen_server:call(?MODULE, check_rollback).\n" ++
              "\n" ++
              "init([]) ->\n" ++
              "    RollbackTimer = case application:get_env(" ++ ModuleName ++ ", enable_rollback, false) of\n" ++
              "        true -> start_rollback_timer();\n" ++
              "        false -> undefined\n" ++
              "    end,\n" ++
              "    {ok, #{rollback_timer => RollbackTimer}}.\n" ++
              "\n" ++
              "handle_call(check_rollback, _From, State) ->\n" ++
              "    {reply, ok, State}.\n" ++
              "\n" ++
              "handle_cast(_Msg, State) ->\n" ++
              "    {noreply, State}.\n" ++
              "\n" ++
              "handle_info({timeout, T, rollback_check}, #state{rollback_timer = T} = State) ->\n" ++
              "    %% Handle rollback check\n" ++
              "    {noreply, State};\n" ++
              "handle_info(_Info, State) ->\n" ++
              "    {noreply, State}.\n" ++
              "\n" ++
              "terminate(_Reason, State) ->\n" ++
              "    ok.\n" ++
              "\n" ++
              "code_change(_OldVsn, State, _Extra) ->\n" ++
              "    {ok, State}.\n" ++
              "\n" ++
              "start_rollback_timer() ->\n" ++
              "    erlang:start_timer(30000, self(), rollback_check).\n",

    Filename = Dir ++ "/" ++ ModuleName ++ ".erl",
    file:write_file(Filename, Content).

%% Template with missing data
render_template_with_missing_data(Dir) ->
    %% Render with incomplete data to test error handling
    IncompleteData = #{module_name => "incomplete_module"},
    render_gen_server_template(Dir, IncompleteData).

%% Template with variables
render_template_with_variables(Dir) ->
    %% Test variable substitution
    VariableData = ?MODULE_DATA#{
        module_name => "var_module",
        exported_functions => [
            #{
                name => "function_with_args",
                args => ["Arg1", "Arg2"]
            },
            #{
                name => "function_no_args",
                args => []
            }
        ]
    },
    render_gen_server_template(Dir, VariableData).

%% Template with conditions
render_template_with_conditions(Dir) ->
    %% Test conditional rendering
    ConditionData = ?MODULE_DATA#{
        module_name => "conditional_module",
        hotci_enabled => true,
        rollback_support => false
    },
    render_gen_server_template(Dir, ConditionData).

%% Generate function definitions
generate_function_definitions([]) -> "";
generate_function_definitions([Function|Functions]) ->
    FunName = maps:get(name, Function),
    Args = case maps:get(args, Function, []) of
        [] -> "";
        ArgsList -> "(" ++ string:join(ArgsList, ", ") ++ ")"
    end,
    "\n" ++ FunName ++ Args ++ " ->\n" ++
    "    gen_server:call(?MODULE, " ++ FunName ++ Args ++ ").\n" ++
    generate_function_definitions(Functions).

%% Generate internal functions
generate_internal_functions([]) -> "";
generate_internal_functions(_Functions) -> "".

%%====================================================================
** Validation Helper Functions
**====================================================================

validate_gen_server_output(Dir) ->
    ModuleFile = Dir ++ "/test_module.erl",
    case file:read_file(ModuleFile) of
        {ok, Content} ->
            lists:member("-behaviour(gen_server)", Content) andalso
            lists:member("-record(state,", Content) andalso
            lists:member("start_link()", Content);
        {error, _} -> false
    end.

validate_gen_statem_output(Dir) ->
    ModuleFile = Dir ++ "/test_module.erl",
    case file:read_file(ModuleFile) of
        {ok, Content} ->
            lists:member("-behaviour(gen_statem)", Content) andalso
            lists:member("callback_mode()", Content);
        {error, _} -> false
    end.

validate_supervisor_output(Dir) ->
    ModuleFile = Dir ++ "/test_module.erl",
    case file:read_file(ModuleFile) of
        {ok, Content} ->
            lists:member("-behaviour(supervisor)", Content) andalso
            lists:member("ChildSpec = #{", Content);
        {error, _} -> false
    end.

validate_properties_records(Dir) ->
    ModuleFile = Dir ++ "/test_module.erl",
    case file:read_file(ModuleFile) of
        {ok, Content} ->
            lists:member("internal_state :: map()", Content) andalso
            lists:member("counter :: integer()", Content);
        {error, _} -> false
    end.

validate_hotci_features(Dir) ->
    ModuleFile = Dir ++ "/test_module.erl",
    case file:read_file(ModuleFile) of
        {ok, Content} ->
            lists:member("HotciMonitor", Content) andalso
            lists:member("start_hotci_monitor()", Content);
        {error, _} -> false
    end.

validate_rollback_features(Dir) ->
    ModuleFile = Dir ++ "/test_module.erl",
    case file:read_file(ModuleFile) of
        {ok, Content} ->
            lists:member("RollbackTimer", Content) andalso
            lists:member("start_rollback_timer()", Content);
        {error, _} -> false
    end.

validate_error_handling(Dir) ->
    ModuleFile = Dir ++ "/incomplete_module.erl",
    case file:read_file(ModuleFile) of
        {ok, _Content} -> true;
        {error, _} -> false
    end.

validate_variable_substitution(Dir) ->
    ModuleFile = Dir ++ "/var_module.erl",
    case file:read_file(ModuleFile) of
        {ok, Content} ->
            lists:member("function_with_args(Arg1, Arg2)", Content) andalso
            lists:member("function_no_args()", Content);
        {error, _} -> false
    end.

validate_conditional_rendering(Dir) ->
    ModuleFile = Dir ++ "/conditional_module.erl",
    case file:read_file(ModuleFile) of
        {ok, Content} ->
            lists:member("HotciMonitor", Content) andalso
            not lists:member("RollbackTimer", Content);
        {error, _} -> false
    end.

compile_generated_code(Dir) ->
    ModuleFile = Dir ++ "/test_module.erl",
    case compile:file(ModuleFile, [return_errors]) of
        {ok, _} -> true;
        {error, _, _} -> false
    end.

validate_compiled_modules(Dir) ->
    ModuleFile = Dir ++ "/test_module.erl",
    BeamFile = Dir ++ "/test_module.beam",
    compile:file(ModuleFile) andalso filelib:is_file(BeamFile).

test_basic_functionality(Dir) ->
    ModuleFile = Dir ++ "/test_module.erl",
    case compile:file(ModuleFile) of
        {ok, Module} ->
            %% Test that the module can be loaded
            code:purge(Module),
            code:load_file(Module),
            true;
        {error, _, _} -> false
    end.

validate_consistent_output(Dir) ->
    %% Generate the same template twice and compare output
    FirstRender = render_gen_server_template(Dir ++ "/first", ?MODULE_DATA),
    SecondRender = render_gen_server_template(Dir ++ "/second", ?MODULEData),

    FirstFile = Dir ++ "/first/test_module.erl",
    SecondFile = Dir ++ "/second/test_module.erl",

    case {file:read_file(FirstFile), file:read_file(SecondFile)} of
        {{ok, FirstContent}, {ok, SecondContent}} ->
            FirstContent =:= SecondContent;
        _ ->
            false
    end.

render_multiple_times(Dir) ->
    %% Render the same template multiple times
    lists:foreach(fun(N) ->
        render_gen_server_template(Dir ++ "/render_" ++ integer_to_list(N), ?MODULE_DATA)
    end, lists:seq(1, 10)),
    true.

measure_rendering_speed(Dir) ->
    StartTime = erlang:system_time(millisecond),
    render_gen_server_template(Dir, ?MODULE_DATA),
    EndTime = erlang:system_time(millisecond),
    GenerationTime = EndTime - StartTime,
    io:format("Template rendering time: ~p ms~n", [GenerationTime]),
    GenerationTime < 1000.

validate_rendering_performance(Dir) ->
    GenerationTime = measure_rendering_speed(Dir),
    GenerationTime < 1000.

render_multiple_templates(Dir) ->
    %% Render different template types
    render_gen_server_template(Dir ++ "/gen_server", ?MODULE_DATA),
    render_gen_statem_template(Dir ++ "/gen_statem", ?MODULE_DATA#{behaviour_type := "gen_statem"}),
    render_supervisor_template(Dir ++ "/supervisor", ?MODULE_DATA#{behaviour_type := "supervisor"}),
    true.

validate_multiple_output(Dir) ->
    GenServerFile = Dir ++ "/gen_server/test_module.erl",
    GenStatemFile = Dir ++ "/gen_statem/test_module.erl",
    SupervisorFile = Dir ++ "/supervisor/test_module.erl",

    GenServerValid = validate_gen_server_output(Dir ++ "/gen_server"),
    GenStatemValid = validate_gen_statem_output(Dir ++ "/gen_statem"),
    SupervisorValid = validate_supervisor_output(Dir ++ "/supervisor"),

    GenServerValid andalso GenStatemValid andalso SupervisorValid.

%%====================================================================
** End of File
%%====================================================================