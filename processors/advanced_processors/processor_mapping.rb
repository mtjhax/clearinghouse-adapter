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

# class Processors::AdvancedProcessors::ProcessorMapping
#
# an import/export processor mapping is a hash where the keys are input attribute names and the values are
# either output attribute names or commands/transformations to apply to the input. the mapping hash can contain
# multiple sub-mappings for various object types which can then be referenced when mapping inputs to outputs.
#
# possible mapping values:
#
# simple field name as symbol or string
# array:
#   indicates a nested result, e.g. {car_type: [:car, :model]} maps car_type to output[:car][:model]
#   array with one entry uses input attribute name as output name, e.g. {car_type: [:car]} maps car_type to output[:car][:car_type]
#   nested arrays are supported, e.g. {car_color: [:car, [:appearance, :model]]} maps car_color to output[:car][:appearance][:model]
# hash indicates a command to perform, key values:
#   :truncate           - limit output to specified length, e.g. { middle_name: { truncate: [ :middle_initial, 1] }}
#   :prepend            - prepend input to target field, e.g. { phone_number: { prepend: [:phone_plus_extension, ' '] }}
#   :append             - append input to target field, e.g. { extension: { append: [:phone_plus_extension, ' '] }}
#   :split              - split input into multiple outputs, e.g. { phone_plus_extension: { split: [' ', :phone_number, :extension] }}
#   :and                - copy value to multiple output attributes, e.g. { phone_number: { and: [:day_phone, :evening_phone] }}
#   :or                 - copy value unless output already has a value, e.g. { evening_phone: { or: :phone_number }}
#   :match              - compare input value to regular expressions and output first match to corresponding attributes,
#                         e.g. { attr: { match: [ /\w+/, :first_word, /\d+/, :first_number ]}}
#   :key_values         - key-value pairs, e.g. input could be "home:123-555-1212,work:123-555-3434"
#                         mapping arguments are [field, separator, default key for entire value if no pairs found]
#                         e.g. [:phone_number_array, ':', :phone_number] maps input to { home: '123-555-1212', work: '123-555-3434' }
#                         in input value was simply '123-555-3434', would map to { phone_number: '123-555-3434' }
#   :key_value_merge    - merge hash attribute into a single string attribute using specified separator
#                         e.g. { car_parts: { key_value_merge: [ :parts, ','] }} would convert { car_parts: { doors: 2, wheels: 4 }}
#                         into { parts: "doors:2,wheels:4" }. Non-hash inputs are saved as a normal output.
#   :list               - list of values, mapping arguments: [field, separator], e.g. { alternate_numbers: { list: [:phone_number_array, '|'] }
#                         an input of "123-555-1212 | 123-555-3434" would map to { phone_number_array: ['123-555-1212', '123-555-3434'] }
#   :list_merge         - merge array attribute into a single string attribute using specified separator
#                         e.g. { car_parts: { list_merge: [ :parts, ','] }} would convert { car_parts: [ 'doors', 'wheels' ]}
#                         into { parts: "doors,wheels" }. Non-list inputs are saved as a normal output.
#   :ignore             - input is not copied to output (regardless of argument value), e.g. { ignore: false } still ignores value
#
# The special :__accept_unmapped__ key indicates how to handle unmapped attributes:
#   - a value of true/nil passes all unmapped attributes to output (this is the default behavior)
#   - a value of false (or anything else) will skip any unmapped attributes

require 'active_support/core_ext'

