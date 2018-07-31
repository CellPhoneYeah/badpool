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
         start_link/2, %% 开始进程池
         workers/1, %% 所有工作进程
         check_in/2, %% 回收一条工作进程
         check_out/1, %% 获取一条工作进程
         stop/1 %% 停止进程池
        ]).


-define(MAX_PROCESS_NUM, 10).

-record(state, {
          name = mypool,
          max_process_num = ?MAX_PROCESS_NUM, %% 最大进程数量
          call_back_mod, %% 回调模块
          worker_opts = [], %% 工作进程的启动参数
          sup_pid,  %% 监视进程pid
          waiting, %% 等待中的使用者
          monitors   %% 正在使用工作进程的进程监控，如果进程使用者死了，则回收进程
         }).

-define(ETS_BADPOOL, ets_badpool).
-define(IDLE, 0). %% 空闲
-define(BUSY, 1). %% 忙碌

-define(TIMEOUT, 5000). %% 请求工作进程超时时间
-define(PROCESS_NAME, process_name).

-define(ETS_MONITORS, monitors).

-record(check_outed,
        {pid = undefined, % 工作进程id
         from = undefined, % 使用的进程信息
         monitor = undefined %% 监控进程
        }). 

-record(wait,
        {
         from = undefined, % 等待进程信息
         monitor = undefined % 监控进程
        }).

%%% ===========================
%%% API
%%% ===========================
start_link(SupOpts, WorkerOpts) ->
    case proplists:get_value(name, SupOpts) of
        undefined ->
            throw({error, not_set_name}); %% 抛出异常，让启动失败
        Name ->
            gen_server:start_link({local, Name}, ?MODULE, {SupOpts, WorkerOpts}, [])
    end.

check_out(Name) ->
    try
        gen_server:call(Name, {check_out}, ?TIMEOUT)
    catch
        Class:Reason ->
            io:format("cancel wait ~p~n", [self()]),
            gen_server:cast(Name, {cancel_wait, self()}),
            erlang:raise(Class, Reason, erlang:get_stacktrace())
    end.

check_in(Name, Pid) ->
    gen_server:cast(Name, {check_in, Pid}).

workers(Name) ->
    ets:lookup_element(?ETS_BADPOOL, {workers, Name}, 2).

stop(Name) ->
    gen_server:stop(Name).

