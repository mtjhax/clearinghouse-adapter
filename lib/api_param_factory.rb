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

require 'base64'
require 'cgi'
require 'openssl'

require 'time'
require 'json'

module ApiParamFactory
  # Return the necessary parameters to make an authenticatable API call
  def self.provider_authenticatable_params(provider, additional_params = {})
    authenticatable_params(provider.api_key, provider.private_key, provider.generate_nonce, additional_params)
  end

  def self.authenticatable_params(api_key, private_key, nonce, additional_params = {})
    timestamp = Time.now.xmlschema
    required_params = {
      api_key:     api_key,
      nonce:       nonce,
      timestamp:   timestamp,
      hmac_digest: hmac_digest(private_key, nonce, timestamp, hash_stringify(additional_params))
    }
    flattened_params = hash_convert(additional_params)
    required_params.merge(flattened_params)
  end
  
  # Create an HMAC digest
  def self.hmac_digest(private_key, nonce, timestamp, request_params)
    digest = OpenSSL::HMAC.hexdigest('sha1', private_key, [nonce, timestamp, request_params.to_json].join(':'))
    digest
  end

  # Convert nested hash keys to flattened parameters, and turns all non-hash values to strings (because that's
  # how they'll be recieved on the API side)
  # Source: http://dev.mensfeld.pl/2012/01/converting-nested-hash-into-http-url-params-hash-version-in-ruby/
  def self.hash_convert(value, key = nil, out_hash = {})
    case value
    when Hash  then
      value.each { |k,v| hash_convert(v, append_key(key,k), out_hash) }
      out_hash
    when Array then
      value.each { |v| hash_convert(v, "#{key}[]", out_hash) }
      out_hash
    when nil   then ''
    else
      out_hash[key] = value.to_s
      out_hash
    end
  end

  # Convert all non-enumerable values to strings (because that's how they'll be recieved on the API side)
  def self.hash_stringify(value)
    case value
    when Hash  then
      value.each { |k,v| value[k] = hash_stringify(v) }
    when Array then
      value.collect { |v| hash_stringify(v) }
    when nil   then ''
    else
      value.to_s
    end
  end

  private

  def self.append_key(root_key, key)
    root_key.nil? ? :"#{key}" : :"#{root_key}[#{key.to_s}]"
  end
end