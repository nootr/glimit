-module(redis_store_ffi).
-export([put_token/2, take_token/1]).

%% The lock token of a key is kept in the process dictionary, because glimit
%% calls `lock_and_get` and `set_and_unlock` for a bucket from the same process.

put_token(Key, Token) ->
    erlang:put({redis_store_lock, Key}, Token),
    nil.

take_token(Key) ->
    case erlang:erase({redis_store_lock, Key}) of
        undefined -> {error, nil};
        Token -> {ok, Token}
    end.
