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

require 'rest_client'
require 'api_param_factory'
require 'yaml'
require 'json'
require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/inflector'

class ApiClient

  # options:
  # api_base_url: e.g. 'http://www.clearinghouse.org/api'
  # api_version:  e.g. 'v1'
  # api_key:      from provider API credentials
  # secret_key:   from provider API credentials
  # raw: true     causes the queries to return hashes instead of ApiClient instances (for processing larger datasets)

  attr_accessor :options

  def initialize(options_hash = {})
    @options = (options_hash || {}).with_indifferent_access

    @site = RestClient::Resource.new(@options.delete(:api_base_url))
    version = @options.delete(:api_version)
    @version = version.is_a?(String) ? version : "v#{ version || 1 }"
    @api_key = @options.delete(:api_key)
    @private_key = @options.delete(:api_private_key)

    @base_resource_path = nil
    @data_attributes = {}.with_indifferent_access
    @nonce_sequence = 0
  end

  # REST-style request methods
  #
  # unless raw:true option is used, returned objects are instances of this class and can be used to request
  # nested objects, e.g. results returned by get('trip_tickets/1').get('trip_ticket_comments')
  #
  # resources can be:
  # symbols:        :trip_tickets
  # strings:        "trip_tickets/1/trip_comments"
  # arrays:         ['trip_tickets', 1, :trip_comments]
  # nested arrays:  ['trip_tickets', 1, [:trip_comments, 2]]

  def get(resource, additional_params = {})
    request(:get, resource, additional_params)
  end

  def post(resource, additional_params)
    request(:post, resource, additional_params)
  end

  def put(resource, additional_params)
    request(:put, resource, additional_params)
  end

  def delete(resource)
    request(:delete, resource)
  end

  # allow returned objects to return attributes like a Hash

  def [](key)
    @data_attributes[key]
  end

  def []=(key, value)
    @data_attributes[key] = value
  end

  def to_s
    @data_attributes.to_s
  end

  # if we want to use all hash methods on the class...
  #def method_missing(method, *args)
  #  @data_attributes.send(method, *args)
  #end

  # access to result hash
  def data
    @data_attributes
  end

  protected

  def request(method, resource, additional_params = nil)
    resource = flatten([@base_resource_path, resource])
    resource_name = singular_resource_name(resource)
    if method == :get
      params = { params: signed_params(additional_params) }
    else
      params = signed_params({ resource_name => additional_params })
    end
    result = @site[versioned(resource)].send(method, params)
    # TODO consider rescuing RestClient exceptions and JSON-parsing e.response
    process_result(resource, result)
  end

  def process_result(resource, result)
    result = JSON.parse(result)
    if options[:raw]
      result
    else
      # convert raw results into dups of the current object with result data stored
      if result.is_a?(Array)
        result.map {|r| self.dup.tap {|dup| dup.set_attributes(resource, false, r) }}
      else
        self.dup.tap {|dup| dup.set_attributes(resource, true, result) }
      end
    end
  end

  def set_attributes(resource_path, singular_resource, attributes)
    @base_resource_path = resource_path
    @base_resource_path << "/#{attributes['id']}" unless singular_resource || attributes['id'].nil?
    @data_attributes = attributes.with_indifferent_access
  end

  def versioned(resource)
    [@version, resource].compact.join('/')
  end

  def flatten(resource)
    if resource.is_a?(Array)
      flattened = resource.compact.map {|r| flatten(r) }
      flattened.join('/')
    else
      resource
    end
  end

  def singular_resource_name(resource_path)
    # returns type of resource being accessed from its path
    # e.g. given 'trip_tickets/1/trip_ticket_comments/2' it should return 'trip_ticket_comment'
    # if path ends with two consecutive alphabetical segments, the last is assumed to be a custom action,
    # e.g. "trip_tickets/1/trip_ticket_comments/most_recent" should still return 'trip_ticket_comment'
    match = resource_path.match(/\/?([A-Za-z_-]+)(\/[A-Za-z_-]+)?[^A-Za-z_-]*$/)
    match[1].singularize if match
  end

  def nonce
    # current time + incremented sequence number should be unique, although not useful for debugging unless logged
    @nonce_sequence += 1
    "#{Time.now.to_i}:#{@nonce_sequence}"
  end

  def signed_params(additional_params = nil)
    ApiParamFactory.authenticatable_params(@api_key, @private_key, nonce, additional_params)
  end

end
