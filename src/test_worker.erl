-module(test_worker).

-behaviour(badpool_worker).
-behaviour(gen_server).

-export([
         start_link/1
        ]).

-export([
         init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3
        ]).

start_link(WorkerOpts) ->
    gen_server:start_link(?MODULE, [WorkerOpts], []).

init(WorkerOpts) ->
    io:format("start a woker ~p ~n", [WorkerOpts]),
    {ok, {}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(_Request, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.
