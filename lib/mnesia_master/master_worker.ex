defmodule MnesiaMaster.MasterWorker do
  use GenServer

  @nodes Application.get_env(:mnesia_master, :nodes)
  require Logger

  def init(_) do
    :net_kernel.monitor_nodes(true, [])
    send(self(), :init_master)
    Enum.each(@nodes, fn node -> Node.monitor(node, true) end)
    if node() in @nodes do
      init_mnesia(@nodes)
      send(self(), :register_name)
    end
    {:ok, %{nodes: @nodes}}
  end

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  def init_mnesia(nodes) do
    stop_mnesia(nodes)
    with false <- schema_exist?(nodes),
         :ok <- :mnesia.create_schema(nodes) |> IO.inspect(),
         :ok <- start_mnesia(nodes),
         :ok <- register_mnesia(nodes),
         {:atomic, :ok} <- :mnesia.create_table(:offers, [{:rocksdb_copies, nodes}]) do
      :ok
    else
      _ -> start_mnesia(nodes)
           register_mnesia(nodes)
           :error
    end
  end

  def schema_exist?(nodes) do
    exist_nodes = :mnesia.table_info(:schema, :disc_copies)
    MapSet.equal?(MapSet.new(nodes), exist_nodes)
  end

  def stop_mnesia(nodes) do
    remain_nodes = Enum.reject(nodes, fn node_name -> node_name == node() end)
    :rpc.multicall(remain_nodes, PusherDb.Utils, :stop_mnesia, []) |> IO.inspect(label: "multicall stop")
    :mnesia.stop
  end

  def start_mnesia(nodes) do
    remain_nodes = Enum.reject(nodes, fn node_name -> node_name == node() end)
    :mnesia.start
    :rpc.multicall(remain_nodes, PusherDb.Utils, :start_mnesia, []) |> IO.inspect(label: "multicall start")
    :ok

  end

  def register_mnesia(nodes) do
    remain_nodes = Enum.reject(nodes, fn node_name -> node_name == node() end)
    :mnesia_rocksdb.register()
    :rpc.multicall(remain_nodes, PusherDb.Utils, :register_mnesia, []) |> IO.inspect(label: "multicall register")
    :ok
  end

  def handle_info({:nodeup, new_node}, %{nodes: nodes} = state) do
    Logger.info("Node up #{inspect(new_node)}")

    if new_node not in :mnesia.table_info(:offers, :rocksdb_copies) do
      :mnesia.change_config(:extra_db_nodes, [new_node]) |> IO.inspect(label: "#{new_node}")
      :mnesia.change_table_copy_type(:schema, new_node, :disc_copies) |> IO.inspect(label: "#{new_node}")
      :mnesia.add_table_copy(:offers, new_node, :rocksdb_copies) |> IO.inspect(label: "#{new_node}")
    end

    {:noreply, %{state | nodes: [new_node | nodes]}}
  end

  def handle_info(:register_name, state) do
    :global.register_name(MasterWorker, self())

    {:noreply, state}
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
