$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'sqlite3'
require 'active_record'
require 'yaml'
require 'rbconfig'
require 'logger'
require 'active_support/core_ext/hash/indifferent_access'

require 'api_client'
require 'active_record_connection'
require 'import'

model_dir = File.join(File.dirname(__FILE__), 'model')
$LOAD_PATH.unshift(model_dir)
Dir[File.join(model_dir, "*.rb")].each {|file| require File.basename(file, '.rb') }

LOG_FILE = File.expand_path(File.join('..', 'log', 'adapter_sync.log'), File.dirname(__FILE__))
CONFIG_FILE = File.expand_path(File.join('..', 'config', 'adapter_sync.yml'), File.dirname(__FILE__))
API_CONFIG_FILE = File.expand_path(File.join('..', 'config', 'api.yml'), File.dirname(__FILE__))
DB_CONFIG_FILE = File.expand_path(File.join('..', 'config', 'database.yml'), File.dirname(__FILE__))
MIGRATIONS_DIR = File.expand_path(File.join('..', 'db', 'migrations'), File.dirname(__FILE__))

def load_config(file)
  (YAML::load(File.open(file)) || {}).with_indifferent_access
end


begin
  logger = Logger.new(LOG_FILE, 'weekly')
  options = load_config(CONFIG_FILE)

  # open the database, creating it if necessary, and make sure up to date with latest migrations
  # TODO need a global environment setting like Rails.env
  connection = ActiveRecordConnection.new(logger, load_config(DB_CONFIG_FILE)[:development])
  connection.migrate(MIGRATIONS_DIR)

  # create connection to the Clearinghouse API
  apiconfig = load_config(API_CONFIG_FILE)[:development]
  apiconfig['raw'] = false
  clearinghouse = ApiClient.new(apiconfig)

  importer = Import.new(logger)
  importer.import_folder(options[:import][:new_folder]) do |row|
    begin
      # TODO allow API to throw exceptions on server error responses or force it to return a result?
      # TODO we need to cleanly handle when we post a trip ticket that already exists
      # TODO report errors to monitor in case they require a notification to user (handle notifications in one place?)
      result = clearinghouse.post(:trip_tickets, row)
      logger.info "Posted trip ticket to API, result #{result}"
    rescue Exception => e
      logger.error "Row error: " << e.message
    end
  end

rescue Exception => e
  logger.error e.message + "\n" + e.backtrace.join("\n")
  exit 1
end
