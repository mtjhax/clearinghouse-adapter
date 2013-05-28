require 'rbconfig'
require 'logger'
require 'mail'
require 'active_support/core_ext/hash/indifferent_access'

CONFIG_FILE = File.expand_path(File.join('..', 'config', 'mail.yml'), File.dirname(__FILE__))
LOG_FILE = File.expand_path(File.join('..', 'log', 'adapter_monitor_notification.log'), File.dirname(__FILE__))

class AdapterNotification

  def initialize(options = {})
    @options = (options || {}).with_indifferent_access
  end

  def send
    begin
      config = YAML::load(File.open(CONFIG_FILE)).with_indifferent_access

      mail_config = config['connection']
      message = config['message']

      send_method = (mail_config.delete(:delivery_method) || :smtp).to_sym
      Mail.defaults do
        delivery_method send_method, mail_config
      end

      logger = Logger.new(LOG_FILE, 'weekly')

      raise "ERROR message 'to' address not configured, cannot send notification" if message['to'].nil?

      message['from'] ||= "noreply@rideconnection.org"
      message['subject'] ||= "Adapter error notification"
      message['body'] ||= "The Clearinghouse Adapter has encountered an error."
      message['body'] << "\n#{@options[:error]}" if @options[:error]

      Mail.deliver do
        to message['to']
        from message['from']
        subject message['subject']
        body message['body']
      end

    rescue Exception => e
      logger.error e.message + "\n" + e.backtrace.join("\n")
      raise
    end
  end
end

opts = Slop.parse do
  banner 'Usage: adapter_monitor_notification.rb [options]'
  on :a, :auto, 'Send email and exit ', argument: :optional
  on :e, :error=, 'Error description', argument: :optional
end

if opts.auto?
  notifier = AdapterNotification.new(opts.to_hash)
  notifier.send
end
