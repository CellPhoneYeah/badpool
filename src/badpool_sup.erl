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
      intensity => 0,
      period => 1
     },
    ChildSpec = #{
      id => CallBackMod,
      start => {CallBackMod, start_link, [Args]},
      restart => temporary,
      shutdown => 5000,
      type => worker,
      modules => [CallBackMod]
     },
    {ok, {SupFlag, [ChildSpec]}}.
