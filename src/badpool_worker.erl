-module(badpool_worker).

%% 进程池进程需要实现的回调方法
-callback start_link(WorkerArgs) -> {ok, Pid} | {error, Reason} when
      WorkerArgs :: proplists:proplist(),
      Pid :: pid(),
      Reason :: atom().
