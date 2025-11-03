Mimic.copy(Req)
Mimic.copy(CarrierDroplet.Gmail.Client)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(CarrierDroplet.Repo, :manual)
