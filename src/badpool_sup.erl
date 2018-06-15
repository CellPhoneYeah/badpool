-module(badpool_sup).

-behaviour(supervisor).

-export([
         start_link/2,
         init/1
        ]).

start_link(CallBackMod, Args) ->
    supervisor:start_link(?MODULE, [CallBackMod, Args]).

init([CallBackMod, Args]) ->
    SupFlag = #{
      strategy => simple_one_for_one,
      infinity => 10,
      period => 10
     },
    ChildSpec = #{
      id => CallBackMod,
      start => {CallBackMod, start_link, [Args]},
      restart => temperary,
      shutdown => 5000,
      type => worker,
      modules => [CallBackMod]
     },
    {ok, {SupFlag, ChildSpec}}.
