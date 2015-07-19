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

# This module includes helper functions for manipulating import and export data

require 'active_support'

module Processors
  module ProcessorHelper
    extend ActiveSupport::Concern

    #--------------------------------------------------------------------------------
    # import helpers

    # removes all row attributes starting with a particular prefix and
    # return them in a new hash with the prefix removed, for example:
    # { prefix_abc: 1, prefix_xyz: 2 } becomes { abc: 1, xyz: 2 }
    def nested_object_to_hash(row, prefix)
      new_hash = {}
      row.select do |k, v|
        if k.to_s.start_with?(prefix) && !k.to_s.end_with?('_attributes')
          new_key = k.to_s.gsub(Regexp.new("^#{prefix}"), '')
          new_hash[new_key] = row.delete(k)
        end
      end
      new_hash
    end

    # adds a hash to the row as a value using specified attribute name,
    # making sure to only overwrite specific nested attributes if the row
    # already contains a hash for that attribute
    def merge_hash_into_row(row, attribute_name, hash)
      if hash.present?
        row[attribute_name] = {}.with_indifferent_access unless row[attribute_name].is_a?(Hash)
        row[attribute_name].merge!(hash)
      end
    end

    def handle_nested_objects!(row)
      # support nested values for :customer_address, :pick_up_location,
      # :drop_off_location, :trip_result
      # These can be included in the CSV file with the object name
      # prepended, e.g. 'trip_result_outcome' upon import they are
      # removed from the row, then added back as nested objects,
      # e.g.: row['trip_result_attributes'] = { 'outcome' => ... })

      customer_address_hash = nested_object_to_hash(row, 'customer_address_')
      pick_up_location_hash = nested_object_to_hash(row, 'pick_up_location_')
      drop_off_location_hash = nested_object_to_hash(row, 'drop_off_location_')
      trip_result_hash = nested_object_to_hash(row, 'trip_result_')

      normalize_location_coordinates!(customer_address_hash)
      normalize_location_coordinates!(pick_up_location_hash)
      normalize_location_coordinates!(drop_off_location_hash)

      merge_hash_into_row row, 'customer_address_attributes', customer_address_hash
      merge_hash_into_row row, 'pick_up_location_attributes', pick_up_location_hash
      merge_hash_into_row row, 'drop_off_location_attributes', drop_off_location_hash
      merge_hash_into_row row, 'trip_result_attributes', trip_result_hash
    end

    # normalize accepted location coordinate formats to WKT
    # accepted:
    #   location_hash['lat'] and location_hash['lon']
    #   location_hash['position'] = "lon lat" (punctuation ignored except
    #     dash, e.g. lon:lat, lon,lat, etc.)
    #   location_hash['position'] = "POINT(lon lat)"
    def normalize_location_coordinates!(location_hash)
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

    def handle_array_and_hstore_attributes!(row)
      # In this example scenario, we know our transportation system outputs
      # certain array and hstore fields in a flattened format in the CSV
      # files, and we know that Rails expects these to be in array and
      # hash formats. We also know that these fields are given sequential
      # identifiers for each value/column.

      # array fields
      [
        :customer_eligibility_factors,
        :customer_mobility_factors,
        :customer_service_animals,
        :trip_funders
      ].each do |f|
        i = 1
        loop do
          key = "#{f}_#{i}"
          break unless row.keys.include?(key) && row[key].present?
          row[f] = [] unless row[f].is_a?(Array)
          row[f] << row.delete(key)
        end
        row[f].compact! if row[f].present?
      end

      # hstore fields
      [:customer_identifiers].each do |f|
        i = 0
        loop do
          i += 1
          key_key = "#{f}_#{i}_key"
          value_key = "#{f}_#{i}_value"
          break unless row.keys.include?(key_key) && row.keys.include?(value_key) && row[key_key].present?
          row[f] = {}.with_indifferent_access unless row[f].is_a?(Hash)
          row[f].merge!({row.delete(key_key) => row.delete(value_key)})
        end
      end
    end

    def handle_date_conversions!(row)
      # assume any date entered as ##/##/#### is mm/dd/yyyy, convert to
      # dd/mm/yyyy the way Ruby prefers
      changed = false
      row.each do |k, v|
        parts = k.to_s.rpartition('_')
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

    #--------------------------------------------------------------------------------
    # export helpers

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
    def flatten_hash(hash, except_keys = nil, prepend_name = nil)
      except_keys = except_keys && except_keys.map(&:to_sym) || []
      new_hash = {}
      hash.each do |key, value|
        new_key = [prepend_name, key.to_s].compact.join('_')
        if value.respond_to?(:each) && !except_keys.include?(key.to_sym)
          if value.is_a?(Hash)
            if [:customer_address, :pick_up_location, :drop_off_location, :originator, :address].include?(key.to_sym)
              # Recurse for known nested groups. Note that :address is under the :originator
              # node, so we catch it after the first round of recursion
              new_hash.merge!(flatten_hash(value, except_keys, new_key))
            else
              # Do not recurse otherwise. This is intended for use with hstore (key/value pair) attributes
              value.each_with_index do |(k,v),i|
                new_hash.merge!({"#{new_key}_#{i + 1}_key" => k, "#{new_key}_#{i + 1}_value" => v})
              end
            end
          elsif value.is_a?(Array)
            value.each_with_index do |v,i|
              new_hash.merge!({"#{new_key}_#{i + 1}" => v})
            end
          end
        else
          new_hash[new_key] = value
        end
      end
      new_hash
    end

  end
end