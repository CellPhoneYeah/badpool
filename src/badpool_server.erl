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
         start_link/2,
         workers/1,
         check_in/2,
         check_out/1,
         stop/1
        ]).


-define(MAX_PROCESS_NUM, 10).

-record(state, {
          name = {local, badpool_server},
          max_process_num = ?MAX_PROCESS_NUM, %% 最大进程数量
          call_back_mod, %% 回调模块
          worker_opts = [], %% 工作进程的启动参数
          sup_pid,  %% 监视进程pid
          workers = [], %% 所有工作进程
          waiting, %% 等待中的使用者
          monitors   %% 正在使用工作进程的进程监控，如果进程使用者死了，则回收进程
         }).

-define(ETS_BADPOOL, ets_badpool).
-define(IDLE, 0). %% 空闲
-define(BUSY, 1). %% 忙碌

-define(TIMEOUT, 5000). %% 请求工作进程超时时间
%%% ===========================
%%% API
%%% ===========================
start_link(SupOpts, WorkerOpts) ->
    case proplists:get_value(name, SupOpts) of
        undefined ->
            not_set_name;
        Name ->
            gen_server:start_link(Name, ?MODULE, {SupOpts, WorkerOpts}, [])
    end.

check_out(Name) ->
    try
        gen_server:call(Name, {check_out}, ?TIMEOUT)
    catch
        Class:Reason ->
            gen_server:cast(Name, {cancel_wait, self()}),
            erlang:raise(Class, Reason, erlang:get_stacktrace())
    end.

check_in(Name, Pid) ->
    gen_server:cast(Name, {check_in, Pid}).

workers(Name) ->
    ets:lookup_element(?ETS_BADPOOL, {all_workers, Name}, 2).

stop(Name) ->
    gen_server:terminate(Name).

%%% ============================
%%% callback
%%% ============================
init({SupOpts, WorkerOpts}) ->
    process_flag(trap_exit, true),
    Monitor = ets:new(monitors, [private]),
    Waiting = queue:new(),
    ets:new(ets_badpool, [public, set, named_table]),
    init(SupOpts, #state{monitors = Monitor, waiting = Waiting, worker_opts = WorkerOpts}).

handle_call({check_out, Name}, {FromPid, _}, State) ->
    #state{monitors = Monitors, waiting = Waiting} = State,
    case ets:lookup_element(?ETS_BADPOOL, {workers, Name}) of
        [] ->
            NewWaiting = [FromPid | Waiting],
            {noreply, State#state{waiting = NewWaiting}};
        [Pid | _Left] ->
            Monitor = erlang:monitor(process, FromPid),
            ets:delete(?ETS_BADPOOL, Pid),
            {reply, Pid, State#state{monitors = [Monitor | Monitors]}}
    end;
handle_call(_Request, _From, State) ->
    {reply, bad_request, State}.

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
do_handle_cast({check_in, Pid}, State) ->
    #state{waiting = Waiting, name = Name} = State,
    case queue:out(Waiting) of
        {{value, WaitPid}, Left} ->
            gen_server:reply(WaitPid, Pid),
            {ok, State#state{waiting = Left}};
        {empty, _} ->
            ets:insert(ets_badpool, {workers, Name})
    end;
do_handle_cast({cancel_wait, Pid}, State) ->
    #state{waiting = Waiting} = State,
    case queue:out(Waiting) of
        {{value, Pid}, Left} ->
            {ok, State#state{waiting = Left}};
        {empty, _} ->
            {ok, State}
    end;
do_handle_cast(_Request, State) ->
    {ok, State}.

do_handle_info(_Request, State) ->
    {ok, State}.

start_workers(SupPid, ProcessNum) ->
    start_workers(SupPid, ProcessNum, []).

start_workers(_SupPid, 0, Workers) ->
    Workers;
start_workers(SupPid, ProcessNum, Workers) ->
    {ok, Pid} = supervisor:start_child(SupPid, []),
    true = link(Pid),
    start_workers(SupPid, ProcessNum - 1, [{Pid, ?IDLE} | Workers]).



init([{name, Name} | Left], State) ->
    init(Left, State#state{name = Name});
init([{call_back_mod, Mod} | Left], State) ->
    init(Left, State#state{call_back_mod = Mod});
init([{max_process_num, MaxProcessNum} | Left], State) ->
    init(Left, State#state{max_process_num = MaxProcessNum});
init([_Other | Left], State) ->
    init(Left, State);
init([], State = #state{name = Name, call_back_mod = CallBackMod, max_process_num = MaxProcessNum, worker_opts = WorkerOpts})
  when CallBackMod /= undefined andalso MaxProcessNum > 0 ->
    {ok, SupPid} = badpool_sup:start_link(CallBackMod, WorkerOpts),
    Workers = start_workers(SupPid, MaxProcessNum),
    ets:insert(ets_badpool, {{workers, Name}, Workers}),
    NewState = State#state{sup_pid = SupPid},
    {ok, NewState}.

