require 'rbconfig'
require 'logger'
require 'mail'

# TODO make a worker base class or mixin that enforces some useful conventions
# TODO make some basic libs to include in all modules with helpers stolen from Rails and elsewhere
class Object
  def to_sym
    self
  end
end
class Hash
  def symbolize_keys
    dup.symbolize_keys!
  end
  def symbolize_keys!
    keys.each do |key|
      self[key.to_sym] = delete(key)
    end
    self
  end
end

CONFIG_FILE = File.expand_path(File.join('..', 'config', 'mail.yml'), File.dirname(__FILE__))
LOG_FILE = File.expand_path(File.join('..', 'log', 'adapter_monitor_notification.log'), File.dirname(__FILE__))

begin
  mail_config = YAML::load(File.open(CONFIG_FILE)).symbolize_keys!
  send_method = mail_config.delete(:delivery_method).to_sym || :smtp
  Mail.defaults do
    delivery_method send_method, mail_config
  end

  logger = Logger.new(LOG_FILE, 'weekly')

  # TODO get arguments from the command line
  Mail.deliver do
    to 'mtj@cmpj.org'
    from 'adapter@cmpj.org'
    subject 'Test notification'
    body 'This is a test notification to see if we can alert ourselves via email in case of errors'
  end
rescue Exception => e
  logger.error e.message + "\n" + e.backtrace.join("\n")
  exit 1
end
