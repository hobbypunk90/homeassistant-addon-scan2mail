require "active_support/all"
require 'logger'
require 'config'

require_relative 'scan2mail/client.rb'
require_relative 'mqtt/client.rb'

def main
  Config.load_and_set_settings(File.join("#{Config.file_name}.yml").to_s,
                               File.join("#{Config.file_name}.local.yml").to_s)
  logger = Logger.new($stdout)

  client = Mqtt::Client.new(logger:)

  Scan2Mail::Client.new(client, logger:)

  while client.running
    sleep 1
  end

  client.disconnect
end

main
