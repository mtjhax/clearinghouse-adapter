# Copyright 2015 Ride Connection
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
require 'active_support/time_with_zone'
require 'hash'
require 'pp'

require 'api_client'
require 'active_record_connection'
require 'adapter_monitor_notification'
require 'export_processor'
require 'import_processor'

model_dir = File.join(File.dirname(__FILE__), 'model')
$LOAD_PATH.unshift(model_dir)
Dir[File.join(model_dir, "*.rb")].each {|file| require File.basename(file, '.rb') }

Time.zone = "UTC"

# This code should use exit(1) or raise an exception for errors that 
# should be considered a service "outage"
#
# Service outages should include things such as:
# - Import folders not configured, resulting in no work being done
# - Failure to connect to the Clearinghouse API
# - Any unforeseen exception
#
# Normal operating errors such as an invalid import file or a row that
# generates an API error should be logged and optionally cause a 
# notification, but don't really constitute an "outage" (although it
# would be nice if the user could configure what to consider a failure 
# vs. a normal error).

class AdapterSync
  BASE_DIR        = File.expand_path('..', File.dirname(__FILE__))
  LOG_FILE        = File.join(BASE_DIR, 'log', 'adapter_sync.log')
  CONFIG_FILE     = File.join(BASE_DIR, 'config', 'adapter_sync.yml')
  API_CONFIG_FILE = File.join(BASE_DIR, 'config', 'api.yml')
  DB_CONFIG_FILE  = File.join(BASE_DIR, 'config', 'database.yml')
  MIGRATIONS_DIR  = File.join(BASE_DIR, 'db', 'migrations')
  PROCESSORS_DIR  = File.join(BASE_DIR, 'processors')

  attr_accessor :options, :logger, :errors, :exported_trips, 
    :imported_trips, :export_processor, :import_processor
    
  def initialize(opts = nil)
    @logger = Logger.new(LOG_FILE, 'weekly')

    # support passing database and API configuration in params, opts[:database] and opts[:api]
    db_opts = opts.try(:delete, :database)
    api_opts = opts.try(:delete, :api)

    @options = load_config(CONFIG_FILE, opts)

    @errors, @exported_trips, @imported_trips = [[], [], []]

    # open the database, creating it if necessary, and make sure up to 
    # date with latest migrations
    @connection = ActiveRecordConnection.new(logger, load_config(DB_CONFIG_FILE, db_opts, ENV["ADAPTER_ENV"]))
    @connection.migrate(MIGRATIONS_DIR)

    # create connection to the Clearinghouse API
    apiconfig = load_config(API_CONFIG_FILE, api_opts, ENV["ADAPTER_ENV"])
    apiconfig['raw'] = false
    @clearinghouse = ApiClient.new(apiconfig)
    
    # create ExportProcessor and ImportProcessor instances
    @options[:export] ||= {}
    @options[:import] ||= {}
    require File.join(PROCESSORS_DIR, options[:export][:processor]) if options[:export][:enabled] && options[:export][:processor].present?
    require File.join(PROCESSORS_DIR, options[:import][:processor]) if options[:import][:enabled] && options[:import][:processor].present?
    @export_processor = ExportProcessor.new(logger, options[:export][:options])
    @import_processor = ImportProcessor.new(logger, options[:import][:options])
  end

  def poll
    @exported_trips, @imported_trips = [[], []]
    begin
      TripTicket.transaction do
        replicate_clearinghouse
        export_tickets
        import_tickets
      end
    rescue Exception => e
      error = e.message + "\n" + e.backtrace.join("\n")
      logger.error error
      report_errors "polling for changes", [error]
      raise e
    end
  end

  def replicate_clearinghouse
    @errors = []
    last_updated_at = most_recent_tracked_update_time
    trips = get_updated_clearinghouse_trips(last_updated_at)
    logger.info "Retrieved #{trips.length} updated trips from API"
    @exported_trips = trips.collect{|trip|
      trip_data = trip.data.deep_dup
      process_updated_clearinghouse_trip(trip_data)
    }.compact
    report_errors "syncing with the Ride Clearinghouse", errors
  end

  def export_tickets
    @errors = []
    return unless options[:export][:enabled]
    export_processor.process(exported_trips)
    report_errors "processing the exported trip tickets", export_processor.errors
  end

  def import_tickets
    @errors = []
    return unless options[:import][:enabled]
    @imported_trips = import_processor.process
    
    imported_rows, skipped_rows, unposted_rows = [[], [], []]
    @imported_trips.each_with_index do |trip_hash, index|
      trip_hash = trip_hash.with_indifferent_access
      if trip_hash[:origin_trip_id].nil?
        @errors << "A trip ticket from the local system did not contain an origin_trip_id value. It will not be imported."
        skipped_rows << trip_hash
      else
        begin
          appointment_time = Time.zone.parse(trip_hash[:appointment_time])
        rescue => e
          logger.error "Could not parse appointment_time value '#{trip_hash[:appointment_time]}' for trip on file line number #{index + 2}"
          raise e
        end

        adapter_trip = TripTicket.find_or_create_by(origin_trip_id: trip_hash[:origin_trip_id], appointment_time: appointment_time)

        unless adapter_trip.synced?
          api_result = post_new_trip(trip_hash)
          logger.info "POST trip ticket with API, result #{api_result}"
        else
          api_result = put_trip_changes(adapter_trip.ch_id, trip_hash)
          logger.info "PUT trip ticket with API, result #{api_result}"
        end

        if api_result[:id].nil?
          @errors << "API result does not contain an ID. Result data will not be saved."
          unposted_rows << trip_hash
        else
          adapter_trip.map_attributes(api_result.data).save!
          imported_rows << trip_hash
        end
      end
    end
    
    import_processor.finalize(imported_rows, skipped_rows, unposted_rows)
    
    report_errors "processing the imported trip tickets", import_processor.errors + errors
  end

  protected

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

  def post_new_trip(trip_hash)
    begin
      @clearinghouse.post(:trip_tickets, trip_hash)
    rescue Exception => e
      api_error "API error on POST: #{e}", trip_hash
    end
  end

  def put_trip_changes(trip_id, trip_hash)
    begin
      @clearinghouse.put([ :trip_tickets, trip_id ], trip_hash)
    rescue Exception => e
      api_error "API error on PUT: #{e}"
    end
  end

  def api_error(message, data = nil)
    if ENV["ADAPTER_ENV"] == 'development'
      # in development mode, don't suppress the original exception
      logger.error message
      logger.error data unless data.nil?
      raise
    else
      raise message
    end
  end

  def load_config(file, additional_options = {}, environment = nil)
    config = (YAML::load(File.open(file)) || {})
    (environment && config[environment] || config).merge(additional_options || {}).deep_symbolize_keys
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
