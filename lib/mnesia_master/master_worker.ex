defmodule MnesiaMaster.MasterWorker do
  use GenServer
  @nodes []
  require Logger

  def init(_) do
    :net_kernel.monitor_nodes(true, [])
    Enum.each(@nodes, fn node -> Node.monitor(node, true) end)
    init_mnesia(@nodes)
    :global.register_name(MasterMnesia, self())
    {:ok, %{nodes: @nodes}}
  end

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  def init_mnesia(nodes) do
    # TODO case
    stop_mnesia(nodes)
    :mnesia.create_schema(nodes)
    start_mnesia(nodes)
  end

  def stop_mnesia(nodes) do
    :rpc.multicall(nodes, PusherDb.Utils, :stop_mnesia, [])
  end

  def start_mnesia(nodes) do
    :rpc.multicall(nodes, PusherDb.Utils, :start_mnesia, [])
  end

  def handle_info({:nodeup, node}, %{nodes: nodes} = state) do
    Logger.info("Node up #{inspect(node)}")
    if node not in :mnesia.table_info(:offers, :rocksdb_copies) do
      :mnesia.change_config(:extra_db_nodes, [node])
      :mnesia.add_table_copy(:offers, node, :rocksdb_copies)
    end

    {:noreply, %{state | nodes: [node | nodes]}}
  end

  def handle_info({:nodedown, node}, %{nodes: nodes} = state) do
    Logger.error("Node down #{inspect(node)}")
    Node.monitor(node, true)
    remain_nodes = Enum.reject(nodes, fn node_name -> node_name == node end)
    {:noreply, %{state | nodes: remain_nodes}}
  end

  def handle_info({:add_nodes_from_config, node}, %{nodes: nodes} = state) do
    Node.monitor(node, true)
    {:noreply, %{state | nodes: [node | nodes]}}
  end
end
