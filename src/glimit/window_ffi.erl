-module(window_ffi).
-export([new/0, check/5, reset/2, cleanup/2, size/1]).

new() ->
    ets:new(glimit_window, [set, public, {write_concurrency, true}]).

check(Table, Key, MaxCount, WindowSecs, Now) ->
    WindowId = Now div WindowSecs,
    FullKey = {window, Key, WindowSecs, WindowId},
    RetryAfter = WindowSecs - (Now rem WindowSecs),
    Count = try ets:update_counter(Table, FullKey, {2, 1})
            catch error:badarg ->
                ets:insert_new(Table, {FullKey, 0}),
                ets:update_counter(Table, FullKey, {2, 1})
            end,
    case Count =< MaxCount of
        true  -> {ok, Count};
        false -> {error, RetryAfter}
    end.

reset(Table, Key) ->
    %% Delete all entries matching this key across all window sizes/ids.
    ets:select_delete(Table, [
        {{{window, Key, '_', '_'}, '_'},
         [],
         [true]}
    ]),
    nil.

cleanup(Table, Now) ->
    %% Delete entries whose window has fully elapsed.
    ets:select_delete(Table, [
        {{{window, '_', '$1', '$2'}, '_'},
         [{'<', {'*', {'+', '$2', 1}, '$1'}, Now}],
         [true]}
    ]),
    nil.

size(Table) ->
    ets:info(Table, size).
