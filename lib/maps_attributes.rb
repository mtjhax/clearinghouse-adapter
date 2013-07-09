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

require 'active_support/concern'
require 'active_support/core_ext/hash/indifferent_access'
require 'json'

# the MapsAttributes mixin provides a convenient way to map an input hash to attributes:
#
# - in a model class definition, use maps_attributes with a list of attributes to save from the input hash
# - map hash keys to attributes with different names with an array: maps_attributes ['from_hash_key', 'to_attr_name']
# - can serialize the entire hash (as JSON) to an attribute using ['*', 'all_my_data']
# - when creating a serialized attribute, a method is defined to return the value as a hash (e.g. all_my_data_hash)
#
# mapping is not automatic via update_attributes -- use map_attributes({}) to map hash values (does not save, but
# is chainable so you can use my_object.map_attributes({...}).save)

module MapsAttributes
  extend ActiveSupport::Concern

  included do
  end

  module ClassMethods
    def maps_attributes(*options)
      cattr_accessor :attribute_mappings
      self.attribute_mappings = (options || [])

      # define convenience method to return JSON serialized attributes as hashes
      attribute_mappings.each do |mapping|
        mapped_key, mapped_field = interpret(mapping)
        if mapped_key == '*'
          define_method("#{mapped_field}_hash") do
            val = self.send(mapped_field)
            val.nil? ? nil : JSON.parse(val).with_indifferent_access
          end
        end
      end
    end

    def interpret(mapping)
      if mapping.is_a?(Array)
        mapped_key = mapping[0].to_s
        mapped_field = (mapping[1] || mapping[0]).to_s
      else
        mapped_key = mapped_field = mapping.to_s
      end
      return mapped_key, mapped_field
    end
  end

  def map_attributes(attributes = {})
    attributes = attributes.with_indifferent_access
    output = {}
    attribute_mappings.each do |mapping|
      mapped_key, mapped_field = self.class.interpret(mapping)
      if mapped_key == '*'
        output[mapped_field] = attributes.to_json
      else
        output[mapped_field] = attributes[mapped_key] if attributes.has_key?(mapped_key)
      end
    end
    self.tap {|obj| obj.attributes = output }
  end

end

ActiveRecord::Base.send :include, MapsAttributes
