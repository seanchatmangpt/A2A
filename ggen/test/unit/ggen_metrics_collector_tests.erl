%%====================================================================
%% Module: ggen_metrics_collector_tests
%% Description: Unit tests for ggen_metrics_collector module
%%====================================================================

-module(ggen_metrics_collector_tests).
-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Data
%%====================================================================

-define(TEST_TIMEOUT, 5000).  %% 5 seconds timeout

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    %% Start the metrics collector
    case ggen_metrics_collector:start_link() of
        {ok, _Pid} -> ok;
        {error, {already_started, _Pid}} -> ok;
        {error, Reason} -> exit({failed_to_start_metrics, Reason})
    end,
    %% Wait for initialization
    timer:sleep(100),
    ok.

cleanup(_) ->
    %% Stop the metrics collector
    case whereis(ggen_metrics_collector) of
        undefined -> ok;
        Pid ->
            exit(Pid, normal),
            timer:sleep(100)
    end,
    ok.

%%====================================================================
%% Unit Tests
%%====================================================================

%% Test basic initialization
initialization_test_() ->
    [{"Metrics collector should start successfully",
        ?_assertMatch(ok, setup())},
     {"Metrics collector should be running",
        ?_assert(is_pid(whereis(ggen_metrics_collector)))}
    ].

%% Test metric retrieval
get_metrics_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(_) ->
            ["Should retrieve metrics structure",
                ?_assertMatch(#{metrics := #{}, timestamp := _, uptime := _},
                    ggen_metrics_collector:get_metrics()),
                ?_assert(is_integer(maps:get(timestamp, ggen_metrics_collector:get_metrics()))),
                ?_assert(is_integer(maps:get(uptime, ggen_metrics_collector:get_metrics())))
            ]
        end
    }.

%% Test increment metric
increment_metric_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(_) ->
            ["Should increment metrics correctly",
                %% Get initial metrics
                InitialMetrics = maps:get(metrics, ggen_metrics_collector:get_metrics()),
                InitialErrors = maps:get(errors, InitialMetrics, 0),

                %% Increment error metric
                ggen_metrics_collector:increment_metric(errors, 2),

                %% Check that metric was incremented
                UpdatedMetrics = maps:get(metrics, ggen_metrics_collector:get_metrics()),
                ?_assertEqual(InitialErrors + 2, maps:get(errors, UpdatedMetrics))
            ]
        end
    }.

%% Test set metric
set_metric_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(_) ->
            ["Should set metrics correctly",
                %% Set a custom metric
                ggen_metrics_collector:set_metric(custom_metric, 42),

                %% Check that metric was set
                Metrics = maps:get(metrics, ggen_metrics_collector:get_metrics()),
                ?_assertEqual(42, maps:get(custom_metric, Metrics))
            ]
        end
    }.

%% Test track_generation_start
track_generation_start_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(_) ->
            ["Should track generation start",
                %% Get initial files_generated count
                InitialMetrics = maps:get(metrics, ggen_metrics_collector:get_metrics()),
                InitialFilesGenerated = maps:get(files_generated, InitialMetrics, 0),

                %% Track generation start
                ggen_metrics_collector:track_generation_start(),

                %% Check that files_generated was incremented
                UpdatedMetrics = maps:get(metrics, ggen_metrics_collector:get_metrics()),
                ?_assertEqual(InitialFilesGenerated + 1, maps:get(files_generated, UpdatedMetrics))
            ]
        end
    }.

%% Test track_generation_end
track_generation_end_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(_) ->
            ["Should track generation time",
                %% Track generation with a specific time
                ggen_metrics_collector:track_generation_end(1500),

                %% Check that generation_time was updated
                Metrics = maps:get(metrics, ggen_metrics_collector:get_metrics()),
                ?_assertEqual(1500, maps:get(generation_time, Metrics))
            ]
        end
    }.

%% Test track_ontology_processed
track_ontology_processed_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(_) ->
            ["Should track ontology processing",
                %% Get initial count
                InitialMetrics = maps:get(metrics, ggen_metrics_collector:get_metrics()),
                InitialOntologies = maps:get(ontologies_processed, InitialMetrics, 0),

                %% Track ontology processed
                ggen_metrics_collector:track_ontology_processed(),

                %% Check that count was incremented
                UpdatedMetrics = maps:get(metrics, ggen_metrics_collector:get_metrics()),
                ?_assertEqual(InitialOntologies + 1, maps:get(ontologies_processed, UpdatedMetrics))
            ]
        end
    }.

