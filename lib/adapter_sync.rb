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

class AdapterSync

  def initialize
    @logger = Logger.new(LOG_FILE, 'weekly')
    @options = load_config(CONFIG_FILE)

    # open the database, creating it if necessary, and make sure up to date with latest migrations
    # TODO need a global environment setting like Rails.env
    @connection = ActiveRecordConnection.new(@logger, load_config(DB_CONFIG_FILE)[:development])
    @connection.migrate(MIGRATIONS_DIR)

    # create connection to the Clearinghouse API
    apiconfig = load_config(API_CONFIG_FILE)[:development]
    apiconfig['raw'] = false
    @clearinghouse = ApiClient.new(apiconfig)
  end

  def poll
    # check for tickets in a CSV file to import
    import_tickets if @options[:import][:enabled]


    # TODO adapter polls local system for new/modified tickets, pushes new tickets/changes
    #
    # How do we know which tickets and changes are new? Local cache or marked in database? We should try to avoid
    # stashing Adapter-specific information in the provider system database because we don't really have control
    # over it, so we will stash them locally, only after successful push.
    #
    # If possible, mark the ticket in the provider system as having been shared, but don't rely on these marks
    #
    # Local cache could just be a date last poll was run, but that might be unreliable.
    #
    # If the cache is empty it needs to look them up on the CH (or just try creating them and fail) -- loss of local
    # cache should not prevent normal operation but duplicate tickets should not be created.

  rescue Exception => e
    @logger.error e.message + "\n" + e.backtrace.join("\n")
    exit 1
  end

  protected

  def load_config(file)
    (YAML::load(File.open(file)) || {}).with_indifferent_access
  end

  def import_tickets
    import_dir = @options[:import][:import_folder]
    output_dir = @options[:import][:completed_folder]
    import = Import.new

    @logger.info "Starting import from directory [#{import_dir}] with output directory [#{output_dir || 'n/a'}]"

    # ensure import directory is configured and exists
    err_msg = import.check_directory(import_dir)
    if err_msg
      @logger.warn err_msg
      @options[:import][:enabled]= false
      return
    end

    # check each file the import thinks it can work with to see if we imported it previously
    skips = []
    import.importable_files(import_dir).each do |file|
      size = File.size(file)
      modified = File.mtime(file)
      if ImportedFile.where(file_name: file, size: size, modified: modified).count > 0
        @logger.warn "Skipping file #{file} which was previously imported"
        skips << file
      end
    end

    # import folder and process each imported row
    import_results = import.from_folder(import_dir, output_dir, skips) do |row, log|
      if row[:origin_trip_id].nil?
        raise Import::RowError, "Imported row does not contain an origin_trip_id value"
      elsif TrackedTicket.where(origin_trip_id: row[:origin_trip_id]).where('clearinghouse_id IS NOT NULL').count > 0
        raise Import::RowError, "Trip ticket with ID #{row[:origin_trip_id]} already imported"
      else
        begin
          api_result = @clearinghouse.post(:trip_tickets, row)
        rescue Exception => e
          # TODO should probably only treat logical errors as recoverable, e.g. a server model validation fails
          raise Import::RowError, "API error: #{e}"
        end
        log.info "Posted trip ticket to API, result #{api_result}"
        raise Import::RowError, "API result should be an array" unless api_result.is_a?(Array)
        raise Import::RowError, "API result is empty" unless api_result.length > 0
        raise Import::RowError, "API result does not contain an ID" if api_result[0]['id'].nil?
        TrackedTicket.create(origin_trip_id: row[:origin_trip_id], clearinghouse_id: api_result[0][:id])
      end
    end

    @logger.info "Imported #{import_results.length} files"
    import_results.each do |r|
      # TODO send notification for files that failed (handled here or by Monitor service?)
      @logger.info r.to_s
      # as an extra layer of safety, record files that were imported so we can avoid reimporting them
      ImportedFile.create(r)
    end
  end

end

AdapterSync.new.poll
