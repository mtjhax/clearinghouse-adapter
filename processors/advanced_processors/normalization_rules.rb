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

# class Processors::AdvancedProcessors::NormalizationRules
#
# When exporting Adapter records and using the Advanced Export Processor,
# a custom configuration file can be used to check the values of imported
# fields against a list of matches, replace values with normalized
# replacements, output the normalized value with a different attribute
# name, and take various actions if there is no match for the value.
#
# Example rule:
#
# mobility_needs: {
#   normalizations: {
#     'wheelchair' => ['wheel chair', 'wheelchr'],
#     'scooter' => /scooter/
#   },
#   output_attribute: :mobility_requirement,
#   unmatched_action: [ :append, :notes, 'See notes field' ]
# }
#
# output_attribute is optional, if omitted input attribute name is preserved.
#
# Unmatched value action:
# :accept   - accepts original value as-is (default)
# :ignore   - ignores attribute and omits it from the output (not recommended)
# :append   - append to a notes field, with optional placeholder in the original field, e.g. "See notes".
#             uses the form: [:append, <name of attribute to append to>, <placeholder string>]
# :replace  - replace specified field with either input value or a specified replacement value
#             uses the form: [:replace, <name of attribute to replace>, <optional replacement value>]
#
# Note that these rules are applied AFTER the advanced processor mappings, so the input attribute
# names will be the mapped names, not the originals from the Adapter.

require 'active_support/core_ext'

module Processors
  module AdvancedProcessors
    class NormalizationRules

      attr_accessor :rules, :output

      def initialize(rules = nil)
        self.rules = rules.is_a?(Hash) ? rules.with_indifferent_access : load_configuration(rules) if rules
        self.rules ||= {}.with_indifferent_access
        self.output = {}
      end

      def load_configuration(config_file)
        YAML::load(File.open(config_file)).with_indifferent_access if config_file
      end

      def normalize_inputs(input_hash, subset_key = nil, output_hash = {})

        # allow storing data in a previous output hash (mostly for testing)
        self.output = (output_hash || {}).with_indifferent_access

        # use subset of rules if specified
        current_rules = subset_key && rules[subset_key] || rules
        rules_remaining = current_rules.dup

        input_hash.each do |input_name, input_value|
          # find input attribute name in the rules
          rule = current_rules[input_name]
          rules_remaining.delete(input_name)

          normalize_input_value rule, input_name, input_value
        end

        rules_remaining.each do |input_name, rule|
          normalize_input_value rule, input_name, nil
        end

        output
      end

      protected

      def normalize_input_value(rule, input_name, input_value)
        case rule
          when nil
            # if there is no rule for an input attribute, output it unchanged
            assign_to_output input_name, input_value
          when Hash
            # rules can be expressed as a hash
            process_rule input_name, input_value, rule[:normalizations], rule[:output_attribute], rule[:unmatched_action]
          when Array
            # compact rule syntax uses array: [ conversions, output_attr, unmatched_action ]
            process_rule input_name, input_value, *rule
          else
            raise "Invalid normalization rule: #{input_name}: #{rule}"
        end
      end

      def process_rule(input_name, input_value, normalizations, output_attribute = nil, unmatched_action = nil)
        # step 1 - check if there are any normalizations to apply
        normal_value = normalized_value(input_value, normalizations)

        # step 2 - if a value to normalize was found, output normalized version to specified output
        #          input name used as default output name if output name not specified
        assign_to_output(output_attribute.presence || input_name, normal_value)

        # step 3 - if value was not normalized, use default action if provided
        handle_unmatched_value input_name, input_value, output_attribute, unmatched_action if normal_value.nil?
      end

      def normalized_value(input_value, normalizations)
        matching_rules = normalizations.select do |k, v|
          if k == input_value
            # input is already an exact match for normal value
            true
          else
            case v
              when Array
                v.any? do |s|
                  if s.respond_to?(:casecmp)
                    s.casecmp(input_value) == 0
                  elsif s.respond_to?(:match)
                    !!s.match(input_value)
                  elsif s.nil?
                    input_value.nil?
                  else
                    raise "Normalization match set contains invalid entry: #{v}"
                  end
                end
              when String
                v.casecmp(input_value) == 0
              when Regexp
                !!v.match(input_value)
              when NilClass
                input_value.nil?
              else
                raise "Normalization rule has invalid match set: #{v || 'nil'}"
            end
          end
        end
        matching_rules.first.try(:first)
      end

      def handle_unmatched_value(input_name, input_value, output_attribute, unmatched_action)
        case unmatched_action.presence
          # default accepts original value unchanged
          when :accept, 'accept', nil
            assign_to_output output_attribute.presence || input_name, input_value
          when :ignore, 'ignore'
            # ignore the input - not recommended
          when Array
            if valid_append_action?(unmatched_action)
              append_to_output unmatched_action[1], input_name, input_value
              leave_placeholder input_name, output_attribute, unmatched_action
            elsif valid_replace_action?(unmatched_action)
              assign_to_output unmatched_action[1], unmatched_action[2] || input_value
            else
              raise "Normalization rule has invalid unmatched_action: #{unmatched_action || 'nil'}"
            end
          else
            raise "Normalization rule has invalid unmatched_action: #{unmatched_action || 'nil'}"
        end
      end

      def assign_to_output(attr_name, attr_value)
        output[attr_name] = attr_value
      end

      def append_to_output(attr_name, original_name, attr_value)
        if output[attr_name].present?
          output[attr_name] << "\\n"
        else
          output[attr_name] = ""
        end
        output[attr_name] << "#{original_name}: #{attr_value}"
      end

      def leave_placeholder(input_name, output_attribute, unmatched_action)
        assign_to_output output_attribute.presence || input_name, unmatched_action[2] if unmatched_action[2].present?
      end

      def valid_append_action?(unmatched_action)
        unmatched_action.is_a?(Array) &&
          (2..3).include?(unmatched_action.length) &&
          [:append, 'append'].include?(unmatched_action[0]) &&
          unmatched_action[1].presence &&
          [String, Symbol].include?(unmatched_action[1].class)
      end

      def valid_replace_action?(replace_action)
        replace_action.is_a?(Array) &&
          (2..3).include?(replace_action.length) &&
          [:replace, 'replace'].include?(replace_action[0]) &&
          replace_action[1].presence &&
          [String, Symbol].include?(replace_action[1].class)
      end

    end
  end
end
