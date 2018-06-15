-module(badpool_server).

-behaviour(gen_server).

-export([
         init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3
        ]).

-export([
         start_link/2
        ]).

-define(MAX_PROCESS_NUM, 10).

-record(state, {
          name = badpool_server,
          max_process_num = ?MAX_PROCESS_NUM, %% 最大进程数量
          idle_workers = [], %% 空闲的工作进程列表
          bussy_workers = [], %% 工作中的工作进程列表
          call_back_mod, %% 回调模块
          worker_opts = [], %% 工作进程的启动参数
          sup_pid,  %% 监视进程pid
          all_workers = [] %% 所有工作进程的pid列表
         }).

start_link(SupOpts, WorkerOpts) ->
    start(SupOpts, #state{worker_opts = WorkerOpts}).

start([{name, Name} | Left], State) ->
    start(Left, State#state{name = Name});
start([{max_process_num, MaxProcessNum} | Left], State) when MaxProcessNum > 0 ->
    start(Left, State#state{max_process_num = MaxProcessNum});
start([{call_back_mod, CallBackMod} | Left], State) ->
    start(Left, State#state{call_back_mod = CallBackMod});
start([], State = #state{call_back_mod = CallBackMod, max_process_num = MaxProcessNum, worker_opts = WorkerOpts})
  when CallBackMod /= undefined andalso MaxProcessNum > 0 ->
    {ok, SupPid} = badpool_sup:start_link(CallBackMod, WorkerOpts),
    Workers = start_workers(SupPid, MaxProcessNum, WorkerOpts),
    NewState = State#state{sup_pid = SupPid, all_workers = Workers, idle_workers = Workers},
    gen_server:start_link({local, ?MODULE}, ?MODULE, [NewState], []).

%%% ============================
%%% callback
%%% ============================
init(State) ->
    {ok, State}.

handle_call(Request, _From, State) ->
    case catch do_handle_call(Request, State) of
        {ok, Reply, NewState} ->
            {reply, Reply, NewState};
        _Other ->
            {reply, error, State}
    end.

handle_cast(Request, State) ->
    case catch do_handle_cast(Request, State) of
        {ok, NewState} ->
            {noreply, NewState};
        _Other ->
            {noreply, State}
    end.

handle_info(Request, State) ->
    case catch do_handle_info(Request, State) of
        {ok, NewState} ->
            {noreply, NewState};
        _Other ->
            {noreply, State}
    end.

terminate(_Reason, _State) ->
    ok.

code_change(_Ovsn, State, _Extra) ->
    {ok, State}.

%%% ============================
%%% internal
%%% ============================
do_handle_call(_Request, State) ->
    {ok, ok, State}.

do_handle_cast(_Request, State) ->
    {ok, State}.

do_handle_info(_Request, State) ->
    {ok, State}.

start_workers(SupPid, ProcessNum, WorkerOpts) ->
    start_workers(SupPid, ProcessNum, WorkerOpts, []).

start_workers(_SupPid, 0, _WorkerOpts, Workers) ->
    Workers;
start_workers(SupPid, ProcessNum, WorkerOpts, Workers) ->
    {ok, Pid} = supervisor:start_child(SupPid, WorkerOpts),
    start_workers(SupPid, ProcessNum - 1, [Pid | Workers]).
