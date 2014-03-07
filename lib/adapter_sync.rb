# Copyright 2013 Ride Connection
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

$LOAD_PATH.unshift(File.dirname(__FILE__))

ENV["ADAPTER_ENV"] ||= 'development'

require 'sqlite3'
require 'active_record'
require 'yaml'
require 'rbconfig'
require 'logger'
require 'active_support/core_ext/object'
require 'active_support/core_ext/hash'
require 'hash'

# TODO is this lib still required?
require 'active_support/time_with_zone'

require 'api_client'
require 'active_record_connection'
require 'adapter_monitor_notification'
require 'export_processor'
require 'import_processor'

# TODO remove after refactoring
require 'debugger'

# TODO refactor this into the ImportProcessor class
require 'import'

model_dir = File.join(File.dirname(__FILE__), 'model')
$LOAD_PATH.unshift(model_dir)
Dir[File.join(model_dir, "*.rb")].each {|file| require File.basename(file, '.rb') }

Time.zone = "UTC"

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

=begin
TASK Refactor Adapter change comparison and what pre-/post-processors are used for
TODO ~Remove HashDiff library since it won't be used anymore~
TODO ~Remove code that diffs data being exported to API~
TODO ~Remove code that diffs data being imported from API~
TODO Create new ExportProcessorBase class. It should accept API data as a parsed JSON array, perform any data massaging necessary (the base class may not need to do this, but allow it to be done for sub classes), and it should finish by dumping the data to a flat CSV file (one per object type). Ensure that hstore and array fields are represented as proper columns: one column for each value for arrays; one column each for every key and value for hstores
TODO Create new ImportProcessorBase class. It should pick up flat CSV files in the same format as how the ImportProcessorBase class writes them, perform any data massaging necessary (the base class may not need to do this, but allow it to be done for sub classes), and finish by POSTing the data to the proper API endpoint.
TODO Move export_csv to ExportProcessorBase class
TODO Simplify sync process - poll API for incoming updates, call export processor, call import processor, send outgoing updates to API
TODO Remove the imported_file migration and refactor that into the ImportProcessor class. 
TODO Alternately, refactor the import table to just track generic strings that the ImportProcessor can poll - upside: convenient, downside: requires Processor class have implementation knowledge about AdapterSync
TODO Add OS license blurb to new files
=end

