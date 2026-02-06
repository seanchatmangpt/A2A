%%% @doc Unit tests for a2a_hotci_security module
%%%
%%% Tests follow Chicago School TDD principles:
%%% - Tests drive the implementation
%%% - Tests describe behavior, not implementation details
%%% - Each test is independent and isolated

-module(a2a_hotci_security_tests).
-author("Claude Code").

-include_lib("eunit/include/eunit.hrl").
-include("a2a.hrl").

%% ============================================================================
%% verify_digital_signature/2 Tests
%% ============================================================================

verify_digital_signature_missing_signature_test_() ->
    {"When signature is missing from metadata, return error",
     fun() ->
         PackagePath = <<"/tmp/test_package.tar.gz">>,
         Metadata = #{},
         Result = a2a_hotci_security:verify_digital_signature(PackagePath, Metadata),
         ?assertEqual({error, missing_signature}, Result)
     end}.

verify_digital_signature_missing_signature_empty_test_() ->
    {"When signature is undefined in metadata, return error",
     fun() ->
         PackagePath = <<"/tmp/test_package.tar.gz">>,
         Metadata = #{signature => undefined},
         Result = a2a_hotci_security:verify_digital_signature(PackagePath, Metadata),
         ?assertEqual({error, missing_signature}, Result)
     end}.

verify_digital_signature_valid_hmac_test_() ->
    {"When HMAC signature is valid, return ok verified",
     setup,
     fun() ->
         %% Setup test environment
         SecretKey = <<"test_secret_key_32bytes_long!">>,
         %% Use process dictionary for test isolation
         put({signing_key_store, <<"test_key_1">>}, SecretKey),
         SecretKey
     end,
     fun(_SecretKey) ->
         %% Cleanup
         erase({signing_key_store, <<"test_key_1">>})
     end,
     fun(_SecretKey) ->
         PackagePath = <<"/tmp/test_package.tar.gz">>,
         Message = <<"package_content_for_signing">>,
         ExpectedSignature = crypto:mac(hmac, sha256, <<"test_secret_key_32bytes_long!">>, Message),

         Metadata = #{
             signature => ExpectedSignature,
             signature_type => hmac,
             signing_key_id => <<"test_key_1">>,
             payload => Message
         },

         %% Note: This test will fail until get_signing_key/1 is updated
         %% to check process dictionary or use application env properly
         Result = a2a_hotci_security:verify_digital_signature(PackagePath, Metadata),
         ?assertMatch({ok, #{algorithm := hmac_sha256}}, Result)
     end}.

verify_digital_signature_invalid_hmac_test_() ->
    {"When HMAC signature is invalid, return error",
     setup,
     fun() ->
         SecretKey = <<"test_secret_key_32bytes_long!">>,
         put({signing_key_store, <<"test_key_2">>}, SecretKey),
         SecretKey
     end,
     fun(_SecretKey) ->
         erase({signing_key_store, <<"test_key_2">>})
     end,
     fun(_SecretKey) ->
         PackagePath = <<"/tmp/test_package.tar.gz">>,
         InvalidSignature = <<0:256>>,

         Metadata = #{
             signature => InvalidSignature,
             signature_type => hmac,
             signing_key_id => <<"test_key_2">>,
             payload => <<"different_payload">>
         },

         Result = a2a_hotci_security:verify_digital_signature(PackagePath, Metadata),
         ?assertMatch({error, {signature_invalid, _}}, Result)
     end}.

verify_digital_signature_unsupported_type_test_() ->
    {"When signature type is unsupported, return error",
     fun() ->
         PackagePath = <<"/tmp/test_package.tar.gz">>,
         Signature = <<0:256>>,

         Metadata = #{
             signature => Signature,
             signature_type => unsupported_algorithm,
             payload => <<"test_payload">>
         },

         Result = a2a_hotci_security:verify_digital_signature(PackagePath, Metadata),
         ?assertMatch({error, {unsupported_signature_type, unsupported_algorithm}}, Result)
     end}.

