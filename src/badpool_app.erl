-module(badpool_app).

-behaviour(application).

-export([
         start/2,
         stop/1
        ]).

start(_, _) ->
    io:format("start server"),
    SupOpts = [
               {name, mypool},
               {call_back_mod, test_worker}
              ],
    WorkerOpts = [],
    badpool_server:start_link(SupOpts, WorkerOpts).

stop(_) ->
    ok.
