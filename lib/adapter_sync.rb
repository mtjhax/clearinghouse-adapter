$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'sqlite3'
require 'active_record'
require 'yaml'
require 'rbconfig'
require 'logger'
require 'csv'
require 'active_support/core_ext/hash/indifferent_access'

require 'api_client'
require 'active_record_connection'

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

  # check designated folder for tickets to import
  # TODO need to refactor this import into a method or module to keep the main sync logic clean
  import_dir = options[:import][:new_folder]
  if import_dir.nil?
    logger.info "Import folder not configured, will not check for files to import"
  elsif Dir[import_dir].empty?
    logger.info "Import folder #{import_dir} does not exist, will not check for files to import"
  else
    logger.info "Checking folder #{File.expand_path(import_dir)} for files to import"
    import_files = Dir[File.join(File.expand_path(import_dir), "*.{txt,csv}")]
    logger.info "Found #{import_files.length} files to import"
    import_files.each do |file|
      logger.info "Importing #{file}"
      # TODO capture exceptions, particularly CSV::MalformedCSVError
      CSV.foreach(file, headers: true, return_headers: false) do |row|
        values = Hash[row.headers.zip(row.fields)]
        logger.info "Row: #{values}"
        begin
          # TODO allow API to throw exceptions on server error responses or force it to return a result?
          # TODO we need to cleanly handle when we post a trip ticket that already exists
          result = clearinghouse.post(:trip_tickets, values)
          logger.info "Posted trip ticket to API, result #{result}"
        rescue Exception => e
          logger.error "Row error: " << e.message
        end
      end
    end
  end

rescue Exception => e
  logger.error e.message + "\n" + e.backtrace.join("\n")
  exit 1
end