module Processors
  module AdvancedProcessors
    class ProcessorMapping

      attr_accessor :mappings, :output, :logger

      def initialize(mappings = nil, logger = nil)
        self.mappings = mappings.is_a?(Hash) ? mappings.with_indifferent_access : load_mapping_configuration(mappings) if mappings
        self.mappings ||= {}.with_indifferent_access
        self.output = {}
        self.logger = logger
      end

      def load_mapping_configuration(mapping_file)
        YAML::load(File.open(mapping_file)).with_indifferent_access if mapping_file
      end

      def keys(sub_key = nil)
        sub_key ? (mappings[sub_key].try(:keys) || []) : mappings.keys
      end

      def values(sub_key = nil)
        sub_key ? (mappings[sub_key].try(:values) || []) : mappings.values
      end

      def map_inputs(input_hash, sub_mapping_key = nil, output_hash = {})

        # allow storing data in a previous output hash (mostly for testing)
        self.output = (output_hash || {}).with_indifferent_access

        # use sub-mapping if specified
        current_mapping = sub_mapping_key && mappings[sub_mapping_key] || mappings
        mappings_remaining = current_mapping.dup
        mappings_remaining.delete(:__accept_unmapped__)

        # check mapping for :__accept_unmapped__ key indicating how to handle unmapped attributes:
        # - true/nil passes all unmapped attributes to output (this is the default behavior)
        # - false/anything else will skip any unmapped attributes
        accept_unmapped = [true, 'true', nil].include?(current_mapping[:__accept_unmapped__])

        input_hash.each do |input_name, input_value|
          # find input attribute name in the mappings
          mapping = current_mapping[input_name]
          mappings_remaining.delete(input_name)
          
          map_input_value output, mapping, input_name, input_value, accept_unmapped
        end

        # Include in the output any attributes not included in the input hash
        # logger.info "Mappings remaining: #{mappings_remaining}"
        mappings_remaining.each do |input_name, mapping|
          map_input_value output, mapping, input_name, nil, accept_unmapped
        end  

        output
      end

      protected

      def map_input_value(output, mapping, input_name, input_value, accept_unmapped)
        case mapping
          when Symbol, String
            # if mapping is a string or symbol, use it as the output attribute name
            assign_attribute output, mapping, input_name, input_value

          when Array
            # array indicates a nested result
            raise "Invalid nested attribute mapping: #{mapping}" unless valid_nested_attribute?(mapping)
            assign_attribute output, mapping, input_name, input_value

          when Hash
            # if mapping is a hash, it should contain a command to apply to input
            mapping.each do |cmd, args|
              process_command cmd, args, input_name, input_value, output
            end

          when true, 'true'
            # if mapping value is accept/true, copy value to output with same attr name
            assign_attribute output, input_name, input_name, input_value

          when nil
            # use default if unmapped
            assign_attribute output, input_name, input_name, input_value if accept_unmapped

          else
            raise "Invalid mapping: #{input_name}: #{mapping}"
        end
      end


      def process_command(cmd, args, input_name, input_value, output)
        case cmd.to_sym
          when :truncate
            raise "Invalid TRUNCATE arguments: #{args}" unless valid_truncate_args?(args)
            assign_attribute(output, args[0], input_name, input_value.try(:slice, 0, args[1]))

          when :prepend
            raise "Invalid PREPEND arguments: #{args}" unless valid_prepend_args?(args)
            assign_attribute(output, args[0], input_name, input_value) do |previous_value|
              use_separator = args[1] && previous_value && previous_value[0, args[1].length] != args[1]
              "#{input_value}#{args[1] if use_separator}#{previous_value}"
            end

          when :append
            raise "Invalid APPEND arguments: #{args}" unless valid_append_args?(args)
            assign_attribute(output, args[0], input_name, input_value) do |previous_value|
              use_separator = args[1] && previous_value && previous_value[-args[1].length, args[1].length] != args[1]
              "#{previous_value}#{args[1] if use_separator}#{input_value}"
            end

          when :split
            raise "Invalid SPLIT arguments: #{args}" unless valid_split_args?(args)
            value_array = input_value.split(args.shift).map(&:strip)
            args.each_with_index do |arg, i|
              assign_attribute output, arg, input_name, value_array[i]
            end

          when :and
            raise "Invalid AND arguments: #{args}" unless valid_and_args?(args)
            args.each do |arg|
              assign_attribute output, arg, input_name, input_value
            end

          when :or
            raise "Invalid OR arguments: #{args}" unless valid_or_args?(args)
            assign_attribute(output, args, input_name, input_value) {|previous_value| previous_value || input_value }

          when :match
            raise "Invalid MATCH arguments: #{args}" unless valid_match_args?(args)
            args.each_slice(2) do |regexp, attr|
              unless attr.nil?
                matched_value = input_value[regexp]
                assign_attribute(output, attr, input_name, matched_value) if matched_value
              end
            end

          when :key_values
            raise "Invalid KEY_VALUES arguments: #{args}" unless valid_key_value_args?(args)
            attr_name = args[0]
            separator = args[1] || ','
            default_key = args[2] || 'value'
            pair_arr = input_value.split(separator).map(&:strip).map {|str| str.split(':').map(&:strip).tap {|arr| arr.length == 1 ? arr.unshift(default_key) : arr }}
            assign_attribute output, attr_name, input_name, Hash[pair_arr].symbolize_keys

          when :key_value_merge
            raise "Invalid KEY_VALUE_MERGE arguments: #{args}" unless valid_key_value_merge_args?(args)
            attr_name = args[0]
            separator = args[1] || ','
            output_value = input_value.is_a?(Hash) ? input_value.map {|k, v| "#{k}:#{v}"}.join(separator) : input_value
            assign_attribute output, attr_name, input_name, output_value

          when :list
            raise "Invalid LIST arguments: #{args}" unless valid_list_args?(args)
            attr_name = args[0]
            separator = args[1] || ','
            list = input_value.split(separator).map(&:strip)
            assign_attribute output, attr_name, input_name, list

          when :list_merge
            raise "Invalid LIST_MERGE arguments: #{args}" unless valid_list_merge_args?(args)
            attr_name = args[0]
            separator = args[1] || ','
            output_value = input_value.is_a?(Array) ? input_value.join(separator) : input_value
            assign_attribute output, attr_name, input_name, output_value

          when :ignore
            # TODO we should probably log ignores and other activity

          else
            raise "Invalid transformation #{cmd}"
        end
      end

      def valid_attribute_name?(arg)
        [Symbol, String].include?(arg.class) && arg.to_s.length > 0
      end

      def valid_nested_attribute?(arg)
        return false unless arg.is_a?(Array) && [1, 2].include?(arg.length) && valid_attribute_name?(arg[0])
        until !arg[1] || valid_attribute_name?(arg[1])
          arg = arg[1]
          return false unless arg.is_a?(Array) && [1, 2].include?(arg.length) && valid_attribute_name?(arg[0])
        end
        true
      end

      def valid_attribute?(arg)
        valid_attribute_name?(arg) || valid_nested_attribute?(arg)
      end

      def assign_attribute(output, mapping, input_name, input_value)
        raise "Invalid mapping value: #{mapping}" unless valid_attribute?(mapping)

        # handle non-nested attribute names
        unless mapping.is_a?(Array)
          result = clean_result(block_given? ? yield(output[mapping]) : input_value)
          output[mapping.to_s] = result
          return
        end

        # loop until second value of array is not another nested attribute name
        until mapping[1].nil? || valid_attribute_name?(mapping[1])
          output[mapping[0].to_s] ||= {}.with_indifferent_access
          output = output[mapping[0]]
          mapping = mapping[1]
        end

        # save output
        # block receives previous value as a param and block result is assigned as new value
        mapping[1] ||= input_name
        result = clean_result(block_given? ? yield(output[mapping[0]].try(:[], mapping[1])) : input_value)
        if result && result.to_s.length > 0
          output[mapping[0].to_s] ||= {}.with_indifferent_access
          output[mapping[0].to_s][mapping[1].to_s] = result
        end
      end

      def clean_result(result)
        result.is_a?(String) ? result.strip : result
      end

      def valid_truncate_args?(args)
        args.is_a?(Array) && args.length == 2 && valid_attribute?(args[0]) && args[1].is_a?(Integer)
      end

      def valid_prepend_args?(args)
        args.is_a?(Array) && [1, 2].include?(args.length) && valid_attribute?(args[0])
      end

      def valid_append_args?(args)
        valid_prepend_args?(args)
      end

      def valid_split_args?(args)
        args.is_a?(Array) && args.length > 1 && [String, Regexp].include?(args[0].class) && args[1, args.length].select {|a| !valid_attribute?(a) }.empty?
      end

      def valid_and_args?(args)
        args.is_a?(Array) && args.length > 0 && args.select {|a| !valid_attribute?(a) }.empty?
      end

      def valid_or_args?(args)
        valid_attribute?(args)
      end

      def valid_match_args?(args)
        # must be array that alternates between regexps and attributes to map to, e.g. [/^\w+/, :x, /_\d+/, [:y, :z]]
        args.is_a?(Array) && args.each_with_index.map {|arg, i| i % 2 == 0 ? arg.is_a?(Regexp) : valid_attribute?(arg) }.inject {|r, x| r && x }
      end

      def valid_key_value_args?(args)
        args.is_a?(Array) && args.length > 0 && valid_attribute?(args[0]) &&
          (args[1].nil? || args[1].is_a?(String)) &&
          (args[2].nil? || [String, Symbol].include?(args[2].class))
      end

      def valid_key_value_merge_args?(args)
        args.is_a?(Array) && [1, 2].include?(args.length) && valid_attribute?(args[0]) && (args[1].nil? || args[1].is_a?(String))
      end

      def valid_list_args?(args)
        args.is_a?(Array) && args.length > 0 && valid_attribute?(args[0]) && (args[1].nil? || args[1].is_a?(String))
      end

      def valid_list_merge_args?(args)
        args.is_a?(Array) && [1, 2].include?(args.length) && valid_attribute?(args[0]) && (args[1].nil? || args[1].is_a?(String))
      end

    end
  end
end
