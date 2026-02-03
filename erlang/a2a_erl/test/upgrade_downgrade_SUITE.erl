%%% @doc A2A Hot Code Upgrade/Downgrade Test Suite
%%%
%%% This Common Test suite validates hot code upgrades and downgrades
%%% for the A2A Erlang/OTP implementation using the peer module.
%%% @end
-module(upgrade_downgrade_SUITE).
-behaviour(ct_suite).
-export([all/0, groups/0]).
-compile(export_all).

-include_lib("stdlib/include/assert.hrl").
-include_lib("common_test/include/ct.hrl").

groups() ->
    [{upgrade_downgrade, [sequence],
      [before_upgrade_case, upgrade_case, after_upgrade_case,
       before_downgrade_case, downgrade_case, after_downgrade_case]}].

all() ->
    [{group, upgrade_downgrade}].

suite() ->
    [
        {require, old_version},
        {require, new_version},
        {require, release_name},
        {require, release_dir}
    ].

init_per_suite(Config) ->
    ct:print("Initializing A2A upgrade/downgrade suite..."),
    ct:log(info, ?LOW_IMPORTANCE, "Initializing suite...", []),
    Docker = os:find_executable("docker"),
    case Docker of
        false ->
            ct:fail("Docker not found. HotCI requires Docker for upgrade testing.");
        _ ->
            ok
    end,
    build_image(),
    ReleaseName = ct:get_config(release_name),

    {ok, Peer, Node} = peer:start(#{name => ReleaseName,
        connection => standard_io,
        exec => {Docker, ["run", "-h", "one", "-i", ReleaseName]}}),

    [{peer, Peer}, {node, Node} | Config].

end_per_suite(Config) ->
    Peer = ?config(peer, Config),
    peer:stop(Peer).

% ========== CASES ==========

before_upgrade_case(Config) ->
    Peer = ?config(peer, Config),
    ct:print("Running pre-upgrade checks..."),

    %% Check that A2A application is running
    {ok, Apps} = peer:call(Peer, application, which_applications, []),
    ct:log("Running applications: ~p", [Apps]),
    ?assert(lists:keymember(a2a_erl, 1, Apps)),

    %% Check that HTTP handlers are available
    case peer:call(Peer, erlang, whereis, [a2a_http_sup]) of
        {badrpc, _} -> ct:log("HTTP supervisor not found (expected for initial version)");
        Pid when is_pid(Pid) -> ct:log("HTTP supervisor found: ~p", [Pid])
    end,

    %% Verify system is healthy
    {ok, _} = peer:call(Peer, erlang, system_info, [system_architecture]),
    ct:print("Pre-upgrade checks passed."),
    ok.

upgrade_case(Config) ->
    Peer = ?config(peer, Config),
    NewVSN = ct:get_config(new_version),
    OldVSN = ct:get_config(old_version),
    ReleaseName = ct:get_config(release_name),
    NewReleaseName = filename:join(NewVSN, ReleaseName),

    ct:print("Upgrading from ~s to ~s", [OldVSN, NewVSN]),

    %% Unpack the new release
    {ok, NewVSN} = peer:call(Peer, release_handler, unpack_release, [NewReleaseName]),
    ct:log("Unpacked release: ~s", [NewVSN]),

    %% Check that new release is unpacked
    Unpacked = peer:call(Peer, release_handler, which_releases, []),
    ct:log("Releases after unpack: ~p", [Unpacked]),

    %% Install the new release
    {ok, OldVSN, _} = peer:call(Peer, release_handler, install_release, [NewVSN]),
    ct:log("Installed release: ~s", [NewVSN]),

    %% Make the upgrade permanent
    ok = peer:call(Peer, release_handler, make_permanent, [NewVSN]),
    ct:log("Made release permanent: ~s", [NewVSN]),

    %% Verify the upgrade
    Releases = peer:call(Peer, release_handler, which_releases, []),
    ct:print("Installed releases after upgrade:\n~p", [Releases]),

    %% Verify A2A application is still running
    {ok, Apps} = peer:call(Peer, application, which_applications, []),
    ?assert(lists:keymember(a2a_erl, 1, Apps)),
    ct:print("A2A application still running after upgrade."),
    ok.

after_upgrade_case(Config) ->
    Peer = ?config(peer, Config),
    ct:print("Running post-upgrade checks..."),

    %% Verify modules are loaded
    {ok, Modules} = peer:call(Peer, code, all_loaded, []),
    A2AModules = [M || {M, _} <- Modules,
                      lists:prefix(atom_to_list(M), "a2a_")],
    ct:log("A2A modules loaded: ~p", [A2AModules]),
    ?assert(length(A2AModules) > 0),

    %% Check process status
    Processes = peer:call(Peer, erlang, processes, []),
    ct:log("Total processes: ~p", [length(Processes)]),
    ?assert(length(Processes) > 0),

    %% Verify message handling works
    Self = self(),
    spawn(fun() ->
        Result = peer:call(Peer, erlang, system_info, [otp_release]),
        Self ! {result, Result}
    end),
    receive
        {result, _} -> ct:print("Message handling verified.")
    after 5000 ->
        ct:fail("Message handling timeout")
    end,
    ok.