%%% ============================
%%% callback
%%% ============================
init({SupOpts, WorkerOpts}) ->
    process_flag(trap_exit, true),
    Monitor = ets:new(?ETS_MONITORS, [private]),
    Name = proplists:get_value(name, SupOpts),
    Waiting = queue:new(),
    ?ETS_BADPOOL = ets:new(?ETS_BADPOOL, [public, set, named_table]),
    init(SupOpts, #state{name = Name, monitors = Monitor, waiting = Waiting, worker_opts = WorkerOpts}).

handle_call({check_out}, {FromPid, _} = From, State) ->
    #state{name = Name, monitors = Monitors, waiting = Waiting} = State,
    Monitor = monitor(process, FromPid),
    case workers(Name) of
        [] ->
            NewWaiting = queue:in({From, Monitor}, Waiting),
            {noreply, State#state{waiting = NewWaiting}};
        [Pid | Left] ->
            ets:insert(?ETS_BADPOOL, {{workers, Name}, Left}),
            {reply, Pid, State#state{monitors = [{Pid, From, Monitor} | Monitors]}}
    end;
handle_call(_Request, _From, State) ->
    io:format("request ~p, from ~p~n", [_Request, _From]),
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

terminate(_Reason, State) ->
    #state{name = Name, monitors = Monitors, waiting = Waiting} = State,
    Workers = workers(Name),
    stop_wait(Waiting),
    [exit(Pid) || {Pid, _} <- Workers],
    [exit(MPid) || {MPid, _, _} <- Monitors],
    ok.

code_change(_Ovsn, State, _Extra) ->
    {ok, State}.

%%% ============================
%%% internal
%%% ============================
add_worker(Pid, State) ->
    #state{name = Name, waiting = Waiting, monitors = Monitors} = State,
    case queue:out(Waiting) of
        {{value, #wait{from = From, monitor = WaitMonitor}}, Left} ->
            NewCheckout = #check_outed{pid = Pid, from = From, monitor = WaitMonitor},
            gen_server:reply(From, Pid),
            {ok, State#state{waiting = Left, monitors = [NewCheckout | Monitors]}};
        {empty, _} ->
            Workers = workers(Name),
            ets:insert(?ETS_BADPOOL, {{workers, Name}, [Pid | Workers]}),
            {ok, State}
    end.

do_handle_cast({check_in, Pid}, State) ->
    #state{monitors = Monitors} = State,
    case lists:keytake(Pid, 1, Monitors) of
        {value, #check_outed{pid = Pid, monitor = Monitor}, LeftMonitors} ->
            demonitor(Monitor),
            add_worker(Pid, State#state{monitors = LeftMonitors});
        false ->
            io:format("not find monitor~n"),
            {ok, State}
    end;

do_handle_cast({cancel_wait, FromPid}, State) ->
    #state{waiting = Waiting} = State,
    F = fun(#wait{from = {FPid, _}, monitor = Monitor}) when FromPid =:= FPid ->
                demonitor(Monitor),
                false;
           (_) ->
                true
        end,
    NewWaiting = queue:filter(F, Waiting),
    io:format("new waiting ~p~n", [NewWaiting]),
    {ok, State#state{waiting = NewWaiting}};
do_handle_cast(_Request, State) ->
    {ok, State}.

% link的进程死掉，也就是工作进程死了，需要重新开一个新的工作进程
do_handle_info({'EXIT', {Pid, _} = From, Reason}, State) ->
    #state{monitors = Monitors, sup_pid = SupPid} = State,
    case lists:keytake(From, #check_outed.pid, Monitors) of
        {value, #check_outed{pid = Pid, monitor = Monitor}, LeftMonitors} ->
            demonitor(Monitor),
            {ok, NewWorkerPid} = supervisor:start_link(SupPid, []),
            add_worker(NewWorkerPid, State#state{monitors = LeftMonitors});
        {empty, _} ->
            io:format("a worker down pid ~w reason ~w~n", [Pid, Reason])
    end;
% monitor的进程死掉，也就是调用工作进程的调用进程死了
do_handle_info({'DOWN', From, Reason}, State) ->
    {ok, NewState} = do_check_in(From, State),
    io:format("a caller down from ~w reason ~w~n", [From, Reason]),
    {ok, NewState};
do_handle_info(_Request, State) ->
    {ok, State}.


do_check_in(Pid, State) when is_pid(Pid) ->
    #state{monitors = Monitors} = State,
    case lists:keytake(Pid, 1, Monitors) of
        {value, {Pid, _From, Monitor}, LeftMonitors} ->
            demonitor(Monitor),
            add_worker(Pid, State#state{monitors = LeftMonitors});
        false ->
            io:format("not find monitor"),
            {ok, State}
    end;
do_check_in(From, State) ->
    #state{monitors = Monitors} = State,
    case lists:keytake(From, #check_outed.from, Monitors) of
        {value, #check_outed{pid = Pid}, _LeftMonitors} ->
            do_check_in(Pid, State);
        false ->
            ok
    end.

start_workers(SupPid, ProcessNum) ->
    start_workers(SupPid, ProcessNum, []).

start_workers(_SupPid, 0, Workers) ->
    Workers;
start_workers(SupPid, ProcessNum, Workers) ->
    {ok, Pid} = supervisor:start_child(SupPid, []),
    true = link(Pid),
    start_workers(SupPid, ProcessNum - 1, [Pid | Workers]).

init([{call_back_mod, Mod} | Left], State) ->
    init(Left, State#state{call_back_mod = Mod});
init([{max_process_num, MaxProcessNum} | Left], State) ->
    init(Left, State#state{max_process_num = MaxProcessNum});
init([_Other | Left], State) ->
    init(Left, State);
init([], State = #state{name =Name, call_back_mod = CallBackMod, max_process_num = MaxProcessNum, worker_opts = WorkerOpts})
  when CallBackMod /= undefined andalso MaxProcessNum > 0 ->
    {ok, SupPid} = badpool_sup:start_link(CallBackMod, WorkerOpts),
    Workers = start_workers(SupPid, MaxProcessNum),
    ets:insert(?ETS_BADPOOL, {{workers, Name}, Workers}),
    NewState = State#state{sup_pid = SupPid},
    {ok, NewState}.

stop_wait(empty) ->
    ok;
stop_wait(Waiting) ->
    case queue:out(Waiting) of
        {{value, {_, Monitor}}, Left} ->
            demonitor(Monitor),
            stop_wait(Left);
        _ ->
            ok
    end.
