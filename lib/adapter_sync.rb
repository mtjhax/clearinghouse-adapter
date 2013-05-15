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

  # process for syncing the provider scheduling system with the clearinghouse:
  #
  # 1. adapter polls local system for new/modified tickets, pushes new tickets/changes
  #
  # how does the adapter know they are new/modified? it needs a local cache to list them as already having been shared,
  # possibly just using date of last update, or if the cache is empty it needs to look them up on the CH (or just try creating them)
  #
  # if possible, mark the ticket in the provider system as having been shared, but don't rely on these marks
  #
  # 2. adapter polls local system for claimed tickets with modifications/results, pushes results/changes
  #
  # how does the adapter know which tickets are claimed by the provider? use local cache of claimed tickets,
  # or query CH for all claimed ticket IDs.
  #
  # 3. adapter polls CH for claims and results on originated tickets, pulls claims/results
  #
  # primary point of this is to mark local ticket (if possible) so dispatcher is aware it has been claimed/completed
  # although there is a fallback which is the CH lets them know,
  #
  # adapter recognizes new claims/results on originated tickets by date(?)
  #
  # 4. adapter polls CH for new and modified claimed tickets, pulls claimed tickets/changes
  #
  # how does adapter know which claimed tickets are new or changed? cache, fallback is to query all claimed
  # tickets and see which ones exist on local system already.

  # How do we know which tickets and changes are new? Local cache or marked in database? We should try to avoid
  # stashing Adapter-specific information in the provider system database because we don't really have control
  # over it, so we will stash them locally, only after successful push.


  importer = Import.new(logger)
  import_results = importer.import_folder(options[:import][:new_folder]) do |row|
    begin
      # TODO allow API to throw exceptions on server error responses or force it to return a result?
      # TODO we need to cleanly handle when we post a trip ticket that already exists
      result = clearinghouse.post(:trip_tickets, row)
      logger.info "Posted trip ticket to API, result #{result}"
    rescue Exception => e
      logger.error "Row error: " << e.message
    end
  end

  # TODO send notification for files that failed (handled here or by Monitor service?)
  logger.info "Imported #{import_results.length} files, results:"
  import_results.each do |r|
    logger.info "File [#{r[:file_name]}], Rows [#{r[:rows]}], Error [#{r[:error] ? r[:error_msg] : 'none'}], "
  end

rescue Exception => e
  logger.error e.message + "\n" + e.backtrace.join("\n")
  exit 1
end