before_downgrade_case(Config) ->
    Peer = ?config(peer, Config),
    ct:print("Running pre-downgrade checks..."),

    %% Verify current version is still active
    Releases = peer:call(Peer, release_handler, which_releases, []),
    ct:log("Current releases: ~p", [Releases]),
    ?assert(length(Releases) > 0),

    %% Verify A2A is functioning
    {ok, Apps} = peer:call(Peer, application, which_applications, []),
    ?assert(lists:keymember(a2a_erl, 1, Apps)),
    ct:print("Pre-downgrade checks passed."),
    ok.

downgrade_case(Config) ->
    Peer = ?config(peer, Config),
    OldVSN = ct:get_config(old_version),

    ct:print("Downgrading to ~s", [OldVSN]),

    %% Install the old version (downgrade)
    {ok, OldVSN, _} = peer:call(Peer, release_handler, install_release, [OldVSN]),
    ct:log("Installed old release: ~s", [OldVSN]),

    %% Make the downgrade permanent
    ok = peer:call(Peer, release_handler, make_permanent, [OldVSN]),
    ct:log("Made release permanent: ~s", [OldVSN]),

    %% Verify the downgrade
    Releases = peer:call(Peer, release_handler, which_releases, []),
    ct:print("Installed releases after downgrade:\n~p", [Releases]),

    %% Verify A2A application is still running
    {ok, Apps} = peer:call(Peer, application, which_applications, []),
    ?assert(lists:keymember(a2a_erl, 1, Apps)),
    ct:print("A2A application still running after downgrade."),
    ok.

after_downgrade_case(Config) ->
    Peer = ?config(peer, Config),
    ct:print("Running post-downgrade checks..."),

    %% Verify system stability
    ProcessCount = peer:call(Peer, erlang, system_info, [process_count]),
    ct:log("Process count: ~p", [ProcessCount]),
    ?assert(ProcessCount > 0),

    %% Verify memory usage
    Memory = peer:call(Peer, erlang, memory, [total]),
    ct:log("Total memory: ~p bytes", [Memory]),
    ?assert(Memory > 0),

    %% Final health check
    {ok, Apps} = peer:call(Peer, application, which_applications, []),
    ?assert(lists:keymember(a2a_erl, 1, Apps)),
    ?assert(lists:keymember(sasl, 1, Apps)),

    ct:print("Post-downgrade checks passed."),
    ok.

% ========== HELPERS ==========

build_image() ->
    NewVSN = ct:get_config(new_version),
    OldVSN = ct:get_config(old_version),
    ReleaseName = ct:get_config(release_name),
    NewReleaseName = ReleaseName ++ "-" ++ NewVSN,
    OldReleaseName = ReleaseName ++ "-" ++ OldVSN,
    ReleaseDir = ct:get_config(release_dir),

    NewReleasePath = filename:join(ReleaseDir, NewReleaseName ++ ".tar.gz"),
    ct:log("New release path: ~s", [NewReleasePath]),
    file:copy(NewReleasePath, "./" ++ NewReleaseName ++ ".tar.gz"),

    OldReleasePath = filename:join(ReleaseDir, OldReleaseName ++ ".tar.gz"),
    ct:log("Old release path: ~s", [OldReleasePath]),
    file:copy(OldReleasePath, "./" ++ OldReleaseName ++ ".tar.gz"),

    %% Create Dockerfile for A2A release testing
    %% Expose port 4445, and make Erlang distribution to listen
    %% on this port, and connect to it without EPMD
    %% Set cookie on both nodes to be the same.
    BuildScript = filename:join("./", "Dockerfile"),
    Dockerfile =
        "FROM ubuntu:22.04 as runner\n"
        "EXPOSE 4445 8080\n"
        "WORKDIR /opt/" ++ ReleaseName ++  "\n"
        "COPY [\"" ++ OldReleaseName ++ ".tar.gz\", \"" ++ NewReleaseName ++ ".tar.gz\"" ++ ", \"/tmp/\"]\n"
        "RUN tar -zxvf /tmp/" ++ OldReleaseName ++ ".tar.gz -C /opt/" ++ ReleaseName ++ "\n"
        "RUN mkdir -p /opt/" ++ ReleaseName ++ "/releases/" ++ NewVSN ++ "\n"
        "RUN cp /tmp/" ++ NewReleaseName ++ ".tar.gz /opt/" ++ ReleaseName ++ "/releases/" ++ NewVSN ++ "/" ++ ReleaseName ++ ".tar.gz\n"
        "ENTRYPOINT [\"/opt/" ++ ReleaseName ++ "/erts-" ++ erlang:system_info(version) ++
        "/bin/dyn_erl\", \"-boot\", \"/opt/" ++ ReleaseName ++ "/releases/" ++ OldVSN ++ "/start\","
        " \"-kernel\", \"inet_dist_listen_min\", \"4445\","
        " \"-erl_epmd_port\", \"4445\","
        " \"-setcookie\", \"a2a_secret\"]\n",
    ct:log(info, ?LOW_IMPORTANCE, "Dockerfile:\n~s", [Dockerfile]),
    ok = file:write_file(BuildScript, Dockerfile),

    ct:print("Building Docker image..."),
    DockerBuildResult = os:cmd("docker build -t " ++ ReleaseName ++ " . 2>&1"),
    ct:log(info, ?LOW_IMPORTANCE, "Docker build:\n~s", [DockerBuildResult]),
    case string:str(DockerBuildResult, "Successfully built") of
        0 -> ct:fail("Docker build failed: ~s", [DockerBuildResult]);
        _ -> ct:print("Docker image built successfully.")
    end.
