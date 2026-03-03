-module(glimit_ffi).
-export([monotonic_now_ms/0]).

monotonic_now_ms() ->
    erlang:monotonic_time(millisecond).
