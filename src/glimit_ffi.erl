-module(glimit_ffi).
-export([rescue/1]).

rescue(Fun) ->
    try
        {ok, Fun()}
    catch
        _:_:_ -> {error, nil}
    end.
