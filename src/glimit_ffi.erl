-module(glimit_ffi).
-export([rescue/1, monotonic_now_ms/0]).

rescue(Fun) ->
    try
        {ok, Fun()}
    catch
        _:_:_ -> {error, nil}
    end.

monotonic_now_ms() ->
    erlang:monotonic_time(millisecond).
