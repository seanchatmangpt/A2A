%%%-------------------------------------------------------------------
%%% @doc BeamAI main facade module.
%%% Provides the primary API for interacting with the BeamAI framework.
%%% This module delegates to the kernel, tool, filter, and LLM
%%% subsystems, presenting a unified interface.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai).

-export([
    %% Kernel management
    kernel/0,
    kernel/1,
    %% Tool management
    tool/2,
    tool/3,
    add_tool/2,
    add_tools/2,
    add_tool_module/2,
    %% LLM management
    add_llm/2,
    add_llm/3,
    %% Filter management
    add_filter/2,
    add_filter/4,
    %% Invocation
    invoke_tool/4,
    %% Chat
    chat/2,
    chat/3,
    chat_with_tools/2,
    chat_with_tools/3,
    %% Rendering
    render/2,
    %% Query
    tools/1,
    tools/2,
    tools_by_tag/2,
    %% Context
    context/0,
    context/1
]).

-type kernel_ref() :: pid() | atom().
-type tool_name() :: binary() | atom().
-type tool_def() :: map().
-type llm_provider() :: atom().
-type llm_opts() :: map() | proplists:proplist().
-type filter_fun() :: fun((map()) -> map()).
-type filter_stage() :: pre_invoke | post_invoke | pre_chat | post_chat.
-type chat_message() :: binary() | map().
-type chat_opts() :: map().
-type context() :: map().

-export_type([
    kernel_ref/0, tool_name/0, tool_def/0, llm_provider/0,
    llm_opts/0, filter_fun/0, filter_stage/0, chat_message/0,
    chat_opts/0, context/0
]).

%%====================================================================
%% Kernel management
%%====================================================================

%% @doc Get the default kernel process reference.
-spec kernel() -> kernel_ref().
kernel() ->
    beamai_kernel:default().

%% @doc Get or create a named kernel instance.
-spec kernel(atom()) -> kernel_ref().
kernel(Name) ->
    beamai_kernel:get_or_create(Name).

%%====================================================================
%% Tool management
%%====================================================================

%% @doc Define a tool with a name and function.
-spec tool(tool_name(), fun()) -> tool_def().
tool(Name, Fun) ->
    beamai_tool:new(Name, Fun).

%% @doc Define a tool with a name, function, and options/metadata.
-spec tool(tool_name(), fun(), map()) -> tool_def().
tool(Name, Fun, Opts) ->
    beamai_tool:new(Name, Fun, Opts).

%% @doc Add a tool definition to a kernel.
-spec add_tool(kernel_ref(), tool_def()) -> ok.
add_tool(KernelRef, ToolDef) ->
    beamai_kernel:add_tool(KernelRef, ToolDef).

%% @doc Add multiple tool definitions to a kernel.
-spec add_tools(kernel_ref(), [tool_def()]) -> ok.
add_tools(KernelRef, ToolDefs) ->
    beamai_kernel:add_tools(KernelRef, ToolDefs).

%% @doc Add all tools exported from a module to a kernel.
%% The module must export a beamai_tools/0 function returning a list of tool defs.
-spec add_tool_module(kernel_ref(), module()) -> ok.
add_tool_module(KernelRef, Module) ->
    Tools = Module:beamai_tools(),
    beamai_kernel:add_tools(KernelRef, Tools).

%%====================================================================
%% LLM management
%%====================================================================

%% @doc Add an LLM provider to the kernel with default options.
-spec add_llm(kernel_ref(), llm_provider()) -> ok.
add_llm(KernelRef, Provider) ->
    add_llm(KernelRef, Provider, #{}).

%% @doc Add an LLM provider to the kernel with specific options.
-spec add_llm(kernel_ref(), llm_provider(), llm_opts()) -> ok.
add_llm(KernelRef, Provider, Opts) ->
    beamai_kernel:add_llm(KernelRef, Provider, Opts).

%%====================================================================
%% Filter management
%%====================================================================

%% @doc Add a filter function that applies to all stages.
-spec add_filter(kernel_ref(), filter_fun()) -> ok.
add_filter(KernelRef, FilterFun) ->
    beamai_kernel:add_filter(KernelRef, FilterFun).

%% @doc Add a filter function for a specific stage with a name and priority.
-spec add_filter(kernel_ref(), filter_stage(), binary(), filter_fun()) -> ok.
add_filter(KernelRef, Stage, Name, FilterFun) ->
    beamai_kernel:add_filter(KernelRef, Stage, Name, FilterFun).

%%====================================================================
%% Invocation
%%====================================================================

%% @doc Invoke a named tool on a kernel with arguments and context.
-spec invoke_tool(kernel_ref(), tool_name(), map(), context()) ->
    {ok, term()} | {error, term()}.
invoke_tool(KernelRef, ToolName, Args, Context) ->
    beamai_kernel:invoke_tool(KernelRef, ToolName, Args, Context).

%%====================================================================
%% Chat
%%====================================================================

%% @doc Send a chat message to the default LLM on the kernel.
-spec chat(kernel_ref(), chat_message()) -> {ok, binary()} | {error, term()}.
chat(KernelRef, Message) ->
    chat(KernelRef, Message, #{}).

%% @doc Send a chat message with options (model, temperature, etc.).
-spec chat(kernel_ref(), chat_message(), chat_opts()) ->
    {ok, binary()} | {error, term()}.
chat(KernelRef, Message, Opts) ->
    beamai_kernel:chat(KernelRef, Message, Opts).

%% @doc Send a chat message and allow the LLM to use registered tools.
-spec chat_with_tools(kernel_ref(), chat_message()) ->
    {ok, binary()} | {error, term()}.
chat_with_tools(KernelRef, Message) ->
    chat_with_tools(KernelRef, Message, #{}).

%% @doc Send a chat message with tool use and options.
-spec chat_with_tools(kernel_ref(), chat_message(), chat_opts()) ->
    {ok, binary()} | {error, term()}.
chat_with_tools(KernelRef, Message, Opts) ->
    beamai_kernel:chat_with_tools(KernelRef, Message, Opts).

%%====================================================================
%% Rendering
%%====================================================================

%% @doc Render a template with the given bindings.
-spec render(binary(), map()) -> binary().
render(Template, Bindings) ->
    beamai_template:render(Template, Bindings).

%%====================================================================
%% Query
%%====================================================================

%% @doc List all tools registered in a kernel.
-spec tools(kernel_ref()) -> [tool_def()].
tools(KernelRef) ->
    beamai_kernel:list_tools(KernelRef).

%% @doc List tools matching the given filter criteria.
-spec tools(kernel_ref(), map()) -> [tool_def()].
tools(KernelRef, Filter) ->
    beamai_kernel:list_tools(KernelRef, Filter).

%% @doc List tools matching a specific tag.
-spec tools_by_tag(kernel_ref(), binary()) -> [tool_def()].
tools_by_tag(KernelRef, Tag) ->
    beamai_kernel:tools_by_tag(KernelRef, Tag).

%%====================================================================
%% Context
%%====================================================================

%% @doc Get the current execution context (default).
-spec context() -> context().
context() ->
    beamai_kernel:context(kernel()).

%% @doc Get the execution context for a specific kernel.
-spec context(kernel_ref()) -> context().
context(KernelRef) ->
    beamai_kernel:context(KernelRef).
