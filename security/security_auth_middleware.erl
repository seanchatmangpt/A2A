%%% @doc Authentication Middleware
%%% Handles authentication and authorization for HTTP requests

-module(security_auth_middleware).
-export([authenticate/1, authorize/3, extract_token/1, validate_request/1]).

-include_lib("cowboy/include/cowboy_req.hrl").

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Authenticate HTTP request
-spec authenticate(cowboy_req:req()) -> {ok, map()} | {error, term()}.
authenticate(Req) ->
    case extract_token(Req) of
        {ok, Token} ->
            case security_auth:validate_token(Token) of
                {ok, AuthInfo} ->
                    {ok, AuthInfo};
                {error, _} ->
                    {error, invalid_token}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Authorize user for specific resource/action
-spec authorize(map(), binary(), binary()) -> boolean().
authorize(AuthInfo, Resource, Action) ->
    UserId = maps:get(user_id, AuthInfo),
    security_auth:check_permission(UserId, Resource, Action).

%% @doc Extract authentication token from request
-spec extract_token(cowboy_req:req()) -> {ok, binary()} | {error, term()}.
extract_token(Req) ->
    %% Check Authorization header
    case cowboy_req:header(<<"authorization">>, Req) of
        undefined ->
            %% Check API key in query parameters
            case cowboy_req:qs_val(<<"api_key">>, Req) of
                undefined -> {error, missing_token};
                {_, ApiKey} -> security_auth:validate_api_key(ApiKey)
            end;
        <<BearerToken/binary>> ->
            case normalize_token(BearerToken) of
                undefined -> {error, invalid_token_format};
                Token -> {ok, Token}
            end;
        _ ->
            {error, invalid_token_format}
    end.

%% @doc Validate request security
-spec validate_request(cowboy_req:req()) -> {ok, cowboy_req:req()} | {error, term()}.
validate_request(Req) ->
    %% Check rate limiting
    case check_rate_limit(Req) of
        {ok, Req1} ->
            %% Check request size limits
            case check_request_size(Req1) of
                {ok, Req2} ->
                    %% Validate content type
                    case validate_content_type(Req2) of
                        {ok, Req3} ->
                            {ok, Req3};
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%%====================================================================
%% Internal Functions
%%====================================================================

normalize_token(BearerToken) ->
    %% Remove "Bearer " prefix if present
    case re:run(BearerToken, "^Bearer\\s+(.+)$", [{capture, [1], binary}]) of
        match -> BearerToken;
        nomatch -> case re:run(BearerToken, "^cpk_(.+)$", [{capture, [1], binary}]) of
            match -> BearerToken; % API key
            nomatch -> undefined
        end
    end.

check_rate_limit(Req) ->
    %% Simple rate limiting implementation
    %% In production, use a proper rate limiting library
    ClientIP = get_client_ip(Req),
    CurrentTime = os:system_time(second),

    %% Check if client has exceeded rate limit
    case get_rate_limit(ClientIP, CurrentTime) of
        {ok, Count} when Count > 1000 -> % 1000 requests per minute
            {error, rate_limit_exceeded};
        _ ->
            {ok, Req}
    end.

check_request_size(Req) ->
    case cowboy_req:has_body(Req) of
        true ->
            case cowboy_req:body_length(Req) of
                Length when Length > 10485760 -> % 10MB limit
                    {error, request_too_large};
                _ ->
                    {ok, Req}
            end;
        false ->
            {ok, Req}
    end.

validate_content_type(Req) ->
    case cowboy_req:header(<<"content-type">>, Req) of
        undefined ->
            {ok, Req}; % No content type for requests without body
        ContentType ->
            case re:run(ContentType, "^application/(json|ld\\+json)") of
                match -> {ok, Req};
                nomatch -> {error, invalid_content_type}
            end
    end.

get_client_ip(Req) ->
    case cowboy_req:header(<<"x-forwarded-for">>, Req) of
        undefined ->
            case cowboy_req:header(<<"x-real-ip">>, Req) of
                undefined ->
                    cowboy_req:peer(Req);
                IP ->
                    IP
            end;
        IPs ->
            %% Get the first IP from the list
            case binary:split(IPs, <<", ">>) of
                [First | _] -> First;
                [First] -> First
            end
    end.

get_rate_limit(ClientIP, CurrentTime) ->
    %% Simple rate limiting - in production use Redis or similar
    %% This is a placeholder implementation
    {ok, 0}.