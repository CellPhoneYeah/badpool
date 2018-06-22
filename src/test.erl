-module(test).

-export([
         all/0,
         test1/0,
         check_out/0,
         out_all/0,
         in_one/0,
         get_data/0,
         stop/0
        ]).

-define(CHECK_OUT, check_out_num).

stop() ->
    badpool_server:stop(mypool).

all() ->
    badpool_server:workers(mypool).

test() ->
    io:format("checkout~n"),
    Pid = badpool_server:check_out(mypool),
    io:format("get pid ~n"),
    receive
        ok ->
            badpool_server:check_in(mypool, Pid),
            check_in(self())
    end.

test1() ->
    out_all(),
    check_out().

out_all() ->
    [check_out() || _ <- lists:seq(1, 10)].

check_out() ->
    Data = get_data(),
    Pid = spawn(fun() -> test() end),
    set_data(queue:in(Pid, Data)).

in_one() ->
    Data = get_data(),
    case queue:out(Data) of
        {{value, Pid}, NewData} ->
                Pid ! ok,
                set_data(NewData);
        _ ->
            ok
    end.

check_in(Pid) ->
    F = fun(P) when P =:= Pid ->
                false;
           (_) ->
                true
        end,
    Data = get_data(),
    set_data(queue:filter(F, Data)).

get_data() ->
    case erlang:get(?CHECK_OUT) of
        undefined ->
            queue:new();
        Data ->
            Data
    end.

set_data(L) ->
    erlang:put(?CHECK_OUT, L).
