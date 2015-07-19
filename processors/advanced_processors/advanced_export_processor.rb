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

require 'active_support/core_ext/object'
require 'active_support/core_ext/hash'
require 'active_support/time_with_zone'
require 'csv'
require 'export_processor'
require 'processors/processor_helpers'
require 'fileutils'
require_relative 'processor_mapping'

Time.zone = "UTC"

class ExportProcessor < Processor::Export::Base
  include Processors::ProcessorHelper

  attr_accessor :mapping

  def initialize(logger = nil, options = {})
    super

    # NOTE the advanced export processor wants a mapping configuration with three sub-mappings:
    # :trip_ticket, :trip_claim, and :trip_comment (trip results fields are included in trip ticket mapping)
    raise RuntimeError, "Mapping configuration file not specified" if options[:mapping_file].blank?
    self.mapping = Processors::AdvancedProcessors::ProcessorMapping.new(options[:mapping_file])
  end

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
    #
    # NOTE: any array or hstore attribute that uses advanced mapping does not need to be flattened,
    # because the mapping will do something different with it (most likely collect it into a single,
    # parseable attribute) so each call to flatten_hash will skip mapped attributes
    #
    {
      trip_updates: :trip_ticket,
      claim_updates: :trip_claim,
      comment_updates: :trip_comment,
      result_updates: :trip_result
    }.each do |rows, type_key|
      # flatten sub-hashes in the data by joining key values with underscores
      # e.g. row[primary][secondary] becomes row[primary_secondary]
      flattened_rows = []
      eval(rows.to_s).each { |x| flattened_rows << flatten_hash(x, mapping.keys(type_key)) }

      # ADVANCED PROCESSING - run each row through export mapping
      flattened_rows = flattened_rows.map {|row| mapping.map_inputs(row, type_key) }

      # create combined lists of keys since each change set can include different updated columns
      row_keys = []
      flattened_rows.each { |x| row_keys |= x.stringify_keys.keys }

      # create file name for exports
      timestamp = timestamp_string
      output_file = File.join(export_dir, "#{type_key.to_s.sub('comment', 'ticket_comment')}s.#{timestamp}.csv")

      # export to CSV
      export_csv(output_file, row_keys, flattened_rows)
    end
  end

end