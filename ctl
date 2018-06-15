function start {
    local CMD="erl -pa ebin -I include -s badpool_entrance start"
    bash -C ${CMD}
}

case $1 in
    start)
        start;;
    *)
        echo"ok"
esac
