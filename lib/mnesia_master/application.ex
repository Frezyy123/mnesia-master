defmodule MnesiaMaster.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [

      %{id: PusherDbClient.ConfigWorker, start: {PusherDbClient.ConfigWorker, :start_link, []}},
      %{id: MnesiaMaster.MasterWorker, start: {MnesiaMaster.MasterWorker, :start_link, []}}
      # Starts a worker by calling: MnesiaMaster.Worker.start_link(arg)
      # {MnesiaMaster.Worker, arg},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MnesiaMaster.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
