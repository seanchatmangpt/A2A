# Enterprise Integration Guide

## Table of Contents

- [Single Sign-On (SSO)](#single-sign-on-sso)
- [LDAP Integration](#ldap-integration)
- [SAML Authentication](#saml-authentication)
- [Webhooks](#webhooks)
- [External Systems Integration](#external-systems-integration)
- [Security Best Practices](#security-best-practices)

---

## Single Sign-On (SSO)

### Overview

A2A supports enterprise Single Sign-On to provide seamless authentication across your organization's applications.

### Supported Protocols

- **OAuth 2.0 / OpenID Connect (OIDC)**
- **SAML 2.0**
- **LDAP/Active Directory**

### OAuth 2.0 / OIDC Configuration

#### Environment Variables

```bash
SSO_ENABLED=true
SSO_PROVIDER=oidc
OIDC_ISSUER_URL=https://your-identity-provider.com
OIDC_CLIENT_ID=your-client-id
OIDC_CLIENT_SECRET=your-client-secret
OIDC_REDIRECT_URI=https://your-a2a-instance.com/auth/callback
OIDC_SCOPES=openid,profile,email
```

#### Configuration File (config/sso.json)

```json
{
  "sso": {
    "enabled": true,
    "provider": "oidc",
    "oidc": {
      "issuerUrl": "https://your-identity-provider.com",
      "clientId": "your-client-id",
      "clientSecret": "your-client-secret",
      "redirectUri": "https://your-a2a-instance.com/auth/callback",
      "scopes": ["openid", "profile", "email"],
      "claimsMapping": {
        "userId": "sub",
        "email": "email",
        "name": "name",
        "groups": "groups"
      },
      "jwksUri": "https://your-identity-provider.com/.well-known/jwks.json",
      "tokenEndpoint": "https://your-identity-provider.com/oauth2/token",
      "authorizationEndpoint": "https://your-identity-provider.com/oauth2/authorize",
      "userinfoEndpoint": "https://your-identity-provider.com/oauth2/userinfo"
    }
  }
}
```

#### Implementation Example

```erlang
%% src/auth/a2a_sso_handler.erl
-module(a2a_sso_handler).
-export([init/2, handle_auth/1, verify_token/1]).

init(Req, State) ->
    case cowboy_req:method(Req) of
        <<"GET">> -> handle_login(Req, State);
        <<"POST">> -> handle_callback(Req, State)
    end.

handle_login(Req, State) ->
    AuthUrl = build_auth_url(),
    Req1 = cowboy_req:reply(302, #{<<"location">> => AuthUrl}, Req),
    {ok, Req1, State}.

handle_callback(Req, State) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req),
    #{<<"code">> := Code} = uri_string:dissect_query(Body),
    case exchange_code_for_token(Code) of
        {ok, Token} ->
            {ok, UserInfo} = verify_token(Token),
            Session = create_session(UserInfo),
            Req2 = cowboy_req:set_resp_cookie(<<"session">>, Session, Req1),
            {ok, Req2, State};
        {error, Reason} ->
            Req2 = cowboy_req:reply(401, #{}, <<"Authentication failed">>, Req1),
            {ok, Req2, State}
    end.
```

---

## LDAP Integration

### Overview

Integrate with LDAP or Active Directory for user authentication and directory services.

### Configuration

#### Environment Variables

```bash
LDAP_ENABLED=true
LDAP_HOST=ldap.company.com
LDAP_PORT=636
LDAP_USE_SSL=true
LDAP_BIND_DN=cn=admin,dc=company,dc=com
LDAP_BIND_PASSWORD=your-secure-password
LDAP_BASE_DN=dc=company,dc=com
LDAP_USER_SEARCH_FILTER=(uid={username})
LDAP_GROUP_SEARCH_FILTER=(member={dn})
```

#### Configuration File (config/ldap.json)

```json
{
  "ldap": {
    "enabled": true,
    "servers": [
      {
        "host": "ldap.company.com",
        "port": 636,
        "useSsl": true,
        "priority": 1
      },
      {
        "host": "ldap-backup.company.com",
        "port": 636,
        "useSsl": true,
        "priority": 2
      }
    ],
    "bindDn": "cn=admin,dc=company,dc=com",
    "bindPassword": "your-secure-password",
    "baseDn": "dc=company,dc=com",
    "userSearchFilter": "(uid={username})",
    "groupSearchFilter": "(member={dn})",
    "attributeMapping": {
      "username": "uid",
      "email": "mail",
      "firstName": "givenName",
      "lastName": "sn",
      "groups": "memberOf"
    },
    "poolSize": 10,
    "timeout": 5000,
    "reconnectInterval": 30000
  }
}
```

#### Implementation Example

```erlang
%% src/auth/a2a_ldap_client.erl
-module(a2a_ldap_client).
-export([authenticate/2, search_user/1, get_user_groups/1]).

-define(LDAP_TIMEOUT, 5000).

authenticate(Username, Password) ->
    Config = load_ldap_config(),
    {ok, Handle} = eldap:open([Config#ldap.host],
                               [{port, Config#ldap.port},
                                {ssl, Config#ldap.use_ssl},
                                {timeout, ?LDAP_TIMEOUT}]),

    %% Bind as admin to search for user
    ok = eldap:simple_bind(Handle, Config#ldap.bind_dn, Config#ldap.bind_password),

    %% Search for user
    Filter = build_filter(Config#ldap.user_search_filter, Username),
    case eldap:search(Handle, [{base, Config#ldap.base_dn},
                                {filter, Filter},
                                {scope, eldap:wholeSubtree()}]) of
        {ok, #eldap_search_result{entries = [Entry | _]}} ->
            UserDn = Entry#eldap_entry.object_name,
            %% Try to bind as the user
            case eldap:simple_bind(Handle, UserDn, Password) of
                ok ->
                    UserAttrs = extract_attributes(Entry, Config),
                    eldap:close(Handle),
                    {ok, UserAttrs};
                {error, _} = Error ->
                    eldap:close(Handle),
                    Error
            end;
        {ok, #eldap_search_result{entries = []}} ->
            eldap:close(Handle),
            {error, user_not_found};
        {error, _} = Error ->
            eldap:close(Handle),
            Error
    end.

search_user(Username) ->
    Config = load_ldap_config(),
    {ok, Handle} = eldap:open([Config#ldap.host],
                               [{port, Config#ldap.port},
                                {ssl, Config#ldap.use_ssl}]),
    ok = eldap:simple_bind(Handle, Config#ldap.bind_dn, Config#ldap.bind_password),
    Filter = build_filter(Config#ldap.user_search_filter, Username),
    Result = eldap:search(Handle, [{base, Config#ldap.base_dn},
                                    {filter, Filter}]),
    eldap:close(Handle),
    Result.

get_user_groups(UserDn) ->
    Config = load_ldap_config(),
    {ok, Handle} = eldap:open([Config#ldap.host],
                               [{port, Config#ldap.port},
                                {ssl, Config#ldap.use_ssl}]),
    ok = eldap:simple_bind(Handle, Config#ldap.bind_dn, Config#ldap.bind_password),
    Filter = build_filter(Config#ldap.group_search_filter, UserDn),
    {ok, #eldap_search_result{entries = Entries}} =
        eldap:search(Handle, [{base, Config#ldap.base_dn},
                              {filter, Filter}]),
    eldap:close(Handle),
    Groups = [extract_group_name(E) || E <- Entries],
    {ok, Groups}.
```

---

## SAML Authentication

### Overview

SAML 2.0 provides federated authentication for enterprise single sign-on.

### Configuration

#### Environment Variables

```bash
SAML_ENABLED=true
SAML_ENTRY_POINT=https://idp.company.com/sso/saml
SAML_ISSUER=https://your-a2a-instance.com
SAML_CALLBACK_URL=https://your-a2a-instance.com/auth/saml/callback
SAML_CERT_PATH=/path/to/idp-cert.pem
SAML_PRIVATE_KEY_PATH=/path/to/sp-private-key.pem
SAML_PUBLIC_CERT_PATH=/path/to/sp-public-cert.pem
```

#### Configuration File (config/saml.json)

```json
{
  "saml": {
    "enabled": true,
    "identityProvider": {
      "entryPoint": "https://idp.company.com/sso/saml",
      "issuer": "https://idp.company.com",
      "certificate": "/path/to/idp-cert.pem",
      "singleLogoutService": "https://idp.company.com/slo/saml",
      "signatureAlgorithm": "sha256"
    },
    "serviceProvider": {
      "issuer": "https://your-a2a-instance.com",
      "callbackUrl": "https://your-a2a-instance.com/auth/saml/callback",
      "privateKey": "/path/to/sp-private-key.pem",
      "certificate": "/path/to/sp-public-cert.pem",
      "signAuthRequests": true,
      "wantAssertionsSigned": true,
      "wantResponseSigned": true
    },
    "attributeMapping": {
      "userId": "urn:oid:0.9.2342.19200300.100.1.1",
      "email": "urn:oid:0.9.2342.19200300.100.1.3",
      "firstName": "urn:oid:2.5.4.42",
      "lastName": "urn:oid:2.5.4.4",
      "groups": "urn:oid:1.3.6.1.4.1.5923.1.5.1.1"
    },
    "security": {
      "authnRequestsSigned": true,
      "logoutRequestSigned": true,
      "logoutResponseSigned": true,
      "wantMessagesSigned": true,
      "signMetadata": true,
      "requestedAuthnContext": ["urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport"]
    }
  }
}
```

#### SAML Metadata Generation

```erlang
%% src/auth/a2a_saml_metadata.erl
-module(a2a_saml_metadata).
-export([generate_sp_metadata/0]).

generate_sp_metadata() ->
    Config = load_saml_config(),
    EntityId = Config#saml.sp_issuer,
    AcsUrl = Config#saml.callback_url,
    Certificate = load_certificate(Config#saml.sp_certificate),

    Metadata = io_lib:format(
        "<?xml version=\"1.0\"?>\n"
        "<md:EntityDescriptor xmlns:md=\"urn:oasis:names:tc:SAML:2.0:metadata\"\n"
        "                     entityID=\"~s\">\n"
        "  <md:SPSSODescriptor protocolSupportEnumeration=\"urn:oasis:names:tc:SAML:2.0:protocol\"\n"
        "                      AuthnRequestsSigned=\"true\"\n"
        "                      WantAssertionsSigned=\"true\">\n"
        "    <md:KeyDescriptor use=\"signing\">\n"
        "      <ds:KeyInfo xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\">\n"
        "        <ds:X509Data>\n"
        "          <ds:X509Certificate>~s</ds:X509Certificate>\n"
        "        </ds:X509Data>\n"
        "      </ds:KeyInfo>\n"
        "    </md:KeyDescriptor>\n"
        "    <md:AssertionConsumerService Binding=\"urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST\"\n"
        "                                 Location=\"~s\"\n"
        "                                 index=\"1\"/>\n"
        "  </md:SPSSODescriptor>\n"
        "</md:EntityDescriptor>",
        [EntityId, Certificate, AcsUrl]),

    {ok, iolist_to_binary(Metadata)}.
```

#### SAML Authentication Handler

```erlang
%% src/auth/a2a_saml_handler.erl
-module(a2a_saml_handler).
-export([init_auth/1, handle_assertion/1, validate_response/1]).

init_auth(Req) ->
    Config = load_saml_config(),
    RequestId = generate_request_id(),
    AuthnRequest = build_authn_request(RequestId, Config),
    SignedRequest = sign_request(AuthnRequest, Config),
    EncodedRequest = base64:encode(zlib:compress(SignedRequest)),

    RedirectUrl = build_redirect_url(Config#saml.idp_entry_point, EncodedRequest),
    store_request(RequestId, erlang:timestamp()),

    {redirect, RedirectUrl}.

handle_assertion(Req) ->
    {ok, Body, _} = cowboy_req:read_body(Req),
    Params = uri_string:dissect_query(Body),
    SamlResponse = maps:get(<<"SAMLResponse">>, Params),

    DecodedResponse = base64:decode(SamlResponse),

    case validate_response(DecodedResponse) of
        {ok, Assertion} ->
            UserInfo = extract_attributes(Assertion),
            Session = create_session(UserInfo),
            {ok, Session};
        {error, Reason} ->
            {error, Reason}
    end.

validate_response(Response) ->
    Config = load_saml_config(),

    %% Parse XML
    {ok, Doc} = parse_xml(Response),

    %% Verify signature
    case verify_signature(Doc, Config#saml.idp_certificate) of
        true ->
            %% Extract and validate assertion
            Assertion = extract_assertion(Doc),
            case validate_assertion(Assertion) of
                ok -> {ok, Assertion};
                {error, _} = Error -> Error
            end;
        false ->
            {error, invalid_signature}
    end.
```

---

## Webhooks

### Overview

Webhooks allow external systems to receive real-time notifications about events in A2A.

### Configuration

#### Webhook Definition (config/webhooks.json)

```json
{
  "webhooks": {
    "enabled": true,
    "endpoints": [
      {
        "id": "external-crm",
        "url": "https://crm.company.com/webhooks/a2a",
        "secret": "your-webhook-secret",
        "events": [
          "agent.created",
          "agent.updated",
          "agent.deleted",
          "task.completed",
          "task.failed",
          "workflow.started",
          "workflow.completed"
        ],
        "headers": {
          "X-Custom-Header": "value"
        },
        "retryPolicy": {
          "maxRetries": 3,
          "backoffMultiplier": 2,
          "initialDelay": 1000
        },
        "timeout": 30000,
        "active": true
      }
    ],
    "globalSettings": {
      "maxConcurrent": 100,
      "queueSize": 10000,
      "deadLetterQueue": "webhooks_dlq"
    }
  }
}
```

### Event Types

| Event | Description | Payload |
|-------|-------------|---------|
| `agent.created` | New agent registered | Agent details |
| `agent.updated` | Agent configuration changed | Updated agent details |
| `agent.deleted` | Agent removed | Agent ID |
| `task.started` | Task execution began | Task ID, agent ID, parameters |
| `task.completed` | Task finished successfully | Task ID, result, duration |
| `task.failed` | Task execution failed | Task ID, error details |
| `workflow.started` | Workflow initiated | Workflow ID, agents involved |
| `workflow.completed` | Workflow finished | Workflow ID, final state |
| `system.alert` | System alert triggered | Alert type, severity, details |

### Implementation

```erlang
%% src/webhooks/a2a_webhook_dispatcher.erl
-module(a2a_webhook_dispatcher).
-behaviour(gen_server).

-export([start_link/0, dispatch_event/2, register_webhook/1, unregister_webhook/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-record(state, {
    webhooks = #{},
    queue = queue:new(),
    workers = []
}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

dispatch_event(EventType, Payload) ->
    gen_server:cast(?MODULE, {dispatch, EventType, Payload}).

init([]) ->
    Webhooks = load_webhooks_config(),
    Workers = start_workers(10),
    {ok, #state{webhooks = Webhooks, workers = Workers}}.

handle_cast({dispatch, EventType, Payload}, State) ->
    FilteredWebhooks = filter_webhooks_by_event(EventType, State#state.webhooks),

    lists:foreach(fun(Webhook) ->
        deliver_webhook(Webhook, EventType, Payload)
    end, FilteredWebhooks),

    {noreply, State}.

deliver_webhook(Webhook, EventType, Payload) ->
    Timestamp = erlang:system_time(millisecond),
    RequestBody = jsx:encode(#{
        event => EventType,
        timestamp => Timestamp,
        payload => Payload
    }),

    Signature = generate_signature(RequestBody, Webhook#webhook.secret),

    Headers = [
        {<<"Content-Type">>, <<"application/json">>},
        {<<"X-A2A-Event">>, EventType},
        {<<"X-A2A-Signature">>, Signature},
        {<<"X-A2A-Delivery">>, generate_delivery_id()}
        | maps:to_list(Webhook#webhook.headers)
    ],

    Options = [
        {timeout, Webhook#webhook.timeout},
        {connect_timeout, 5000}
    ],

    case hackney:post(Webhook#webhook.url, Headers, RequestBody, Options) of
        {ok, StatusCode, _RespHeaders, _ClientRef} when StatusCode >= 200, StatusCode < 300 ->
            log_webhook_success(Webhook#webhook.id, EventType),
            ok;
        {ok, StatusCode, _RespHeaders, _ClientRef} ->
            log_webhook_failure(Webhook#webhook.id, EventType, StatusCode),
            retry_webhook(Webhook, EventType, Payload, 1);
        {error, Reason} ->
            log_webhook_error(Webhook#webhook.id, EventType, Reason),
            retry_webhook(Webhook, EventType, Payload, 1)
    end.

retry_webhook(Webhook, EventType, Payload, Attempt) ->
    MaxRetries = Webhook#webhook.retry_policy#retry_policy.max_retries,

    if Attempt > MaxRetries ->
           send_to_dead_letter_queue(Webhook, EventType, Payload),
           {error, max_retries_exceeded};
       true ->
           Delay = calculate_backoff_delay(Attempt, Webhook#webhook.retry_policy),
           timer:apply_after(Delay, ?MODULE, deliver_webhook, [Webhook, EventType, Payload])
    end.

generate_signature(Body, Secret) ->
    Hmac = crypto:mac(hmac, sha256, Secret, Body),
    base64:encode(Hmac).
```

### Webhook Payload Example

```json
{
  "event": "task.completed",
  "timestamp": 1707235200000,
  "payload": {
    "taskId": "task_abc123",
    "agentId": "agent_xyz789",
    "status": "completed",
    "result": {
      "output": "Task completed successfully",
      "artifacts": ["file1.txt", "file2.json"]
    },
    "duration": 5432,
    "startTime": "2026-02-06T10:30:00Z",
    "endTime": "2026-02-06T10:30:05Z"
  }
}
```

### Webhook Security

#### Signature Verification (Recipient Side)

```javascript
// Node.js example
const crypto = require('crypto');

function verifyWebhookSignature(body, signature, secret) {
  const hmac = crypto.createHmac('sha256', secret);
  hmac.update(body);
  const expectedSignature = hmac.digest('base64');

  return crypto.timingSafeEqual(
    Buffer.from(signature),
    Buffer.from(expectedSignature)
  );
}

// Express middleware
app.post('/webhooks/a2a', (req, res) => {
  const signature = req.headers['x-a2a-signature'];
  const body = JSON.stringify(req.body);

  if (!verifyWebhookSignature(body, signature, WEBHOOK_SECRET)) {
    return res.status(401).json({ error: 'Invalid signature' });
  }

  // Process webhook
  const { event, payload } = req.body;
  handleWebhookEvent(event, payload);

  res.status(200).json({ received: true });
});
```

---

## External Systems Integration

### REST API Integration

#### Outbound REST Calls

```erlang
%% src/integration/a2a_rest_client.erl
-module(a2a_rest_client).
-export([call_external_api/4, configure_integration/2]).

-record(api_config, {
    base_url,
    auth_type,
    auth_credentials,
    timeout = 30000,
    retry_policy,
    circuit_breaker
}).

call_external_api(Method, Endpoint, Headers, Body) ->
    Config = get_integration_config(Endpoint),
    Url = build_url(Config#api_config.base_url, Endpoint),

    %% Add authentication
    AuthHeaders = add_auth_headers(Headers, Config),

    %% Check circuit breaker
    case check_circuit_breaker(Config#api_config.circuit_breaker) of
        open ->
            {error, circuit_breaker_open};
        _ ->
            execute_request(Method, Url, AuthHeaders, Body, Config)
    end.

execute_request(Method, Url, Headers, Body, Config) ->
    Options = [
        {timeout, Config#api_config.timeout},
        {connect_timeout, 5000},
        {recv_timeout, Config#api_config.timeout}
    ],

    case hackney:request(Method, Url, Headers, Body, Options) of
        {ok, StatusCode, RespHeaders, ClientRef} when StatusCode >= 200, StatusCode < 300 ->
            {ok, ResponseBody} = hackney:body(ClientRef),
            record_success(Url),
            {ok, StatusCode, RespHeaders, ResponseBody};
        {ok, StatusCode, RespHeaders, ClientRef} ->
            {ok, ResponseBody} = hackney:body(ClientRef),
            record_failure(Url, StatusCode),
            {error, {http_error, StatusCode, ResponseBody}};
        {error, Reason} = Error ->
            record_failure(Url, Reason),
            maybe_retry(Method, Url, Headers, Body, Config, 1),
            Error
    end.

add_auth_headers(Headers, #api_config{auth_type = basic, auth_credentials = {User, Pass}}) ->
    Credentials = base64:encode(<<User/binary, ":", Pass/binary>>),
    [{<<"Authorization">>, <<"Basic ", Credentials/binary>>} | Headers];

add_auth_headers(Headers, #api_config{auth_type = bearer, auth_credentials = Token}) ->
    [{<<"Authorization">>, <<"Bearer ", Token/binary>>} | Headers];

add_auth_headers(Headers, #api_config{auth_type = api_key, auth_credentials = {KeyName, KeyValue}}) ->
    [{KeyName, KeyValue} | Headers];

add_auth_headers(Headers, #api_config{auth_type = oauth2}) ->
    Token = get_oauth2_token(),
    [{<<"Authorization">>, <<"Bearer ", Token/binary>>} | Headers];

add_auth_headers(Headers, _Config) ->
    Headers.
```

### Message Queue Integration

#### RabbitMQ Integration

```erlang
%% src/integration/a2a_rabbitmq_client.erl
-module(a2a_rabbitmq_client).
-export([start_link/0, publish/3, subscribe/2, create_queue/2]).

-record(state, {
    connection,
    channel,
    exchanges = #{},
    queues = #{}
}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    Config = load_rabbitmq_config(),
    {ok, Connection} = amqp_connection:start(#amqp_params_network{
        host = Config#rabbitmq.host,
        port = Config#rabbitmq.port,
        username = Config#rabbitmq.username,
        password = Config#rabbitmq.password,
        virtual_host = Config#rabbitmq.virtual_host
    }),
    {ok, Channel} = amqp_connection:open_channel(Connection),

    {ok, #state{connection = Connection, channel = Channel}}.

publish(Exchange, RoutingKey, Message) ->
    gen_server:call(?MODULE, {publish, Exchange, RoutingKey, Message}).

handle_call({publish, Exchange, RoutingKey, Message}, _From, State) ->
    Payload = jsx:encode(Message),
    Publish = #'basic.publish'{
        exchange = Exchange,
        routing_key = RoutingKey
    },
    Props = #'P_basic'{
        content_type = <<"application/json">>,
        delivery_mode = 2,  % persistent
        timestamp = erlang:system_time(millisecond)
    },
    Msg = #amqp_msg{payload = Payload, props = Props},

    Result = amqp_channel:cast(State#state.channel, Publish, Msg),
    {reply, Result, State}.

subscribe(Queue, Callback) ->
    gen_server:call(?MODULE, {subscribe, Queue, Callback}).

handle_call({subscribe, Queue, Callback}, _From, State) ->
    Subscribe = #'basic.consume'{queue = Queue},
    #'basic.consume_ok'{consumer_tag = Tag} =
        amqp_channel:call(State#state.channel, Subscribe),

    spawn(fun() -> consume_loop(State#state.channel, Tag, Callback) end),

    {reply, {ok, Tag}, State}.

consume_loop(Channel, Tag, Callback) ->
    receive
        {#'basic.deliver'{delivery_tag = DeliveryTag}, #amqp_msg{payload = Payload}} ->
            Message = jsx:decode(Payload, [return_maps]),
            case Callback(Message) of
                ok ->
                    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = DeliveryTag});
                {error, _Reason} ->
                    amqp_channel:cast(Channel, #'basic.nack'{
                        delivery_tag = DeliveryTag,
                        requeue = true
                    })
            end,
            consume_loop(Channel, Tag, Callback)
    end.
```

#### Kafka Integration

```erlang
%% src/integration/a2a_kafka_client.erl
-module(a2a_kafka_client).
-export([start_link/0, produce/2, consume/2]).

start_link() ->
    Config = load_kafka_config(),

    ClientConfig = [
        {endpoints, Config#kafka.brokers},
        {auto_start_producers, true},
        {default_producer_config, [
            {required_acks, all},
            {max_linger_ms, 100},
            {max_batch_size, 1048576}
        ]}
    ],

    {ok, _} = application:ensure_all_started(brod),
    brod:start_client(Config#kafka.brokers, a2a_kafka_client, ClientConfig).

produce(Topic, Messages) when is_list(Messages) ->
    Partition = select_partition(Topic),
    KafkaMessages = lists:map(fun(Msg) ->
        {undefined, jsx:encode(Msg)}
    end, Messages),

    brod:produce_sync(a2a_kafka_client, Topic, Partition, undefined, KafkaMessages).

consume(Topic, GroupId) ->
    ConsumerConfig = [
        {begin_offset, latest},
        {offset_reset_policy, reset_to_latest}
    ],

    GroupConfig = [
        {offset_commit_policy, commit_to_kafka_v2},
        {offset_commit_interval_seconds, 5}
    ],

    {ok, _SubscriberPid} = brod:start_link_group_subscriber(
        a2a_kafka_client,
        GroupId,
        [Topic],
        GroupConfig,
        ConsumerConfig,
        _CallbackModule = ?MODULE,
        _CallbackInitArg = []
    ).

handle_message(_Topic, Partition, Message, State) ->
    #kafka_message{
        offset = Offset,
        key = Key,
        value = Value
    } = Message,

    Payload = jsx:decode(Value, [return_maps]),

    %% Process message
    case process_kafka_message(Payload) of
        ok ->
            {ok, ack, State};
        {error, Reason} ->
            logger:error("Failed to process Kafka message: ~p", [Reason]),
            {ok, ack, State}  % Ack anyway to avoid blocking
    end.
```

### Database Integration

#### PostgreSQL Integration

```erlang
%% src/integration/a2a_postgres_client.erl
-module(a2a_postgres_client).
-export([start_link/0, query/2, transaction/1]).

start_link() ->
    Config = load_postgres_config(),

    PoolConfig = [
        {size, Config#postgres.pool_size},
        {max_overflow, Config#postgres.max_overflow}
    ],

    WorkerArgs = [
        {hostname, Config#postgres.host},
        {port, Config#postgres.port},
        {database, Config#postgres.database},
        {username, Config#postgres.username},
        {password, Config#postgres.password},
        {ssl, Config#postgres.ssl},
        {ssl_opts, Config#postgres.ssl_opts}
    ],

    poolboy:start_link(PoolConfig, WorkerArgs).

query(Sql, Params) ->
    poolboy:transaction(?MODULE, fun(Worker) ->
        epgsql:equery(Worker, Sql, Params)
    end).

transaction(Fun) ->
    poolboy:transaction(?MODULE, fun(Worker) ->
        epgsql:with_transaction(Worker, fun(_) ->
            Fun(Worker)
        end)
    end).
```

### gRPC Integration

```erlang
%% src/integration/a2a_grpc_client.erl
-module(a2a_grpc_client).
-export([start_link/1, call_service/3]).

start_link(ServiceName) ->
    Config = load_grpc_config(ServiceName),

    Options = #{
        host => Config#grpc.host,
        port => Config#grpc.port,
        ssl_options => case Config#grpc.use_tls of
            true -> [
                {verify, verify_peer},
                {cacertfile, Config#grpc.ca_cert},
                {certfile, Config#grpc.cert},
                {keyfile, Config#grpc.key}
            ];
            false -> []
        end,
        compression => gzip,
        keepalive => #{
            keepalive_time_ms => 10000,
            keepalive_timeout_ms => 5000
        }
    },

    grpc_client:start_link(ServiceName, Options).

call_service(ServiceName, Method, Request) ->
    Metadata = #{
        <<"authorization">> => get_auth_token(),
        <<"x-request-id">> => generate_request_id()
    },

    Options = #{
        metadata => Metadata,
        timeout => 30000
    },

    case grpc_client:unary(ServiceName, Method, Request, Options) of
        {ok, Response, _Metadata} ->
            {ok, Response};
        {error, Reason} = Error ->
            logger:error("gRPC call failed: ~p", [Reason]),
            Error
    end.
```

---

## Security Best Practices

### Authentication & Authorization

1. **Multi-Factor Authentication (MFA)**
   - Enforce MFA for administrative accounts
   - Support TOTP and SMS-based authentication
   - Integrate with enterprise MFA providers

2. **Role-Based Access Control (RBAC)**
   ```json
   {
     "roles": [
       {
         "name": "admin",
         "permissions": ["*"]
       },
       {
         "name": "developer",
         "permissions": [
           "agents:read",
           "agents:write",
           "tasks:execute",
           "workflows:read"
         ]
       },
       {
         "name": "viewer",
         "permissions": [
           "agents:read",
           "tasks:read",
           "workflows:read"
         ]
       }
     ]
   }
   ```

3. **API Key Management**
   - Rotate API keys regularly
   - Use separate keys for different environments
   - Implement key expiration policies

### Network Security

1. **TLS/SSL Configuration**
   ```erlang
   SSLOpts = [
       {verify, verify_peer},
       {cacertfile, "/path/to/ca.pem"},
       {certfile, "/path/to/cert.pem"},
       {keyfile, "/path/to/key.pem"},
       {versions, ['tlsv1.2', 'tlsv1.3']},
       {ciphers, [
           "ECDHE-ECDSA-AES256-GCM-SHA384",
           "ECDHE-RSA-AES256-GCM-SHA384",
           "ECDHE-ECDSA-CHACHA20-POLY1305",
           "ECDHE-RSA-CHACHA20-POLY1305"
       ]}
   ].
   ```

2. **IP Whitelisting**
   ```json
   {
     "security": {
       "ipWhitelist": {
         "enabled": true,
         "addresses": [
           "10.0.0.0/8",
           "172.16.0.0/12",
           "192.168.1.0/24"
         ]
       }
     }
   }
   ```

3. **Rate Limiting**
   ```erlang
   %% src/security/a2a_rate_limiter.erl
   -module(a2a_rate_limiter).
   -export([check_rate_limit/2]).

   check_rate_limit(ClientId, Resource) ->
       Key = {ClientId, Resource},
       Limit = get_rate_limit(Resource),
       Window = get_time_window(Resource),

       case ets:lookup(rate_limits, Key) of
           [{_, Count, Timestamp}] ->
               Now = erlang:system_time(second),
               if Now - Timestamp > Window ->
                      ets:insert(rate_limits, {Key, 1, Now}),
                      {ok, Limit - 1};
                  Count >= Limit ->
                      {error, rate_limit_exceeded};
                  true ->
                      ets:insert(rate_limits, {Key, Count + 1, Timestamp}),
                      {ok, Limit - Count - 1}
               end;
           [] ->
               ets:insert(rate_limits, {Key, 1, erlang:system_time(second)}),
               {ok, Limit - 1}
       end.
   ```

### Data Security

1. **Encryption at Rest**
   - Encrypt sensitive data in databases
   - Use key management services (KMS)
   - Implement field-level encryption

2. **Encryption in Transit**
   - Enforce HTTPS for all communications
   - Use mutual TLS for service-to-service communication
   - Implement certificate pinning where appropriate

3. **Audit Logging**
   ```erlang
   %% src/security/a2a_audit_logger.erl
   -module(a2a_audit_logger).
   -export([log_event/4]).

   log_event(UserId, Action, Resource, Result) ->
       Event = #{
           timestamp => erlang:system_time(millisecond),
           user_id => UserId,
           action => Action,
           resource => Resource,
           result => Result,
           ip_address => get_client_ip(),
           user_agent => get_user_agent()
       },

       %% Write to audit log
       write_audit_log(Event),

       %% Send to SIEM if configured
       case get_siem_config() of
           {ok, SiemConfig} ->
               send_to_siem(Event, SiemConfig);
           undefined ->
               ok
       end.
   ```

### Compliance

1. **GDPR Compliance**
   - Implement data retention policies
   - Support right to erasure (right to be forgotten)
   - Maintain data processing records

2. **SOC 2 Compliance**
   - Enable comprehensive audit logging
   - Implement access controls
   - Regular security assessments

3. **HIPAA Compliance** (if handling health data)
   - Encrypt all PHI data
   - Implement access controls and audit trails
   - Business Associate Agreements (BAA)

---

## Configuration Management

### Environment-Specific Configuration

```erlang
%% config/sys.config
[
  {a2a, [
    {environment, production},
    {integration_configs, [
      {sso, "config/prod/sso.json"},
      {ldap, "config/prod/ldap.json"},
      {saml, "config/prod/saml.json"},
      {webhooks, "config/prod/webhooks.json"}
    ]},
    {secrets_manager, #{
      type => aws_secrets_manager,
      region => "us-east-1",
      prefix => "a2a/prod/"
    }}
  ]}
].
```

### Secret Management

```erlang
%% src/config/a2a_secrets_manager.erl
-module(a2a_secrets_manager).
-export([get_secret/1, refresh_secrets/0]).

get_secret(SecretName) ->
    case ets:lookup(secrets_cache, SecretName) of
        [{_, Value, ExpiresAt}] ->
            Now = erlang:system_time(second),
            if Now < ExpiresAt ->
                   {ok, Value};
               true ->
                   fetch_and_cache_secret(SecretName)
            end;
        [] ->
            fetch_and_cache_secret(SecretName)
    end.

fetch_and_cache_secret(SecretName) ->
    Config = application:get_env(a2a, secrets_manager),

    case Config#secrets.type of
        aws_secrets_manager ->
            fetch_from_aws(SecretName, Config);
        azure_key_vault ->
            fetch_from_azure(SecretName, Config);
        hashicorp_vault ->
            fetch_from_vault(SecretName, Config);
        kubernetes_secrets ->
            fetch_from_k8s(SecretName, Config)
    end.
```

---

## Monitoring & Observability

### Metrics Collection

```erlang
%% src/monitoring/a2a_metrics.erl
-module(a2a_metrics).
-export([record_integration_call/3, record_auth_attempt/2]).

record_integration_call(Integration, Duration, Status) ->
    prometheus_histogram:observe(
        integration_call_duration_seconds,
        [Integration, Status],
        Duration / 1000
    ),

    prometheus_counter:inc(
        integration_calls_total,
        [Integration, Status]
    ).

record_auth_attempt(Provider, Success) ->
    prometheus_counter:inc(
        auth_attempts_total,
        [Provider, atom_to_list(Success)]
    ).
```

### Health Checks

```erlang
%% src/monitoring/a2a_health_check.erl
-module(a2a_health_check).
-export([check_all/0, check_integration/1]).

check_all() ->
    Checks = [
        {database, fun check_database/0},
        {ldap, fun check_ldap/0},
        {message_queue, fun check_message_queue/0},
        {external_apis, fun check_external_apis/0}
    ],

    Results = lists:map(fun({Name, CheckFun}) ->
        try CheckFun() of
            ok -> {Name, healthy};
            {error, Reason} -> {Name, {unhealthy, Reason}}
        catch
            _:Error -> {Name, {unhealthy, Error}}
        end
    end, Checks),

    Status = case lists:all(fun({_, healthy}) -> true; (_) -> false end, Results) of
        true -> healthy;
        false -> degraded
    end,

    #{status => Status, checks => maps:from_list(Results)}.
```

---

## Troubleshooting

### Common Issues

1. **LDAP Connection Failures**
   - Verify network connectivity to LDAP server
   - Check SSL/TLS certificate validity
   - Verify bind DN and password
   - Check firewall rules

2. **SAML Authentication Issues**
   - Validate SAML metadata configuration
   - Check certificate expiration
   - Verify clock synchronization
   - Review IdP logs

3. **Webhook Delivery Failures**
   - Check webhook endpoint availability
   - Verify signature validation
   - Review retry attempts in logs
   - Check circuit breaker status

### Debug Mode

```bash
# Enable debug logging
export A2A_LOG_LEVEL=debug
export A2A_DEBUG_INTEGRATIONS=true

# Start A2A with integration debugging
./bin/a2a start --debug-integrations
```

### Support

For enterprise support:
- Email: enterprise@a2a.dev
- Documentation: https://docs.a2a.dev/enterprise
- Support Portal: https://support.a2a.dev
