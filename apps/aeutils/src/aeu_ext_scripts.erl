-module(aeu_ext_scripts).

-export([ parse_opts/2
        , connect_node/1 ]).

parse_opts(Args, #{arguments := Args0} = Spec0) ->
    Spec = Spec0#{arguments => Args0 ++ node_arguments()},
    try parse_opts_(Args, Spec)
    catch
        error:{argparse, Error} ->
            usage(Error, Spec);
        error:{?MODULE, _} = Error ->
            usage(Error, Spec)
    end.

parse_opts_(Args, Spec) ->
    Opts = argparse:parse(Args, Spec, #{progname => escript:script_name()}),
    NodeKeys = ['$cookie','$sname','$name'],
    ConnOpts = maps:with(NodeKeys, Opts),
    UserOpts = maps:without(NodeKeys, Opts),
    #{ opts => UserOpts
     , connect => check_conn_opts(ConnOpts) }.

usage(Error, Spec) ->
    io:fwrite(standard_error, format_error(Spec, Error), []),
    argparse:help(Spec),
    halt(1).

node_arguments() ->
    Arg = #{ required => false, type => string, nargs => 1 },
    [
      Arg#{ name  => '$cookie', long => "setcookie", required => true }
    , Arg#{ name  => '$sname' , long => "sname"     }
    , Arg#{ name  => '$name'  , long => "name"      }
    ].

check_conn_opts(#{'$cookie' := [Cookie]} = Opts) ->
    {Name, Mode} = name_and_mode(Opts),
    #{ cookie => Cookie
     , name => my_name(Name)
     , mode => Mode
     , target_node => nodename(Name) }.

name_and_mode(Opts) ->
    case Opts of
        #{'$name' := _, '$sname' := _} ->
            error({?MODULE, both_sname_and_name});
        #{'$name' := [Name] } ->
            {Name, longnames};
        #{'$sname' := [Name]} ->
            {Name, shortnames};
        _ ->
            error({?MODULE, no_name_or_sname})
    end.


connect_node(#{connect := #{name := Name, mode := Mode, cookie := Cookie,
                            target_node := TargetNode}}) ->
    {ok, _} = net_kernel:start([Name, Mode]),
    erlang:set_cookie(node(), list_to_atom(Cookie)),
    connect_and_ping(TargetNode).

my_name(Name) ->
    ScriptName = escript:script_name(),
    append_node_suffix(Name, "_" ++ filename:basename(ScriptName)).

connect_and_ping(Node) ->
    NotResp = fun() ->
                      io:fwrite(standard_error, "Node ~p not responding", [Node]),
                      halt(1)
              end,
    case net_kernel:hidden_connect_node(Node) of
        true ->
            case net_adm:ping(Node) of
                pong ->
                    {ok, Node};
                pang ->
                    NotResp()
            end;
        false ->
            NotResp()
    end.

format_error(_Spec, {?MODULE, no_name_or_sname}) ->
    "Either -sname or -name option required~n";
format_error(_Spec, {?MODULE, both_sname_and_name}) ->
    "Cannot have both -sname and -name~n";
format_error(Spec, Error) ->
    argparse:format_error(Error).

append_node_suffix(Name, Suffix) ->
    case re:split(Name, "@", [{return, list}, unicode]) of
        [Node, Host] ->
            list_to_atom(lists:concat([Node, Suffix, os:getpid(), "@", Host]));
        [Node] ->
            list_to_atom(lists:concat([Node, Suffix, os:getpid()]))
    end.

nodename(Name) ->
    case re:split(Name, "@", [{return, list}, unicode]) of
        [_Node, _Host] ->
            list_to_atom(Name);
        [Node] ->
            [_, Host] = re:split(atom_to_list(node()), "@", [{return, list}, unicode]),
            list_to_atom(lists:concat([Node, "@", Host]))
    end.
