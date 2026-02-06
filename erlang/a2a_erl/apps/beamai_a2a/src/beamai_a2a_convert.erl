%%%-------------------------------------------------------------------
%%% @doc BeamAI A2A Type Conversion
%%%
%%% Converts between the existing a2a.hrl record types used by the
%%% a2a_erl application and the flat map representations used by the
%%% BeamAI framework.
%%%
%%% Direction helpers:
%%%   to_beamai/1   - record  -> BeamAI map
%%%   from_beamai/1 - BeamAI map -> record
%%%
%%% Specific converters:
%%%   task_to_map/1, map_to_task/1
%%%   message_to_map/1, map_to_message/1
%%%   part_to_map/1, map_to_part/1
%%%   artifact_to_map/1, map_to_artifact/1
%%%   agent_card_to_map/1, map_to_agent_card/1
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_a2a_convert).

-include("a2a.hrl").

%% High-level API
-export([
    to_beamai/1,
    from_beamai/1
]).

%% Task conversion
-export([
    task_to_map/1,
    map_to_task/1
]).

%% Message conversion
-export([
    message_to_map/1,
    map_to_message/1
]).

%% Part conversion
-export([
    part_to_map/1,
    map_to_part/1
]).

%% Artifact conversion
-export([
    artifact_to_map/1,
    map_to_artifact/1
]).

%% Task status conversion
-export([
    task_status_to_map/1,
    map_to_task_status/1
]).

%% Agent card conversion
-export([
    agent_card_to_map/1,
    map_to_agent_card/1
]).

%% Push notification config conversion
-export([
    push_config_to_map/1,
    map_to_push_config/1
]).

