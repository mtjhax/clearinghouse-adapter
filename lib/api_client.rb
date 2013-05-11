require 'rest_client'
require 'api_param_factory'
require 'yaml'
require 'json'
require 'active_support/core_ext/hash/indifferent_access'

class ApiClient

  # options:
  # api_base_url: e.g. 'http://www.clearinghouse.org/api'
  # api_version:  e.g. 'v1'
  # api_key:      from provider API credentials
  # secret_key:   from provider API credentials
  # raw: true     causes the queries to return hashes instead of ApiClient instances (for processing larger datasets)

  def initialize(options_hash = {})
    @options = (options_hash || {}).with_indifferent_access

    @site = RestClient::Resource.new(@options.delete(:api_base_url))
    version = @options.delete(:api_version)
    @version = version.is_a?(String) ? version : "v#{ version || 1 }"
    @api_key = @options.delete(:api_key)
    @private_key = @options.delete(:api_private_key)

    @base_resource_path = nil
    @data_attributes = {}
    @nonce_sequence = 0
  end

  # REST-style request methods
  # returned objects are instances of this class and can be used to request nested objects
  # e.g. results returned by GET trip_tickets can be used to GET trip_ticket_comments

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

  protected

  def request(method, resource, additional_params = nil)
    resource = flatten([@base_resource_path, resource])
    params = method == :get ? { params: signed_params(additional_params) } : signed_params(additional_params)
    result = @site[versioned(resource)].send(method, params)
    process_result(resource, result)
  end

  def process_result(resource, result)
    result = JSON.parse(result)
    if @options[:raw]
      result
    else
      result = [result] unless result.is_a?(Array)
      result.map {|r| self.dup.tap {|dup| dup.set_attributes(resource, r) }}
    end
  end

  def set_attributes(resource_path, attributes)
    @base_resource_path = resource_path + (attributes['id'].blank? ? "" : "/#{attributes['id']}")
    @data_attributes = attributes
  end

  def versioned(resource)
    [@version, resource].compact.join('/')
  end

  def flatten(resource)
    case resource
      when Array
        flattened = resource.compact.each do |r|
          flatten(r)
        end
        flattened.join('/')
      else
        resource
    end
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
