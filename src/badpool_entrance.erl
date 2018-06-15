-module(badpool_entrance).

-export([
         start/0
        ]).

start() ->
    case application:start(badpool) of
        ok ->
            io:format("app start~n");
        Other ->
            io:format("Other ~p~n", [Other])
    end.
