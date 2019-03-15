defmodule PusherDbClient.ConfigWorker do
  use GenServer
  require Logger

  @section "nodes configuration"
  @path Application.get_env(:mnesia_master, :config_path)
  @period_read_config Application.get_env(:mnesia_master, :period_read_config)
  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    send(self(), :read_config)
    {:ok, %{nodes: MapSet.new()}}
  end

  def handle_info(:read_config, %{nodes: nodes} = state) do
    # list_of_nodes =
    #   try do
    #     {:ok, parse_result} = ConfigParser.parse_file(@path)

    #     get_values(parse_result, @section)
    #     |> Enum.filter(fn node -> alive_node?(node) end)
    #     |> MapSet.new()
    #   rescue
    #     e ->
    #       Logger.error("Can't find config file #{inspect(e)}, create it!")
    #       []
    #   end

    # GenServer.cast(NodeWorker, {:update_from_config, list_of_nodes})
    # Process.send_after(self(), :read_config, @period_read_config)

    # new_nodes = if MapSet.equal?(list_of_nodes, nodes) do
    #   nodes
    # else
    #   up_nodes = Enum.map(MapSet.difference(list_of_nodes, nodes), fn node -> add_node_to_cluster(node) end)
    #   up_nodes ++ nodes
    # end

    # {:noreply, %{state | nodes: new_nodes}}
    {:noreply, state}
  end

  @spec alive_node?(atom()) :: boolean()
  def alive_node?(node) do
    if Node.ping(node) == :pong do
      # Logger.info("connection node: #{inspect(node)} was estabilished")
      true
    else
      false
    end
  end

  @spec get_values(any(), binary()) :: list()
  def get_values(parser_result, section) do
    ConfigParser.get(parser_result, section, "nodes")
    |> String.split(", ")
    |> Enum.map(fn node ->
      try do
        String.to_existing_atom(node)
      rescue
        _ -> String.to_atom(node)
      end
    end)
  end
  def add_node_to_cluster(node) do
    GenServer.cast(MnesiaMaster.MasterWorker, {:add_nodes_from_config, node})
  end
end