class AdapterSync
  BASE_DIR        = File.expand_path('..', File.dirname(__FILE__))
  LOG_FILE        = File.join(BASE_DIR, 'log', 'adapter_sync.log')
  CONFIG_FILE     = File.join(BASE_DIR, 'config', 'adapter_sync.yml')
  API_CONFIG_FILE = File.join(BASE_DIR, 'config', 'api.yml')
  DB_CONFIG_FILE  = File.join(BASE_DIR, 'config', 'database.yml')
  MIGRATIONS_DIR  = File.join(BASE_DIR, 'db', 'migrations')
  PROCESSORS_DIR  = File.join(BASE_DIR, 'processors')

  attr_accessor :options, :logger, :errors, :updated_trips, 
    :export_processor, :import_processor

  def initialize(opts = {})
    @logger = Logger.new(LOG_FILE, 'weekly')
    @options = opts.presence || load_config(CONFIG_FILE)

    @errors, @updated_trips = [[], []]

    # open the database, creating it if necessary, and make sure up to date with latest migrations
    @connection = ActiveRecordConnection.new(logger, load_config(DB_CONFIG_FILE)[ENV["ADAPTER_ENV"]])
    @connection.migrate(MIGRATIONS_DIR)

    # create connection to the Clearinghouse API
    apiconfig = load_config(API_CONFIG_FILE)[ENV["ADAPTER_ENV"]]
    apiconfig['raw'] = false
    @clearinghouse = ApiClient.new(apiconfig)
    
    # create ExportProcessor and ImportProcessor instances
    require File.join(PROCESSORS_DIR, options[:export][:processor]) if options[:export].try(:[], :processor).present?
    require File.join(PROCESSORS_DIR, options[:import][:processor]) if options[:import].try(:[], :processor).present?
    @export_processor = ExportProcessor.new(@logger, options[:export].try(:[], :options))
    @import_processor = ImportProcessor.new(@logger, options[:import].try(:[], :options))
  end

  def poll
    @errors, @updated_trips = [[], []]
    replicate_clearinghouse
    export_tickets
    import_tickets
  rescue Exception => e
    logger.error e.message + "\n" + e.backtrace.join("\n")
    raise
  end

  def replicate_clearinghouse
    last_updated_at = most_recent_tracked_update_time
    trips = get_updated_clearinghouse_trips(last_updated_at)
    logger.info "Retrieved #{trips.length} updated trips from API"
    @updated_trips = trips.collect{|trip|
      trip_data = trip.data.deep_dup
      process_updated_clearinghouse_trip(trip_data)
    }.compact
    report_errors "syncing with the Ride Clearinghouse", @errors
  end

  def export_tickets
    export_processor.process(@updated_trips) if options[:export][:enabled]
    report_errors "processing the exported trip tickets", export_processor.errors
  end

  # TODO - refactor to use ImportProcessor. It should start by calling 
  # import_processor.process with no arguments (the ImportProcessor)
  # class is responsible for aquring the import data, by reading flat
  # files, or reading from the DB directly, etc.). It should return 
  # an array of trip ticket attribute hashes (JSON-style) to post to
  # the CH API
  def import_tickets
    return unless options[:import][:enabled]
    import_dir = options[:import][:import_folder]
    output_dir = options[:import][:completed_folder]
    import = Import.new

    logger.info "Starting import from directory [#{import_dir}] with output directory [#{output_dir || 'n/a'}]"

    # ensure import directory is configured and exists
    err_msg = import.check_directory(import_dir)
    raise err_msg if err_msg

    # check each file the import thinks it can work with to see if we imported it previously
    skips = []
    import.importable_files(import_dir).each do |file|
      size = File.size(file)
      modified = File.mtime(file)
      if ImportedFile.where(file_name: file, size: size, modified: modified).count > 0
        logger.warn "Skipping file #{file} which was previously imported"
        skips << file
      end
    end

    # import folder and process each imported row
    import_results = import.from_folder(import_dir, output_dir, skips) do |row, log|
      if row[:origin_trip_id].nil?
        raise Import::RowError, "Imported row does not contain an origin_trip_id value"
      else
        handle_nested_objects!(row)
        handle_date_conversions!(row)
        # row = import_processor.process_trip_hash(row)

        # trips on the provider are uniquely identified by trip ID and appointment time because some trip tickets are
        # recycled, but these should represent new trips on the Clearinghouse and are stored as new trips in the
        # Adapter so the corresponding Clearinghouse IDs can each be stored

        trip = TripTicket.find_or_create_by_origin_trip_id_and_appointment_time(row[:origin_trip_id], Time.zone.parse(row[:appointment_time]))

        unless trip.synced?
          api_result = post_new_trip(row)
          log.info "POST trip ticket with API, result #{api_result}"
        else
          # trip is already tracked, see if we need to update the CH
          # Note: for now we just try an update and see what happens, we need to deal with error if no fields changed
          api_result = put_trip_changes(trip.ch_id, row)
          log.info "PUT trip ticket with API, result #{api_result}"
        end

        raise Import::RowError, "API result does not contain an ID" if api_result[:id].nil?

        trip.map_attributes(api_result.data).save!
      end
    end

    logger.info "Imported #{import_results.length} files"
    import_results.each do |r|
      logger.info r.to_s
      # as an extra layer of safety, record files that were imported so we can avoid reimporting them
      ImportedFile.create(r)
      # send notifications for files that contained errors
      if r[:error] || r[:row_errors].to_i > 0
        msg = "Encountered #{r[:row_errors]} errors while importing file #{r[:file_name]} at #{r[:created_at]}:\n#{r[:error_msg]}"
        begin
          AdapterNotification.new(error: msg).send
        rescue Exception => e
          logger.error "Error notification failed, could not send email: #{e}"
        end
      end
    end
  end

  protected

  # TODO - refactor into ExportProcessor
  def timestamp_string
    Time.zone.now.strftime("%Y-%m-%d.%H%M%S")
  end

  def most_recent_tracked_update_time
    TripTicket.maximum('ch_updated_at').try(:utc)
  end

  # Query CH for all trips/results/claims updated after that time where
  # our provider is originator or a claimant
  def get_updated_clearinghouse_trips(since_time)
    time_str = since_time.presence && (since_time.is_a?(String) ? since_time : since_time.strftime('%Y-%m-%d %H:%M:%S.%6N'))
    begin
      @clearinghouse.get('trip_tickets/sync', updated_since: time_str) || []
    rescue Exception => e
      api_error "API error on GET: #{e}"
    end
  end

  # Mark the trip and any known sub nodes as new or modified, then save
  # the trip_hash to the database
  def process_updated_clearinghouse_trip(trip_hash)
    # Don't bother with converting the hash to indifferent access, we
    # can just check for the ID key as both a symbol and a string
    if trip_hash[:id].nil? && trip_hash["id"].nil?
      @errors << "A trip ticket from the Clearinghouse was missing its ID. It will not be exported."
      return
    end
    
    # Ensure association hashes exist, even if empty
    trip_hash[:trip_claims]          ||= []
    trip_hash[:trip_ticket_comments] ||= []
    trip_hash[:trip_result]          ||= {}

    # Look up any existing trip data
    adapter_trip = TripTicket.find_by_ch_id(trip_hash[:id])

    if adapter_trip.nil?
      # save new trip in local database
      TripTicket.new.map_attributes(trip_hash).save!

      # mark the ticket and each associated object as a new record
      trip_hash[:trip_claims].map! {|claim| claim.merge!({new_record: true})}
      trip_hash[:trip_ticket_comments].map! {|comment| comment.merge!({new_record: true})}
      trip_hash[:trip_result].merge!({new_record: true}) unless trip_hash[:trip_result].blank?
      trip_hash.merge!({new_record: true})
    else
      # save a copy of the current data hash to use for comparison
      original_ch_data_hash = adapter_trip.ch_data_hash.deep_dup
      
      # save updated trip in local database
      adapter_trip.map_attributes(trip_hash).save!

      # mark new associated records as necessary, mark the trip as not
      # new
      mark_new_associations!(trip_hash[:trip_claims], original_ch_data_hash[:trip_claims] || [])
      mark_new_associations!(trip_hash[:trip_ticket_comments], original_ch_data_hash[:trip_ticket_comments] || [])
      trip_hash[:trip_result].merge!({new_record: original_ch_data_hash[:trip_result].blank?}) unless trip_hash[:trip_result].blank?
      trip_hash.merge!({new_record: false})
    end
    
    trip_hash
  end
  
  def mark_new_associations!(association_hashes, existing_hashes)
    existing_ids = existing_hashes.collect{|o| (o.try(:[], :id) || o.try(:[], "id")).to_i}
    association_hashes.map! do |association_hash|
      association_id = (association_hash.try(:[], :id) || association_hash.try(:[], "id")).to_i
      association_hash.merge!({new_record: !existing_ids.include?(association_id)})
    end
  end

  # TODO - refactor to ImportProcessor?
  def handle_nested_objects!(row)
    # support nested values for :customer_address, :pick_up_location, :drop_off_location, :trip_result
    # these can be included in the CSV file with the object name prepended, e.g. 'trip_result_outcome'
    # upon import they are removed from the row, then added back as nested objects,
    # e.g.: row['trip_result_attributes'] = { 'outcome' => ... })

    customer_address_hash = nested_object_to_hash(row, 'customer_address_')
    pick_up_location_hash = nested_object_to_hash(row, 'pick_up_location_')
    drop_off_location_hash = nested_object_to_hash(row, 'drop_off_location_')
    trip_result_hash = nested_object_to_hash(row, 'trip_result_')

    normalize_location_coordinates(customer_address_hash)
    normalize_location_coordinates(pick_up_location_hash)
    normalize_location_coordinates(drop_off_location_hash)

    row['customer_address_attributes'] = customer_address_hash if customer_address_hash.present?
    row['pick_up_location_attributes'] = pick_up_location_hash if pick_up_location_hash.present?
    row['drop_off_location_attributes'] = drop_off_location_hash if drop_off_location_hash.present?
    row['trip_result_attributes'] = trip_result_hash if trip_result_hash.present?
  end

  # TODO - refactor to ImportProcessor?
  def nested_object_to_hash(row, prefix)
    new_hash = {}
    row.select do |k, v|
      if k.to_s.start_with?(prefix)
        new_key = k.to_s.gsub(Regexp.new("^#{prefix}"), '')
        new_hash[new_key] = row.delete(k)
      end
    end
    new_hash
  end

  # TODO - refactor to ImportProcessor?
  # normalize accepted location coordinate formats to WKT
  # accepted:
  # location_hash['lat'] and location_hash['lon']
  # location_hash['position'] = "lon lat" (punction ignored except dash, e.g. lon:lat, lon,lat, etc.)
  # location_hash['position'] = "POINT(lon lat)"
  def normalize_location_coordinates(location_hash)
    lat = location_hash.delete('lat')
    lon = location_hash.delete('lon')
    position = location_hash.delete('position')
    new_position = position
    if lon.present? && lat.present?
      new_position = "POINT(#{lon} #{lat})"
    elsif position.present?
      match = position.match(/^\s*([\d\.\-]+)[^\d-]+([\d\.\-]+)\s*$/)
      new_position = "POINT(#{match[1]} #{match[2]})" if match
    end
    location_hash['position'] = new_position if new_position
  end

  # TODO - refactor to ImportProcessor?
  def handle_date_conversions!(row)
    # assume any date entered as ##/##/#### is mm/dd/yyyy, convert to
    # dd/mm/yyyy the way Ruby prefers
    changed = false
    row.each do |k,v|
      parts = k.rpartition('_')
      if parts[1] == '_' && ['date', 'time', 'at', 'on', 'dob'].include?(parts[2])
        if v =~ /^(\d{1,2})\/(\d{1,2})\/(\d{4})(.*)$/
          new_val = "#{ "%02d" % $2 }/#{ "%02d" % $1 }/#{ $3 }#{ $4 }"
          row[k] = new_val
          changed = true
        end
      end
    end
    changed
  end

  def post_new_trip(trip_hash)
    begin
      @clearinghouse.post(:trip_tickets, trip_hash)
    rescue Exception => e
      api_error "API error on POST: #{e}"
    end
  end

  def put_trip_changes(trip_id, trip_hash)
    begin
      @clearinghouse.put([ :trip_tickets, trip_id ], trip_hash)
    rescue Exception => e
      api_error "API error on PUT: #{e}"
    end
  end

  def api_error(message)
    if ENV["ADAPTER_ENV"] == 'development'
      # in development mode, don't suppress the original exception
      raise
    else
      raise Import::RowError, message
    end
  end

  def load_config(file)
    (YAML::load(File.open(file)) || {}).with_indifferent_access
  end

  def report_errors(error_message, errors)
    unless errors.blank?
      msg = "Encountered #{errors.length} errors while #{error_message}:\n" << errors.join("\n")
      begin
        AdapterNotification.new(error: error_message).send
      rescue Exception => e
        logger.error "Error notification failed, could not send email: #{e}"
      end
    end
  end
end

if __FILE__ == $0
  adapter_sync = AdapterSync.new
  adapter_sync.poll
end