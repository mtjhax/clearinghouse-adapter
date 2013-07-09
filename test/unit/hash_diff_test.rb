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

require 'test_helper'
require 'hash_diff'

describe HashDiff do
  include HashDiff

  describe "#hash_diff" do
    it "should return nil if modified_hash is blank" do
      hash_diff({x:1}, {}).must_be_nil
    end

    it "should nest new hashes in a hash with key :_new" do
      hash_diff({}, { x:1 }).must_equal({ :_new => true, x:1 })
    end

    it "should nest modified hashes in a hash with key :_modified" do
      hash_diff({ x:1 }, { x:2 }).must_equal({ :_modified => true, x:2 })
    end

    it "should return a hash containing each entry in modified_hash that varies from original_hash" do
      hash_diff({ x:1, y:'2' }, { x:1, y:'99', z:3 }).must_equal({ :_modified => true, y:'99', z:3 })
    end

    it "should not return values which have not changed" do
      hash_diff({ x:1, y:'2' }, { x:1, y:'2', z:3 }).must_equal({ :_modified => true, z:3 })
    end

    it "should recurse into nested hashes" do
      original = { people: 1, tom: { age: 20 }}
      changed  = { people: 2, tom: { age: 21 }, sally: { age: 24 }}
      expected = { :_modified => true, people: 2, tom: { :_modified => true, age:21 }, sally: { :_new => true, age:24 }}
      hash_diff(original, changed).must_equal(expected)
    end

    it "should ignore original_hash entries that are absent in modified_hash" do
      hash_diff({ x:1, y:2, z:3 }, { y:99 }).must_equal({ :_modified => true, y:99 })
    end

    it "should return the entire array if an array of values has changed" do
      original = { values: [ 1, 2, 3, 4 ] }
      changed  = { values: [ 1, 3, 2, 4 ] }
      expected = { :_modified => true, values: [ 1, 3, 2, 4 ] }
      hash_diff(original, changed).must_equal(expected)
    end

    it "should always include required keys in results" do
      hash_diff({ x:1, y:2, z:3 }, { x:1, y:'2', z:3 }, 'z').must_equal({ :_modified => true, y:'2', z:3 })
    end

    it "should return only new and updated hashes if an array of hashes has changed" do
      original = { people: [{ id:1, name:'Tom' }, { id:2, name:'Silly' }, { id:3, name:'Roger' }] }
      changed  = { people: [{ id:2, name:'Sally' }, { id:3, name:'Roger' }, { id:4, name:'Jane' }] }
      expected = { :_modified => true, people: [{ :_modified => true, id:2, name:'Sally' }, { :_new => true, id:4, name:'Jane' }] }
      hash_diff(original, changed).must_equal(expected)
    end

    it "should treat a mixed array as an array of values" do
      original = { people: [1, 2, 3, { id:1, name:'Tom' }] }
      changed  = { people: [1, 2, 3, { id:1, name:'Tim' }] }
      expected = { :_modified => true, people: [1, 2, 3, { id:1, name:'Tim' }] }
      hash_diff(original, changed).must_equal(expected)
    end

    it "should treat an array of hashes that do not all contain 'id' keys as an array of values" do
      original = { people: [{ id:1, name:'Tom' }, { id:2, name:'Silly' }, { id:3, name:'Roger' }] }
      changed  = { people: [{ id:2, name:'Sally' }, { name:'Roger' }] }
      expected = { :_modified => true, people: [{ id:2, name:'Sally' }, { name:'Roger' }] }
      hash_diff(original, changed).must_equal(expected)
    end
  end

  describe "#clean_diff" do
    it "should remove :_new and :_modified keys from the input hash" do
      input = { :_modified => true, :_new => true, x:1, y:'2' }
      expected = { x:1, y:'2' }
      clean_diff(input).must_equal(expected)
    end

    it "should remove :_new and :_modified keys from nested hashes and arrays" do
      input = { :_modified => true, person: { :_new => true, id:4, name:'Jane' }, people: [{ :_modified => true, id:2, name:'Sally' }] }
      expected = { person: { id:4, name:'Jane' }, people: [{ id:2, name:'Sally' }] }
      clean_diff(input).must_equal(expected)
    end
  end
end