%% Test track_template_rendered
track_template_rendered_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(_) ->
            ["Should track template rendering",
                %% Get initial count
                InitialMetrics = maps:get(metrics, ggen_metrics_collector:get_metrics()),
                InitialTemplates = maps:get(templates_rendered, InitialMetrics, 0),

                %% Track template rendered
                ggen_metrics_collector:track_template_rendered(),

                %% Check that count was incremented
                UpdatedMetrics = maps:get(metrics, ggen_metrics_collector:get_metrics()),
                ?_assertEqual(InitialTemplates + 1, maps:get(templates_rendered, UpdatedMetrics))
            ]
        end
    }.

%% Test track_sparql_executed
track_sparql_executed_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(_) ->
            ["Should track SPARQL queries",
                %% Get initial count
                InitialMetrics = maps:get(metrics, ggen_metrics_collector:get_metrics()),
                InitialSparql = maps:get(sparql_queries_executed, InitialMetrics, 0),

                %% Track SPARQL executed
                ggen_metrics_collector:track_sparql_executed(),

                %% Check that count was incremented
                UpdatedMetrics = maps:get(metrics, ggen_metrics_collector:get_metrics()),
                ?_assertEqual(InitialSparql + 1, maps:get(sparql_queries_executed, UpdatedMetrics))
            ]
        end
    }.

%% Test track_error
track_error_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(_) ->
            ["Should track errors",
                %% Get initial count
                InitialMetrics = maps:get(metrics, ggen_metrics_collector:get_metrics()),
                InitialErrors = maps:get(errors, InitialMetrics, 0),

                %% Track error
                ggen_metrics_collector:track_error(test_error),

                %% Check that error count was incremented
                UpdatedMetrics = maps:get(metrics, ggen_metrics_collector:get_metrics()),
                ?_assertEqual(InitialErrors + 1, maps:get(errors, UpdatedMetrics))
            ]
        end
    }.

%% Test multiple metric operations
multiple_metric_operations_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(_) ->
            ["Should handle multiple metric operations correctly",
                %% Start multiple generations
                ggen_metrics_collector:track_generation_start(),
                ggen_metrics_collector:track_generation_start(),

                %% Track some ontologies
                ggen_metrics_collector:track_ontology_processed(),
                ggen_metrics_collector:track_ontology_processed(),
                ggen_metrics_collector:track_ontology_processed(),

                %% Track templates
                ggen_metrics_collector:track_template_rendered(),

                %% Track SPARQL
                ggen_metrics_collector:track_sparql_executed(),

                %% Track generation time
                ggen_metrics_collector:track_generation_end(2000),

                %% Check final metrics
                Metrics = maps:get(metrics, ggen_metrics_collector:get_metrics()),
                ?_assertEqual(2, maps:get(files_generated, Metrics)),
                ?_assertEqual(3, maps:get(ontologies_processed, Metrics)),
                ?_assertEqual(1, maps:get(templates_rendered, Metrics)),
                ?_assertEqual(1, maps:get(sparql_queries_executed, Metrics)),
                ?_assertEqual(2000, maps:get(generation_time, Metrics))
            ]
        end
    }.

%% Test metric persistence across multiple calls
metric_persistence_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(_) ->
            ["Metrics should persist across multiple get_metrics calls",
                %% Set a metric
                ggen_metrics_collector:set_metric(persistent_metric, 100),

                %% Get metrics multiple times
                Metrics1 = ggen_metrics_collector:get_metrics(),
                Metrics2 = ggen_metrics_collector:get_metrics(),

                %% Both should have the same metric value
                ?_assertEqual(100, maps:get(persistent_metric, maps:get(metrics, Metrics1))),
                ?_assertEqual(100, maps:get(persistent_metric, maps:get(metrics, Metrics2)))
            ]
        end
    }.

%% Test timestamp increment
timestamp_increment_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(_) ->
            ["Timestamp should be updated for each get_metrics call",
                %% Get first timestamp
                #{timestamp: Timestamp1} = ggen_metrics_collector:get_metrics(),

                %% Wait a bit
                timer:sleep(10),

                %% Get second timestamp
                #{timestamp: Timestamp2} = ggen_metrics_collector:get_metrics(),

                %% Second timestamp should be greater
                ?_assert(Timestamp2 > Timestamp1)
            ]
        end
    }.

%%====================================================================
%% Stress Tests
%%====================================================================

%% Test handling of many metric updates
stress_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(_) ->
            ["Should handle large number of metric updates",
                %% Perform many metric updates
                lists:foreach(fun(_) ->
                    ggen_metrics_collector:increment_metric(stress_metric, 1),
                    ggen_metrics_collector:track_ontology_processed()
                end, lists:seq(1, 1000)),

                %% Check that metrics were tracked correctly
                Metrics = maps:get(metrics, ggen_metrics_collector:get_metrics()),
                ?_assertEqual(1000, maps:get(stress_metric, Metrics)),
                ?_assertEqual(1000, maps:get(ontologies_processed, Metrics))
            ]
        end
    }.

%%====================================================================
%% End of File
%%====================================================================