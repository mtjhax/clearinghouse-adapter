$LOAD_PATH.unshift(File.dirname(__FILE__))

ENV["ADAPTER_ENV"] ||= 'development'

require 'sqlite3'
require 'active_record'
require 'yaml'
require 'rbconfig'
require 'logger'
require 'active_support/core_ext/hash/indifferent_access'

require 'api_client'
require 'active_record_connection'
require 'import'
require 'adapter_monitor_notification'

model_dir = File.join(File.dirname(__FILE__), 'model')
$LOAD_PATH.unshift(model_dir)
Dir[File.join(model_dir, "*.rb")].each {|file| require File.basename(file, '.rb') }

# This code should use exit(1) or raise an exception for errors that should be considered a service "outage"
#
# Service outages should include things such as:
# - Import folders not configured, resulting in no work being done
# - Failure to connect to the Clearinghouse API
# - Any unforeseen exception
#
# Normal operating errors such as an invalid import file or a row that generates an API error should
# be logged and optionally cause a notification, but don't really constitute an "outage" (although it
# would be nice if the user could configure what to consider a failure vs. a normal error).

class AdapterSync
  LOG_FILE = File.expand_path(File.join('..', 'log', 'adapter_sync.log'), File.dirname(__FILE__))
  CONFIG_FILE = File.expand_path(File.join('..', 'config', 'adapter_sync.yml'), File.dirname(__FILE__))
  API_CONFIG_FILE = File.expand_path(File.join('..', 'config', 'api.yml'), File.dirname(__FILE__))
  DB_CONFIG_FILE = File.expand_path(File.join('..', 'config', 'database.yml'), File.dirname(__FILE__))
  MIGRATIONS_DIR = File.expand_path(File.join('..', 'db', 'migrations'), File.dirname(__FILE__))

  attr_accessor :options

  def initialize(options = {})
    @logger = Logger.new(LOG_FILE, 'weekly')
    @options = load_config(CONFIG_FILE)
    @options.merge!(options)

    # open the database, creating it if necessary, and make sure up to date with latest migrations
    @connection = ActiveRecordConnection.new(@logger, load_config(DB_CONFIG_FILE)[ENV["ADAPTER_ENV"]])
    @connection.migrate(MIGRATIONS_DIR)

    # create connection to the Clearinghouse API
    apiconfig = load_config(API_CONFIG_FILE)[ENV["ADAPTER_ENV"]]
    apiconfig['raw'] = false
    @clearinghouse = ApiClient.new(apiconfig)
  end

  def poll
    # check for tickets in a CSV file to import
    import_tickets if @options[:import][:enabled]
  rescue Exception => e
    @logger.error e.message + "\n" + e.backtrace.join("\n")
    raise
  end

  def import_tickets
    import_dir = @options[:import][:import_folder]
    output_dir = @options[:import][:completed_folder]
    import = Import.new

    @logger.info "Starting import from directory [#{import_dir}] with output directory [#{output_dir || 'n/a'}]"

    # ensure import directory is configured and exists
    err_msg = import.check_directory(import_dir)
    raise err_msg if err_msg

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
      else
        trip = TrackedTicket.find_or_create(row[:origin_trip_id], row[:appointment_time])

        unless trip.synced?
          api_result = post_new_trip(row)
          log.info "POST trip ticket with API, result #{api_result}"
        else
          # trip is already tracked, see if we need to update the CH
          # Note: for now we just try an update and see what happens, we need to deal with error if no fields changed
          api_result = put_trip_changes(row)
          log.info "PUT trip ticket with API, result #{api_result}"
        end
        raise Import::RowError, "API result should be an array" unless api_result.is_a?(Array)
        raise Import::RowError, "API result is empty" unless api_result.length > 0
        raise Import::RowError, "API result does not contain an ID" if api_result[0]['id'].nil?

        trip.update(clearinghouse_id: api_result[0]['id'])
      end
    end

    @logger.info "Imported #{import_results.length} files"
    import_results.each do |r|
      @logger.info r.to_s
      # as an extra layer of safety, record files that were imported so we can avoid reimporting them
      ImportedFile.create(r)
      # send notifications for files that contained errors
      if r.error? || r.row_errors.to_i > 0
        msg = "Encountered #{r.row_errors} errors while importing file #{r.file_name} at #{r.created_at}:\\n#{r.error_msg}"
        begin
          AdapterNotification.new(error: msg).send
        rescue Exception => e
          @logger.error "Error notification failed, could not send email: #{e}"
        end
      end
    end
  end

  protected

  def post_new_trip(trip_hash)
    begin
      @clearinghouse.post(:trip_tickets, trip_hash)
    rescue Exception => e
      # TODO if exception indicates a duplicate object, we probably want to get the trip from the CH then try an update
      raise Import::RowError, "API error on POST: #{e}"
    end
  end

  def put_trip_changes(trip_hash)
    begin
      @clearinghouse.put(:trip_tickets, trip_hash)
    rescue Exception => e
      # TODO if exception indicates an error due to no changes, we should just ignore that error
      raise Import::RowError, "API error on PUT: #{e}"
    end
  end

  def load_config(file)
    (YAML::load(File.open(file)) || {}).with_indifferent_access
  end

end