%%====================================================================
%% High-level dispatch
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Convert an a2a.hrl record to a BeamAI map.
%%
%% Dispatches based on the record type. Unknown terms pass through
%% as-is (maps are returned unchanged).
%% @end
%%--------------------------------------------------------------------
-spec to_beamai(term()) -> map().
to_beamai(#task{} = T)           -> task_to_map(T);
to_beamai(#message{} = M)        -> message_to_map(M);
to_beamai(#part{} = P)           -> part_to_map(P);
to_beamai(#artifact{} = A)       -> artifact_to_map(A);
to_beamai(#task_status{} = S)    -> task_status_to_map(S);
to_beamai(#agent_card{} = C)     -> agent_card_to_map(C);
to_beamai(#push_notification_config{} = P) -> push_config_to_map(P);
to_beamai(Map) when is_map(Map)  -> Map;
to_beamai(Other)                 -> #{<<"value">> => Other}.

%%--------------------------------------------------------------------
%% @doc Convert a BeamAI map to an a2a.hrl record.
%%
%% Uses the `<<"type">>' key to select the target record, falling
%% back to heuristic field-presence detection.
%% @end
%%--------------------------------------------------------------------
-spec from_beamai(map()) -> term().
from_beamai(#{<<"type">> := <<"task">>} = M)     -> map_to_task(M);
from_beamai(#{<<"type">> := <<"message">>} = M)  -> map_to_message(M);
from_beamai(#{<<"type">> := <<"part">>} = M)     -> map_to_part(M);
from_beamai(#{<<"type">> := <<"artifact">>} = M) -> map_to_artifact(M);
from_beamai(#{<<"type">> := <<"agent_card">>} = M) -> map_to_agent_card(M);
%% Heuristic: detect by key presence
from_beamai(#{<<"contextId">> := _, <<"status">> := _} = M) -> map_to_task(M);
from_beamai(#{<<"messageId">> := _, <<"role">> := _} = M)   -> map_to_message(M);
from_beamai(#{<<"artifactId">> := _} = M) -> map_to_artifact(M);
from_beamai(#{<<"skills">> := _} = M)     -> map_to_agent_card(M);
from_beamai(Map) -> Map.

%%====================================================================
%% Task conversion
%%====================================================================

-spec task_to_map(#task{}) -> map().
task_to_map(#task{} = T) ->
    Base = #{
        <<"type">>      => <<"task">>,
        <<"id">>        => T#task.id,
        <<"contextId">> => T#task.context_id,
        <<"status">>    => task_status_to_map(T#task.status)
    },
    M1 = case T#task.artifacts of
        [] -> Base;
        Arts -> Base#{<<"artifacts">> => [artifact_to_map(A) || A <- Arts]}
    end,
    M2 = case T#task.history of
        [] -> M1;
        Hist -> M1#{<<"history">> => [message_to_map(Msg) || Msg <- Hist]}
    end,
    case T#task.metadata of
        Meta when map_size(Meta) =:= 0 -> M2;
        Meta -> M2#{<<"metadata">> => Meta}
    end.

-spec map_to_task(map()) -> #task{}.
map_to_task(M) ->
    #task{
        id         = maps:get(<<"id">>, M),
        context_id = maps:get(<<"contextId">>, M),
        status     = map_to_task_status(maps:get(<<"status">>, M)),
        artifacts  = [map_to_artifact(A) || A <- maps:get(<<"artifacts">>, M, [])],
        history    = [map_to_message(Msg) || Msg <- maps:get(<<"history">>, M, [])],
        metadata   = maps:get(<<"metadata">>, M, #{})
    }.

%%====================================================================
%% Task status conversion
%%====================================================================

-spec task_status_to_map(#task_status{}) -> map().
task_status_to_map(#task_status{} = S) ->
    Base = #{
        <<"state">>     => atom_to_binary(S#task_status.state, utf8),
        <<"timestamp">> => S#task_status.timestamp
    },
    case S#task_status.message of
        undefined -> Base;
        Msg       -> Base#{<<"message">> => message_to_map(Msg)}
    end.

-spec map_to_task_status(map()) -> #task_status{}.
map_to_task_status(M) ->
    State = beamai_a2a_types:task_state(maps:get(<<"state">>, M)),
    NormState = case State of
        {error, _} -> submitted;
        S -> S
    end,
    #task_status{
        state     = NormState,
        message   = case maps:get(<<"message">>, M, undefined) of
                        undefined -> undefined;
                        MsgMap    -> map_to_message(MsgMap)
                    end,
        timestamp = maps:get(<<"timestamp">>, M, 0)
    }.

%%====================================================================
%% Message conversion
%%====================================================================

-spec message_to_map(#message{}) -> map().
message_to_map(#message{} = Msg) ->
    Base = #{
        <<"type">>      => <<"message">>,
        <<"messageId">> => Msg#message.message_id,
        <<"role">>      => atom_to_binary(Msg#message.role, utf8),
        <<"parts">>     => [part_to_map(P) || P <- Msg#message.parts]
    },
    M1 = case Msg#message.context_id of
        undefined -> Base;
        CId       -> Base#{<<"contextId">> => CId}
    end,
    M2 = case Msg#message.task_id of
        undefined -> M1;
        TId       -> M1#{<<"taskId">> => TId}
    end,
    M3 = case Msg#message.metadata of
        Meta when map_size(Meta) =:= 0 -> M2;
        Meta -> M2#{<<"metadata">> => Meta}
    end,
    M4 = case Msg#message.extensions of
        [] -> M3;
        Ext -> M3#{<<"extensions">> => Ext}
    end,
    case Msg#message.reference_task_ids of
        [] -> M4;
        Refs -> M4#{<<"referenceTaskIds">> => Refs}
    end.

-spec map_to_message(map()) -> #message{}.
map_to_message(M) ->
    RoleRaw = maps:get(<<"role">>, M),
    Role = case beamai_a2a_types:message_role(RoleRaw) of
        {error, _} -> user;
        R          -> R
    end,
    #message{
        message_id         = maps:get(<<"messageId">>, M),
        context_id         = maps:get(<<"contextId">>, M, undefined),
        task_id            = maps:get(<<"taskId">>, M, undefined),
        role               = Role,
        parts              = [map_to_part(P) || P <- maps:get(<<"parts">>, M, [])],
        metadata           = maps:get(<<"metadata">>, M, #{}),
        extensions         = maps:get(<<"extensions">>, M, []),
        reference_task_ids = maps:get(<<"referenceTaskIds">>, M, [])
    }.

%%====================================================================
%% Part conversion
%%====================================================================

-spec part_to_map(#part{}) -> map().
part_to_map(#part{} = P) ->
    Base = case P#part.content of
        {text, Text} -> #{<<"text">> => Text};
        {raw, Raw}   -> #{<<"raw">> => base64:encode(Raw)};
        {url, Url}   -> #{<<"url">> => Url};
        {data, Data} -> #{<<"data">> => Data}
    end,
    M1 = case P#part.metadata of
        Meta when map_size(Meta) =:= 0 -> Base;
        Meta -> Base#{<<"metadata">> => Meta}
    end,
    M2 = case P#part.filename of
        undefined -> M1;
        F -> M1#{<<"filename">> => F}
    end,
    case P#part.media_type of
        undefined -> M2;
        MT -> M2#{<<"mediaType">> => MT}
    end.

-spec map_to_part(map()) -> #part{}.
map_to_part(M) ->
    Content = case M of
        #{<<"text">> := Text} -> {text, Text};
        #{<<"raw">> := Raw}   -> {raw, base64:decode(Raw)};
        #{<<"url">> := Url}   -> {url, Url};
        #{<<"data">> := Data} -> {data, Data};
        _                     -> {text, <<>>}
    end,
    #part{
        content    = Content,
        metadata   = maps:get(<<"metadata">>, M, #{}),
        filename   = maps:get(<<"filename">>, M, undefined),
        media_type = maps:get(<<"mediaType">>, M, undefined)
    }.

%%====================================================================
%% Artifact conversion
%%====================================================================

-spec artifact_to_map(#artifact{}) -> map().
artifact_to_map(#artifact{} = A) ->
    Base = #{
        <<"type">>       => <<"artifact">>,
        <<"artifactId">> => A#artifact.artifact_id,
        <<"parts">>      => [part_to_map(P) || P <- A#artifact.parts]
    },
    M1 = case A#artifact.name of
        undefined -> Base;
        N -> Base#{<<"name">> => N}
    end,
    M2 = case A#artifact.description of
        undefined -> M1;
        D -> M1#{<<"description">> => D}
    end,
    M3 = case A#artifact.metadata of
        Meta when map_size(Meta) =:= 0 -> M2;
        Meta -> M2#{<<"metadata">> => Meta}
    end,
    case A#artifact.extensions of
        [] -> M3;
        Ext -> M3#{<<"extensions">> => Ext}
    end.

-spec map_to_artifact(map()) -> #artifact{}.
map_to_artifact(M) ->
    #artifact{
        artifact_id = maps:get(<<"artifactId">>, M),
        name        = maps:get(<<"name">>, M, undefined),
        description = maps:get(<<"description">>, M, undefined),
        parts       = [map_to_part(P) || P <- maps:get(<<"parts">>, M, [])],
        metadata    = maps:get(<<"metadata">>, M, #{}),
        extensions  = maps:get(<<"extensions">>, M, [])
    }.

%%====================================================================
%% Agent card conversion
%%====================================================================

-spec agent_card_to_map(#agent_card{}) -> map().
agent_card_to_map(#agent_card{} = C) ->
    Base = #{
        <<"type">>              => <<"agent_card">>,
        <<"name">>              => C#agent_card.name,
        <<"description">>       => C#agent_card.description,
        <<"version">>           => C#agent_card.version,
        <<"defaultInputModes">> => C#agent_card.default_input_modes,
        <<"defaultOutputModes">>=> C#agent_card.default_output_modes,
        <<"skills">>            => [skill_to_map(S) || S <- C#agent_card.skills],
        <<"supportedInterfaces">> =>
            [interface_to_map(I) || I <- C#agent_card.supported_interfaces],
        <<"capabilities">>      => capabilities_to_map(C#agent_card.capabilities)
    },
    M1 = case C#agent_card.provider of
        undefined -> Base;
        P -> Base#{<<"provider">> => provider_to_map(P)}
    end,
    M2 = case C#agent_card.documentation_url of
        undefined -> M1;
        D -> M1#{<<"documentationUrl">> => D}
    end,
    M3 = case C#agent_card.security_schemes of
        Sec when map_size(Sec) =:= 0 -> M2;
        Sec -> M2#{<<"securitySchemes">> => Sec}
    end,
    M4 = case C#agent_card.security_requirements of
        [] -> M3;
        Reqs -> M3#{<<"securityRequirements">> => Reqs}
    end,
    M5 = case C#agent_card.icon_url of
        undefined -> M4;
        Icon -> M4#{<<"iconUrl">> => Icon}
    end,
    M5.

-spec map_to_agent_card(map()) -> #agent_card{}.
map_to_agent_card(M) ->
    #agent_card{
        name = maps:get(<<"name">>, M),
        description = maps:get(<<"description">>, M),
        version = maps:get(<<"version">>, M),
        supported_interfaces =
            [map_to_interface(I) || I <- maps:get(<<"supportedInterfaces">>, M, [])],
        provider = case maps:get(<<"provider">>, M, undefined) of
            undefined -> undefined;
            P -> map_to_provider(P)
        end,
        documentation_url = maps:get(<<"documentationUrl">>, M, undefined),
        capabilities = map_to_capabilities(
            maps:get(<<"capabilities">>, M, #{})
        ),
        security_schemes = maps:get(<<"securitySchemes">>, M, #{}),
        security_requirements = maps:get(<<"securityRequirements">>, M, []),
        default_input_modes = maps:get(<<"defaultInputModes">>, M, []),
        default_output_modes = maps:get(<<"defaultOutputModes">>, M, []),
        skills = [map_to_skill(S) || S <- maps:get(<<"skills">>, M, [])],
        icon_url = maps:get(<<"iconUrl">>, M, undefined)
    }.

%%====================================================================
%% Push notification config conversion
%%====================================================================

-spec push_config_to_map(#push_notification_config{}) -> map().
push_config_to_map(#push_notification_config{} = C) ->
    Base = #{<<"url">> => C#push_notification_config.url},
    M1 = case C#push_notification_config.id of
        undefined -> Base;
        Id -> Base#{<<"id">> => Id}
    end,
    M2 = case C#push_notification_config.token of
        undefined -> M1;
        T -> M1#{<<"token">> => T}
    end,
    case C#push_notification_config.authentication of
        undefined -> M2;
        #authentication_info{scheme = Scheme, credentials = Creds} ->
            AuthMap = #{<<"scheme">> => Scheme},
            AuthMap2 = case Creds of
                undefined -> AuthMap;
                _ -> AuthMap#{<<"credentials">> => Creds}
            end,
            M2#{<<"authentication">> => AuthMap2}
    end.

-spec map_to_push_config(map()) -> #push_notification_config{}.
map_to_push_config(M) ->
    #push_notification_config{
        id = maps:get(<<"id">>, M, undefined),
        url = maps:get(<<"url">>, M),
        token = maps:get(<<"token">>, M, undefined),
        authentication = case maps:get(<<"authentication">>, M, undefined) of
            undefined -> undefined;
            AMap ->
                #authentication_info{
                    scheme = maps:get(<<"scheme">>, AMap),
                    credentials = maps:get(<<"credentials">>, AMap, undefined)
                }
        end
    }.

%%====================================================================
%% Internal helpers - sub-record conversion
%%====================================================================

skill_to_map(#agent_skill{} = S) ->
    Base = #{
        <<"id">>          => S#agent_skill.id,
        <<"name">>        => S#agent_skill.name,
        <<"description">> => S#agent_skill.description,
        <<"tags">>        => S#agent_skill.tags
    },
    M1 = case S#agent_skill.examples of
        [] -> Base;
        Ex -> Base#{<<"examples">> => Ex}
    end,
    M2 = case S#agent_skill.input_modes of
        [] -> M1;
        I -> M1#{<<"inputModes">> => I}
    end,
    M3 = case S#agent_skill.output_modes of
        [] -> M2;
        O -> M2#{<<"outputModes">> => O}
    end,
    case S#agent_skill.security_requirements of
        [] -> M3;
        Sec -> M3#{<<"securityRequirements">> => Sec}
    end.

map_to_skill(M) ->
    #agent_skill{
        id = maps:get(<<"id">>, M),
        name = maps:get(<<"name">>, M),
        description = maps:get(<<"description">>, M),
        tags = maps:get(<<"tags">>, M, []),
        examples = maps:get(<<"examples">>, M, []),
        input_modes = maps:get(<<"inputModes">>, M, []),
        output_modes = maps:get(<<"outputModes">>, M, []),
        security_requirements = maps:get(<<"securityRequirements">>, M, [])
    }.

interface_to_map(#agent_interface{} = I) ->
    Base = #{
        <<"url">>             => I#agent_interface.url,
        <<"protocolBinding">> => I#agent_interface.protocol_binding,
        <<"protocolVersion">> => I#agent_interface.protocol_version
    },
    case I#agent_interface.tenant of
        undefined -> Base;
        T -> Base#{<<"tenant">> => T}
    end.

map_to_interface(M) ->
    #agent_interface{
        url = maps:get(<<"url">>, M),
        protocol_binding = maps:get(<<"protocolBinding">>, M),
        tenant = maps:get(<<"tenant">>, M, undefined),
        protocol_version = maps:get(<<"protocolVersion">>, M)
    }.

capabilities_to_map(#agent_capabilities{} = C) ->
    Base = #{},
    M1 = case C#agent_capabilities.streaming of
        undefined -> Base;
        S -> Base#{<<"streaming">> => S}
    end,
    M2 = case C#agent_capabilities.push_notifications of
        undefined -> M1;
        P -> M1#{<<"pushNotifications">> => P}
    end,
    M3 = case C#agent_capabilities.extended_agent_card of
        undefined -> M2;
        E -> M2#{<<"extendedAgentCard">> => E}
    end,
    case C#agent_capabilities.extensions of
        [] -> M3;
        _ -> M3
    end.

map_to_capabilities(M) ->
    #agent_capabilities{
        streaming = maps:get(<<"streaming">>, M, undefined),
        push_notifications = maps:get(<<"pushNotifications">>, M, undefined),
        extended_agent_card = maps:get(<<"extendedAgentCard">>, M, undefined),
        extensions = []
    }.

provider_to_map(#agent_provider{} = P) ->
    #{
        <<"url">>          => P#agent_provider.url,
        <<"organization">> => P#agent_provider.organization
    }.

map_to_provider(M) ->
    #agent_provider{
        url = maps:get(<<"url">>, M),
        organization = maps:get(<<"organization">>, M)
    }.
