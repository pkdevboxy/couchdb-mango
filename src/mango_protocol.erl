
-module(mango_protocol).

-behavior(gen_server).
-behavior(ranch_protocol).

-export([
    start_link/4
]).

-export([
    init/1,
    init/4,
    terminate/2,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    code_change/3
]).


-record(st, {
    socket,
    transport,
    buffer = <<>>,
    errors = []
}).


start_link(Ref, Socket, Transport, Opts) ->
    proc_lib:start_link(?MODULE, init, [Ref, Socket, Transport, Opts]).


% This function only exists to satiate the
% gen_server behavior checks.
init(_) ->
    {ok, ignored}.


init(Ref, Socket, Transport, Opts) ->
    ok = proc_lib:init_ack({ok, self()}),
    ok = ranch:accept_ack(Ref),
    St = #st{
        socket = Socket,
        transport = Transport
    },
    set_active(St),
    gen_server:enter_loop(?MODULE, [], St).


handle_call(Msg, _From, St) ->
    {error, {invalid_call, Msg}, {invalid_call, Msg}, St}.


handle_cast(Msg, St) ->
    {error, {invalid_cast, Msg}, St}.


handle_info({tcp, Socket, Data}, St) ->
    set_active(St),
    NewBuffer = <<(St#st.buffer)/binary, Data/binary>>,
    case mango_msg:new(NewBuffer) of
        undefined ->
            {noreply, St#st{buffer=NewBuffer}};
        {error, Reason} ->
            {noreply, add_error(Reason, St)};
        {Msg, Rest} ->
            dispatch(Msg, St#st{buffer=Rest})
    end;
handle_info({tcp_closed, _Socket}, State) ->
    {stop, normal, State};
handle_info({tcp_error, _, Reason}, State) ->
    {stop, Reason, State};
handle_info(timeout, State) ->
    {stop, normal, State};
handle_info(Msg, St) ->
    {error, {invalid_info, Msg}, St}.


code_change(_OldVSn, St, _Extra) ->
    {ok, St}.


dispatch({Type, Props}, St) ->
    case mango_handler:Type(Props) of
        ok ->
            {noreply, St};
        {ok, Resp} ->
            {noreply, send_resp(Resp, St)};
        Error ->
            {noreply, add_error(Error, St)}
    end.


set_active(#st{socket=S, transport=T}) ->
    ok = T:setopts(S, [{active, once}]).


send_resp(_Resp, St) ->
    St.


add_error(Error, #st{errors=Errors}=St) ->
    St#st{errors = [Error | Errors]}.