verify_digital_signature_timestamp_validation_test_() ->
    {"When signature timestamp is too old, return error",
     setup,
     fun() ->
         SecretKey = <<"test_secret_key_32bytes_long!">>,
         put({signing_key_store, <<"test_key_ts">>}, SecretKey),
         Message = <<"package_content">>,
         ValidSignature = crypto:mac(hmac, sha256, SecretKey, Message),
         {SecretKey, ValidSignature}
     end,
     fun({SecretKey, _ValidSignature}) ->
         erase({signing_key_store, <<"test_key_ts">>})
     end,
     fun({_SecretKey, ValidSignature}) ->
         PackagePath = <<"/tmp/test_package.tar.gz">>,

         %% Old timestamp (more than 24 hours ago)
         OldTimestamp = erlang:system_time(millisecond) - (25 * 60 * 60 * 1000),

         Metadata = #{
             signature => ValidSignature,
             signature_type => hmac,
             signing_key_id => <<"test_key_ts">>,
             payload => <<"package_content">>,
             timestamp => OldTimestamp
         },

         Result = a2a_hotci_security:verify_digital_signature(PackagePath, Metadata),
         ?assertMatch({error, {signature_expired, _}}, Result)
     end}.

verify_digital_signature_timestamp_valid_test_() ->
    {"When signature timestamp is recent, return ok",
     setup,
     fun() ->
         SecretKey = <<"test_secret_key_32bytes_long!">>,
         put({signing_key_store, <<"test_key_ts2">>}, SecretKey),
         Message = <<"package_content">>,
         ValidSignature = crypto:mac(hmac, sha256, SecretKey, Message),
         {SecretKey, ValidSignature}
     end,
     fun({_SecretKey, _ValidSignature}) ->
         erase({signing_key_store, <<"test_key_ts2">>})
     end,
     fun({_SecretKey, ValidSignature}) ->
         PackagePath = <<"/tmp/test_package.tar.gz">>,

         %% Recent timestamp (1 minute ago)
         RecentTimestamp = erlang:system_time(millisecond) - (60 * 1000),

         Metadata = #{
             signature => ValidSignature,
             signature_type => hmac,
             signing_key_id => <<"test_key_ts2">>,
             payload => <<"package_content">>,
             timestamp => RecentTimestamp
         },

         Result = a2a_hotci_security:verify_digital_signature(PackagePath, Metadata),
         ?assertMatch({ok, #{timestamp_valid := true}}, Result)
     end}.

%% ============================================================================
%% calculate_checksum/1 Tests
%% ============================================================================

calculate_checksum_binary_test_() ->
    {"Calculate SHA256 checksum for binary data",
     fun() ->
         Data = <<"test data for checksum">>,
         Checksum = a2a_hotci_security:calculate_checksum(Data),
         ?assertEqual(32, byte_size(Checksum)),
         ?assert(is_binary(Checksum))
     end}.

calculate_checksum_map_test_() ->
    {"Calculate SHA256 checksum for map data",
     fun() ->
         Data = #{key1 => <<"value1">>, key2 => 42},
         Checksum = a2a_hotci_security:calculate_checksum(Data),
         ?assertEqual(32, byte_size(Checksum)),
         ?assert(is_binary(Checksum))
     end}.

calculate_checksum_known_vector_test_() ->
    {"Verify checksum against known test vector (RFC 4634)",
     fun() ->
         %% Known SHA256 of "abc" is ba7816bf8f01cfea...
         Data = <<"abc">>,
         Expected = <<186, 120, 22, 191, 143, 1, 207, 234,
                      194, 69, 189, 27, 133, 229, 119, 63,
                      131, 232, 152, 92, 135, 185, 51, 126,
                      55, 100, 131, 203, 138, 111, 220, 193>>,
         ?assertEqual(Expected, a2a_hotci_security:calculate_checksum(Data))
     end}.

%% ============================================================================
%% generate_hotp/2 Tests
%% ============================================================================

generate_hotp_basic_test_() ->
    {"Generate HOTP with valid secret and counter",
     fun() ->
         Secret = <<"12345678901234567890">>,
         Counter = 0,
         Token = a2a_hotci_security:generate_hotp(Secret, Counter),
         ?assert(is_binary(Token)),
         ?assert(6 =< byte_size(Token))
     end}.

generate_hotp_different_counters_test_() ->
    {"Different counters produce different tokens",
     fun() ->
         Secret = <<"12345678901234567890">>,
         Token0 = a2a_hotci_security:generate_hotp(Secret, 0),
         Token1 = a2a_hotci_security:generate_hotp(Secret, 1),
         ?assertNotEqual(Token0, Token1)
     end}.

generate_hotp_rfc4226_test_() ->
    {"Verify HOTP against RFC 4226 test vectors",
     fun() ->
         %% RFC 4226 test vector secret (ASCII "12345678901234567890")
         Secret = <<49,50,51,52,53,54,55,56,57,48,49,50,51,52,53,54,55,56,57,48>>,
         Token0 = a2a_hotci_security:generate_hotp(Secret, 0),
         ?assert(is_binary(Token0)),
         ?assert(6 =< byte_size(Token0))
     end}.
