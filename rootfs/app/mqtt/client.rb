require 'mqtt'
require 'json'
require 'logger'

module Mqtt
  class Client
    ONLINE_STATES = [:online, :waiting, :scanning, :converting, :sending, :error]

    attr_reader :logger
    attr_reader :running
    attr_reader :subscritions
  
    def initialize(logger: Logger.new($stdout))
      @client = MQTT::Client.connect("mqtt://#{Settings.mqtt.username}:#{Settings.mqtt.password}@#{Settings.mqtt.server}:#{Settings.mqtt.port}", will_topic: topic(:status), will_payload: :offline, will_retain: true)
      @subscritions = {}
      @logger = logger

      trap("SIGINT") do
        stop
      end
  
      discover(:sensor, :status, {
        availability_topic: nil,
        availability_template: nil,
        payload_available: nil,
        payload_not_available: nil,
        device_class: :enum,
        options: [:offline] + ONLINE_STATES,
        state_topic: topic(:status),
        json_attributes_topic: topic(:'status/attributes'),
        icon: 'mdi:state-machine'
      })
  
      discover_and_subscribe_button(:shutdown, { icon: 'mdi:power' }) do |_, _|
        logger.info "Shutdown..."
        stop
      end

      online()
      create_getter_thread()
    end
  
    ONLINE_STATES.each do |state|
      define_method(state) do |message = nil|
        @running = true
        publish(topic(:status), state, retain: true)
        if message.present?
          publish(topic(:'status/attributes'), {message:}, retain: true)
        else
          publish(topic(:'status/attributes'), {}, retain: true)
          publish(topic(:'status/attributes'), nil, retain: false)
        end
      end
    end

    def discover_and_subscribe_button(name, options = {}, &)
      discover(:button, name, {
        command_topic: "~/button/#{topicize(name)}"
      }.merge(options))

      subscribe("button/#{name}", &)
    end
  
    def discover(type, name, options)
      topic = topic().gsub('/', '')
      options = {
        name: name.to_s.titleize,
        '~': topic,
        availability_topic: '~/status',
        availability_template: "{{ 'online' if value == 'online' or value == 'error' else 'offline' }}",
        payload_available: 'online',
        payload_not_available: 'offline',
        unique_id: "#{topic(name).gsub('/', '__')}",
        device: {
          name: 'Scan 2 Mail',
          manufacturer: 'Hobbypunk',
          model: 'Scan2Mail Service',
          identifiers: [topic, 'BxTgDTtvT4WGNczDmhue'],
          sw_version: '0.1'
        }
      }.merge(options).compact
  
      publish("homeassistant/#{type}/#{topic(name)}/config", options)
    end
  
    def publish(topic, data, retain: false)
      data = data.to_json if data.is_a?(Hash) || data.is_a?(Array)
      @client.publish(topic, data, retain = retain)
    end
  
    def create_getter_thread
      Thread.new do
        @client.get do |topic, message| 
          subscritions[topic].call(topic, message) if subscritions[topic].present?
        rescue StandardError => error
          logger.error(error)
        end
      end
    end

    def subscribe(topic, &block)
      topic = topic(topic)
      subscritions[topic] = block
      @client.subscribe(topic)
    end
    
    def disconnect()
      publish(topic(:status), :offline, retain: true)
      @client.disconnect()
    end
  
    def topic(name = nil)
      "scan2mail/#{topicize(name)}"
    end

    def topicize(str)
      str.to_s.gsub(/[^\/a-zA-Z0-9_-]/, '').gsub(/\/$/, '-')
    end
  
    def stop
      @running = false
    end
  end  
end
