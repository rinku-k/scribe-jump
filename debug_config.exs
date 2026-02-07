
IO.puts "DEBUGGING CONFIG"
config = Application.get_env(:ueberauth, Ueberauth.Strategy.Hubspot.OAuth)
IO.inspect(config, label: "Ueberauth.Strategy.Hubspot.OAuth Config")

hubspot_client_id = System.get_env("HUBSPOT_CLIENT_ID")
IO.inspect(hubspot_client_id, label: "System.get_env(\"HUBSPOT_CLIENT_ID\")")
