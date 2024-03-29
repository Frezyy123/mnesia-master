defmodule MnesiaMaster.MasterWorker do
  use GenServer

  @nodes Application.get_env(:mnesia_master, :nodes)
  require Logger

  def init(_) do
    :net_kernel.monitor_nodes(true, [])
    Enum.each(@nodes, fn node -> Node.monitor(node, true) end)

    if node() in @nodes do
      nodes = [node() | Node.list()] |> IO.inspect()
      init_mnesia(nodes)
      send(self(), :register_name)
    end

    {:ok, %{nodes: @nodes}}
  end

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  def init_mnesia(nodes) do
    IO.inspect("init mnesia")

    with :ok <- start_mnesia(nodes),
         :ok <- :mnesia.wait_for_tables([:schema], 5000),
         false <- schema_exist?(nodes),
         :ok <- stop_mnesia(nodes),
         :ok <- :mnesia.create_schema(nodes) |> IO.inspect(),
         :ok <- start_mnesia(nodes),
         :ok <- register_mnesia(nodes),
         {:atomic, :ok} <- :mnesia.create_table(:offers, [{:rocksdb_copies, nodes}]) do
      :ok
    else
      _ ->
        start_mnesia(nodes)
        register_mnesia(nodes)
        :error
    end
  end

  def schema_exist?(nodes) do
    IO.inspect("schema_exist?")

    try do
      exist_nodes =
        :mnesia.table_info(:schema, :active_replicas) |> IO.inspect(label: "Mnesia nodes")

      nodes |> IO.inspect(label: "List of nodes")
      MapSet.equal?(MapSet.new(nodes), MapSet.new(exist_nodes)) |> IO.inspect()
    rescue
      _ -> false
    end
  end

  def stop_mnesia(nodes) do
    case :rpc.multicall(nodes, PusherDb.Utils, :stop_mnesia, []) do
      {_, [_ | _]} -> :error
      {_, []} -> :ok
    end
  end

  def start_mnesia(nodes) do
    case :rpc.multicall(nodes, PusherDb.Utils, :start_mnesia, []) do
      {_, [_ | _]} -> :error
      {_, []} -> :ok
    end
  end

  def register_mnesia(nodes) do
    case :rpc.multicall(nodes, PusherDb.Utils, :register_mnesia, []) do
      {_, [_ | _]} -> :error
      {_, []} -> :ok
    end
  end

  def handle_info({:nodeup, new_node}, %{nodes: nodes} = state) do
    Logger.info("Node up #{inspect(new_node)}")

    try do
      Logger.info("Add node #{new_node} to cluster")

      with true <- new_node not in :mnesia.table_info(:offers, :rocksdb_copies),
           {:ok, _} <- :mnesia.change_config(:extra_db_nodes, [new_node]),
           :ok <- :mnesia.wait_for_tables([:schema], 5000),
           {:atomic, :ok} <- :mnesia.change_table_copy_type(:schema, new_node, :disc_copies),
           {:atomic, :ok} <- :mnesia.add_table_copy(:offers, new_node, :rocksdb_copies) do
        Node.monitor(new_node, true)
      else
        e -> Logger.error("Can't add node to cluser, reason: #{inspect(e)}")
      end
    catch
      :exit, reason ->
        Logger.debug("#{inspect(reason)}")
        :ok
    end

    {:noreply, %{state | nodes: [new_node | nodes]}}
  end

  def handle_info(:register_name, state) do
    :global.register_name(MasterWorker, self())

    {:noreply, state}
  end

  def handle_info({:nodedown, node}, %{nodes: nodes} = state) do
    # Logger.error("Node down #{inspect(node)}")
    Node.monitor(node, true)
    remain_nodes = Enum.reject(nodes, fn node_name -> node_name == node end)
    {:noreply, %{state | nodes: remain_nodes}}
  end

  def handle_info({:add_nodes_from_config, node}, %{nodes: nodes} = state) do
    Node.monitor(node, true)
    {:noreply, %{state | nodes: [node | nodes]}}
  end
end
