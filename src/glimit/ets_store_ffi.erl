-module(ets_store_ffi).
-export([new/0, get/2, set/3, delete/2, sweep/2, size/1, set_interval/2]).

new() ->
    ets:new(glimit_ets, [set, public, {write_concurrency, true}, {read_concurrency, true}]).

get(Table, Key) ->
    case ets:lookup(Table, Key) of
        [{_, Value}] -> {ok, Value};
        [] -> {error, nil}
    end.

set(Table, Key, Value) ->
    ets:insert(Table, {Key, Value}),
    {ok, nil}.

delete(Table, Key) ->
    ets:delete(Table, Key),
    {ok, nil}.

sweep(Table, Fun) ->
    ets:foldl(fun({Key, Value}, Acc) ->
        case Fun(Key, Value) of
            true -> ets:delete(Table, Key), Acc + 1;
            false -> Acc
        end
    end, 0, Table).

size(Table) ->
    ets:info(Table, size).

set_interval(IntervalMs, Fun) ->
    {ok, _TRef} = timer:apply_interval(IntervalMs, erlang, apply, [Fun, []]),
    nil.
