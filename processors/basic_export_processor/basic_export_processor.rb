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

require 'active_support/core_ext/object'
require 'active_support/core_ext/hash'
require 'active_support/time_with_zone'
require 'csv'
require 'export_processor'
require 'fileutils'

Time.zone = "UTC"

class ExportProcessor < Processor::Export::Base
  def process(exported_trips)
    export_dir = @options[:export_folder]
    raise RuntimeError, "Export folder not configured, will not export new changes detected on the Clearinghouse" if export_dir.blank?
    raise RuntimeError, "Export folder #{export_dir} does not exist" if Dir[export_dir].empty?

    trip_updates, claim_updates, comment_updates, result_updates = [[], [], [], []]
    exported_trips.each do |trip|
      trip_data = trip.with_indifferent_access
      
      # pluck the modifications to claims, comments, and results out
      # of the trip to report them separately
      claims = trip_data.delete(:trip_claims) || []
      comments = trip_data.delete(:trip_ticket_comments) || []
      result = trip_data.delete(:trip_result) || {}

      # save results for export
      # make sure the trip_data with the claims, comments, and
      # results removed is not blank or just an ID
      unless trip_data.blank? || trip_data.keys == ['id']
        trip_updates << trip_data
      end
      claims.each { |claim| claim_updates << claim }
      comments.each { |comment| comment_updates << comment }
      result_updates << result unless result.blank?
    end    
    
    # flatten nested structures in the updated trips
    flattened_trips, flattened_claims, flattened_comments, flattened_results = [[], [], [], []]
    trip_updates.each { |x| flattened_trips << flatten_hash(x) }
    claim_updates.each { |x| flattened_claims << flatten_hash(x) }
    comment_updates.each { |x| flattened_comments << flatten_hash(x) }
    result_updates.each { |x| flattened_results << flatten_hash(x) }

    # create combined lists of keys since each change set can include
    # different updated columns
    trip_keys, claim_keys, comment_keys, result_keys = [[], [], [], []]
    flattened_trips.each { |x| trip_keys |= x.stringify_keys.keys }
    flattened_claims.each { |x| claim_keys |= x.stringify_keys.keys }
    flattened_comments.each { |x| comment_keys |= x.stringify_keys.keys }
    flattened_results.each { |x| result_keys |= x.stringify_keys.keys }

    # create file names for exports
    timestamp = timestamp_string
    trip_file = File.join(export_dir, "trip_tickets.#{timestamp}.csv")
    claim_file = File.join(export_dir, "trip_claims.#{timestamp}.csv")
    comment_file = File.join(export_dir, "trip_ticket_comments.#{timestamp}.csv")
    result_file = File.join(export_dir, "trip_results.#{timestamp}.csv")

    # export to CSV
    export_csv(trip_file, trip_keys, flattened_trips)
    export_csv(claim_file, claim_keys, flattened_claims)
    export_csv(comment_file, comment_keys, flattened_comments)
    export_csv(result_file, result_keys, flattened_results)
  end
  
  private
  
  def timestamp_string
    Time.zone.now.strftime("%Y-%m-%d.%H%M%S")
  end
  
  def export_csv(filename, headers, data)
    if data.present?
      CSV.open(filename, 'wb', headers: headers, write_headers: true) do |csv|
        data.each {|result| csv << headers.map { |key| result[key] }}
      end
    end
  end
  
  # flatten a trip's hash structure down to its root level. The data
  # we get from the CH API is predictable enough that we can make 
  # assumptions about the structure. For instance, we shouldn't need
  # to worry about deep nested objects, and we can expect the hash to
  # no more than 2-3 levels deep
  def flatten_hash(hash, prepend_name = nil)
    new_hash = {}
    hash.each do |key, value|
      new_key = [prepend_name, key.to_s].compact.join('_')
      case value
      when Hash
        case key.to_sym
        # Recurs for known nested groups. Note that :address is 
        # under the :originator node, so we catch it after the
        # first round of recursion
        when :customer_address, :pick_up_location, :drop_off_location, :originator, :address
          new_hash.merge!(flatten_hash(value, new_key))
        else
          # Do not recurs otherwise. This is intended for use with 
          # hstore (key/value pair) attributes
          value.each_with_index do |(k,v),i|
            new_hash.merge!({
              "#{new_key}_#{i + 1}_key" => k,
              "#{new_key}_#{i + 1}_value" => v
            })
          end
        end
      when Array
        value.each_with_index do |v,i|
          new_hash.merge!({"#{new_key}_#{i + 1}" => v})
        end
      else
        new_hash[new_key] = value
      end
    end
    new_hash
  end
end