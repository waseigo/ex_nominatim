Logger.configure(level: :warning)

{:ok, _pid} = Agent.start_link(fn -> %{} end, name: ExNominatim.TestCache)

ExUnit.start()
