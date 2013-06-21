$LOAD_PATH.unshift(File.dirname(__FILE__))

ENV["ADAPTER_ENV"] ||= 'development'

require 'sqlite3'
require 'active_record'
require 'yaml'
require 'rbconfig'
require 'logger'
require 'active_support/core_ext/object'
require 'active_support/core_ext/hash'
require 'active_support/time_with_zone'

require 'csv' # TODO for exporting results, but should extend the Import class to do exports instead

require 'api_client'
require 'active_record_connection'
require 'import'
require 'adapter_monitor_notification'

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

class AdapterSync
  LOG_FILE = File.expand_path(File.join('..', 'log', 'adapter_sync.log'), File.dirname(__FILE__))
  CONFIG_FILE = File.expand_path(File.join('..', 'config', 'adapter_sync.yml'), File.dirname(__FILE__))
  API_CONFIG_FILE = File.expand_path(File.join('..', 'config', 'api.yml'), File.dirname(__FILE__))
  DB_CONFIG_FILE = File.expand_path(File.join('..', 'config', 'database.yml'), File.dirname(__FILE__))
  MIGRATIONS_DIR = File.expand_path(File.join('..', 'db', 'migrations'), File.dirname(__FILE__))

  attr_accessor :options, :logger, :errors, :trip_updates, :claim_updates, :comment_updates, :result_updates

  def initialize(opts = {})
    @logger = Logger.new(LOG_FILE, 'weekly')
    @options = opts.presence || load_config(CONFIG_FILE)

    @errors = []
    @trip_updates = @claim_updates = @comment_updates = @result_updates = []

    # open the database, creating it if necessary, and make sure up to date with latest migrations
    @connection = ActiveRecordConnection.new(logger, load_config(DB_CONFIG_FILE)[ENV["ADAPTER_ENV"]])
    @connection.migrate(MIGRATIONS_DIR)

    # create connection to the Clearinghouse API
    apiconfig = load_config(API_CONFIG_FILE)[ENV["ADAPTER_ENV"]]
    apiconfig['raw'] = false
    @clearinghouse = ApiClient.new(apiconfig)
  end

  def poll
    errors = []
    trip_updates = claim_updates = comment_updates = result_updates = []
    replicate_clearinghouse
    export_changes
    report_sync_errors
    import_tickets
  rescue Exception => e
    logger.error e.message + "\n" + e.backtrace.join("\n")
    raise
  end

  # TODO this needs refactoring as its too long and complex
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
        # support nested values for :customer_address, :pick_up_location, :drop_off_location, :trip_result
        # these can be included in the CSV file with the object name prepended, e.g. 'trip_result_outcome'
        # they are removed from the row, then added back as nested objects, e.g.: row[:trip_result_attributes] = { ... })

        customer_address_hash = row.select {|k, v| row.delete(k) || true if k.to_s.start_with?('customer_address_') }
        pick_up_location_hash = row.select {|k, v| row.delete(k) || true if k.to_s.start_with?('pick_up_location_') }
        drop_off_location_hash = row.select {|k, v| row.delete(k) || true if k.to_s.start_with?('drop_off_location_') }
        trip_result_hash = row.select {|k, v| row.delete(k) || true if k.to_s.start_with?('trip_result_') }

        row['customer_address_attributes'] = customer_address_hash if customer_address_hash.present?
        row['pick_up_location_attributes'] = pick_up_location_hash if pick_up_location_hash.present?
        row['drop_off_location_attributes'] = drop_off_location_hash if drop_off_location_hash.present?
        row['trip_result_attributes'] = trip_result_hash if trip_result_hash.present?

        # trips on the provider are uniquely identified by trip ID and appointment time because some trip tickets are
        # recycled, but these should represent new trips on the Clearinghouse and are stored as new trips in the
        # Adapter so the corresponding Clearinghouse IDs can each be stored
        trip = TripTicket.find_or_create_by_origin_trip_id_and_appointment_time(row[:origin_trip_id], row[:appointment_time])

        unless trip.synced?
          api_result = post_new_trip(row)
          log.info "POST trip ticket with API, result #{api_result}"
        else
          # trip is already tracked, see if we need to update the CH
          # Note: for now we just try an update and see what happens, we need to deal with error if no fields changed
          api_result = put_trip_changes(row)
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
      # TODO combine import error reporting code with sync error code (see report_sync_errors method)
      if r[:error] || r[:row_errors].to_i > 0
        msg = "Encountered #{r[:row_errors]} errors while importing file #{r[:file_name]} at #{r[:created_at]}:\\n#{r[:error_msg]}"
        begin
          AdapterNotification.new(error: msg).send
        rescue Exception => e
          logger.error "Error notification failed, could not send email: #{e}"
        end
      end
    end
  end

  protected

  def replicate_clearinghouse
    last_updated_at = most_recent_tracked_update_time
    updated_trips = get_updated_clearinghouse_trips(last_updated_at)
    logger.debug "Retrieved #{updated_trips.length} updated trips from API"
    updated_trips.each {|trip_hash| process_updated_clearinghouse_trip(trip_hash) }
  end

  # TODO refactor to a separate Export class
  def export_changes
    return unless options[:export][:enabled]
    export_dir = options[:export][:export_folder]
    raise "Export folder not configured, will not export new changes detected on the Clearinghouse" if export_dir.blank?
    raise "Export folder #{export_dir} does not exist" if Dir[export_dir].empty?

    # flatten nested structures in the updated trips
    flattened_trips = flattened_claims = flattened_comments = flattened_results = []
    trip_updates.each { |x| flattened_trips << flatten_hash(x) }
    claim_updates.each { |x| flattened_claims << flatten_hash(x) }
    comment_updates.each { |x| flattened_comments << flatten_hash(x) }
    result_updates.each { |x| flattened_results << flatten_hash(x) }

    # create combined lists of keys since each change set can include different updated columns
    trip_keys = claim_keys = comment_keys = result_keys = []
    flattened_trips.each { |x| trip_keys |= x.stringify_keys.keys }
    flattened_claims.each { |x| claim_keys |= x.stringify_keys.keys }
    flattened_comments.each { |x| comment_keys |= x.stringify_keys.keys }
    flattened_results.each { |x| result_keys |= x.stringify_keys.keys }

    # create file names for exports
    timestamp = Time.zone.now.strftime("%Y-%m-%d.%H%M%S")
    trip_file = File.join(export_dir, "trip_tickets.#{timestamp}.csv")
    claim_file = File.join(export_dir, "trip_claims.#{timestamp}.csv")
    comment_file = File.join(export_dir, "trip_ticket_comments.#{timestamp}.csv")
    result_file = File.join(export_dir, "trip_results.#{timestamp}.csv")

    CSV.open(trip_file, headers: trip_keys, write_headers: true) do |csv|
      flattened_trips.each do |trip|
        csv << trip_keys.map { |key| trip[key] }
      end
    end
    CSV.open(claim_file, headers: claim_keys, write_headers: true) do |csv|
      flattened_claims.each do |claim|
        csv << claim_keys.map { |key| claim[key] }
      end
    end
    CSV.open(comment_file, headers: comment_keys, write_headers: true) do |csv|
      flattened_comments.each do |comment|
        csv << comment_keys.map { |key| comment[key] }
      end
    end
    CSV.open(result_file, headers: result_keys, write_headers: true) do |csv|
      flattened_results.each do |result|
        csv << result_keys.map { |key| result[key] }
      end
    end
  end

  # flatten hash structure, changing keys of nested objects to parentkey_nestedkey
  # arrays of sub-objects will be ignored
  # TODO refactor to a separate Export class
  def flatten_hash(hash, prepend_name = nil)
    new_hash = {}
    hash.each do |key, value|
      new_key = [prepend_name, key.to_s].compact.join('_')
      case value
        when Hash
          new_hash.merge!(flatten_hash(value, new_key))
        when Array
          hash_array = value.index{|x| x.is_a?(Hash) }.present?
          new_hash[new_key] = value unless hash_array
        else
          new_hash[new_key] = value
      end
    end
    new_hash
  end

  def most_recent_tracked_update_time
    TripTicket.maximum('ch_updated_at')
  end

  # Query CH for all trips/results/claims updated after that time where our provider is originator or a claimant
  # TODO if since_time nil, maybe omit resolved trips from API query since they should not change again

  def get_updated_clearinghouse_trips(since_time)
    time_str = since_time.is_a?(String) ? since_time : since_time.strftime('%Y-%m-%d %H:%M:%S.%6N')
    begin
      @clearinghouse.get('trip_tickets/sync', updated_since: time_str)
    rescue Exception => e
      api_error "API error on GET: #{e}"
    end
  end

  def process_updated_clearinghouse_trip(trip_hash)
    # TODO this is clunky, maybe raise exceptions and rescue them below
    if trip_hash[:id].nil?
      errors << { api_id_missing: "A trip ticket from the Clearinghouse was missing its ID" }
      return
    end

    adapter_trip = TripTicket.find_by_ch_id(trip_hash[:id])

    if adapter_trip.nil?
      trip_updates << { update_type: 'new_record' }.merge(trip_hash)
      TripTicket.new.map_attributes(trip_hash).save!
    else
      trip_diff = hash_diff(adapter_trip.ch_data_hash, trip_hash).with_indifferent_access

      # pluck the modifications to claims, comments, and results out of the trip to report them separately
      claims = trip_diff.delete(:trip_claims)
      comments = trip_diff.delete(:trip_ticket_comments)
      result = trip_diff.delete(:trip_result)

      # save results for export
      # make sure the trip_diff with the claims, comments, and results removed is not blank or just an ID
      clean_trip_diff = clean_diff(trip_diff)
      unless clean_trip_diff.blank? || clean_trip_diff.keys == ['id']
        trip_updates << { update_type: 'modified' }.merge(clean_trip_diff)
      end
      claims.each { |claim_diff| record_changes(claim_diff, claim_updates) }
      comments.each { |comment_diff| record_changes(comment_diff, comment_updates) }
      record_changes(result, result_updates) if result.present?

      adapter_trip.map_attributes(trip_hash).save!
    end
  end

  def record_changes(diff_hash, save_list)
    # TODO blow up if diff is not a hash or does not have ID key
    update_type = (diff_hash.has_key?(:_new) || diff_hash.has_key?('_new')) ? 'new_record' : 'modified'
    save_list << { update_type: update_type }.merge(clean_diff(diff_hash))
  end

  def post_new_trip(trip_hash)
    begin
      @clearinghouse.post(:trip_tickets, trip_hash)
    rescue Exception => e
      # TODO if exception indicates a duplicate object, we probably want to get the trip from the CH then try an update
      api_error "API error on POST: #{e}"
    end
  end

  def put_trip_changes(trip_hash)
    begin
      @clearinghouse.put(:trip_tickets, trip_hash)
    rescue Exception => e
      # TODO if exception indicates an error due to no changes, we should just ignore that error
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

  def report_sync_errors
    unless errors.blank?
      msg = "Encountered #{errors.length} errors while syncing with the Ride Clearinghouse:\\n" << errors.join("\\n")
      begin
        AdapterNotification.new(error: msg).send
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