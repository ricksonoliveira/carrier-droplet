defmodule CarrierDroplet.Repo do
  use Ecto.Repo,
    otp_app: :carrier_droplet,
    adapter: Ecto.Adapters.Postgres
end
