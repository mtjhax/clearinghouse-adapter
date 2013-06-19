require 'active_support/core_ext/object'
require 'active_support/core_ext/hash'

module HashDiff

  # hash_diff returns a hash containing each entry in modified_hash that varies from original_hash.
  #
  # New and modified simple values are copied into the new hash. New and modified hashes are nested inside a
  # hash with key :_new or :_modified to indicate if the object in question did not exist in original_hash, or existed
  # but contained changes, respectively. For example:
  #
  # original_hash: { people: 1, tom: { age: 20 }}
  # modified_hash: { people: 2, tom: { age: 21 }, sally: { age: 24 }}
  # result:        { :_modified => { people: 2, tom: { :_modified => { age: 21 }}, sally: { :_new => { age: 24 }}}}
  #
  # hash_diff recurses into nested structures, only including key-value pairs in the nested structure
  # that are modified and omitting the entire nested structure if it is unchanged.
  #
  # If modified_hash is completely missing a key that exists in original_hash, this is not reflected in the results
  # as we can't extrapolate that a missing key means to set the original key to nil (in practice, the objects
  # returned by our API are not sparse and will contain "x"=>nil instead of omitting key "x").
  #
  # For arrays of hashes, the changes of each modified hash will be included in the returned array.
  # For arrays of values, the entire array will be returned if any values or orders are changed, otherwise the entire
  # array will be omitted. Anything in an array that is not a hash or doesn't have an 'id' key will result in the array
  # being treated as an array of values (but we should never get mixed arrays). Nested arrays will not be recursed into
  # (but again, arrays with nested arrays are unlikely we given that the data comes from a SQL table).
  #
  # required_keys indicate keys in the modified hash that will be included in results even if unchanged, unless
  # they are the only keys in the result. this does not apply to nested hashes or arrays (it is just needed to make
  # sure identifiers are always included).

  def hash_diff(original_hash, modified_hash, *required_keys)
    return nil if modified_hash.blank?
    return { :_new => modified_hash } if original_hash.blank?

    new_hash = {}
    diff_seen = false
    orig_hash = original_hash.with_indifferent_access

    modified_hash.each do |key, mod_value|
      orig_value = orig_hash[key]
      result = case mod_value
        when Hash
          # programmer.lazy? ? recurse : iterate (nesting structures won't be very deep so no problem)
          hash_diff(orig_value, mod_value).tap {|diff| diff_seen = true if diff.present? }
        when Array
          array_diff(orig_value, mod_value).tap {|diff| diff_seen = true if diff.present? }
        else
          # diff_seen lets us dump the result if the only keys in the result were required keys
          diff_seen = true if mod_value != orig_value
          required = required_keys.include?(key.to_sym) || required_keys.include?(key.to_s)
          (required || mod_value != orig_value) ? mod_value : nil
      end
      new_hash[key] = result if result.present?
    end

    new_hash.presence && diff_seen.presence && { :_modified => new_hash }  # return nil or the expression on the right
  end

  # array_diff is a helper to just handle comparing array sub-elements
  # nested object hashes are compared by ID
  # for arrays containing any non-hash values or hashes without IDs, the entire array is compared
  #
  # note that nested hashes won't have indifferent access so we check 'id' and :id for each entry when matching

  def array_diff(original_array, modified_array, *required_keys)
    return nil if modified_array.nil?
    return modified_array if original_array.nil?

    value_array = modified_array.index{|x| !x.is_a?(Hash) || (x['id'] || x[:id]).blank? }.present?
    if value_array
      modified_array == original_array ? nil : modified_array
    else
      new_array = []
      modified_array.each do |mod_hash|
        mod_hash_id = mod_hash['id'] || mod_hash[:id]
        orig_hash = original_array.find{|orig| orig.is_a?(Hash) && (orig['id'] || orig[:id]) == mod_hash_id }
        result = hash_diff(orig_hash, mod_hash, 'id')
        new_array << result if result.present?
      end
      new_array.presence  # nil or a non-empty array
    end
  end

end