-module(window_ffi).
-export([new/0, check/5, decrement/4, reset/2, cleanup/2, size/1]).

new() ->
    ets:new(glimit_window, [set, public, {write_concurrency, true}]).

check(Table, Key, MaxCount, WindowSecs, Now) ->
    WindowId = Now div WindowSecs,
    FullKey = {window, Key, WindowSecs, WindowId},
    RetryAfter = WindowSecs - (Now rem WindowSecs),
    Count = try ets:update_counter(Table, FullKey, {2, 1})
            catch error:badarg ->
                ets:insert_new(Table, {FullKey, 0}),
                %% Key could be deleted between insert and update (by reset
                %% or cleanup). Treat as a fresh entry if that happens.
                try ets:update_counter(Table, FullKey, {2, 1})
                catch error:badarg -> 1
                end
            end,
    case Count =< MaxCount of
        true  -> {ok, Count};
        false -> {error, RetryAfter}
    end.

%% Decrement the counter for a window by 1 (used for rollback on denial).
decrement(Table, Key, WindowSecs, Now) ->
    WindowId = Now div WindowSecs,
    FullKey = {window, Key, WindowSecs, WindowId},
    try ets:update_counter(Table, FullKey, {2, -1})
    catch error:badarg -> 0
    end,
    nil.

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
    %% Guard: (WindowId + 1) * WindowSecs < Now
    %% A window with WindowId=1 and WindowSecs=60 covers seconds 60-119,
    %% so its end is (1+1)*60 = 120. Expired when Now > 119, i.e. Now >= 120.
    ets:select_delete(Table, [
        {{{window, '_', '$1', '$2'}, '_'},
         [{'<', {'*', {'+', '$2', 1}, '$1'}, Now}],
         [true]}
    ]),
    nil.

size(Table) ->
    ets:info(Table, size).
