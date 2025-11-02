import Config

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
if File.exists?(Path.expand("#{config_env()}.exs", __DIR__)) do
  import_config "#{config_env()}.exs"
end
