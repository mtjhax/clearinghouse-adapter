require 'test_helper'
require 'hash_diff'

describe HashDiff do
  include HashDiff

  describe "#hash_diff" do
    it "should return nil if modified_hash is blank" do
      hash_diff({x:1}, {}).must_be_nil
    end

    it "should nest new hashes in a hash with key :_new" do
      hash_diff({}, {x:1}).must_equal({ :_new => {x:1}})
    end

    it "should nest modified hashes in a hash with key :_modified" do
      hash_diff({x:1}, {x:2}).must_equal({ :_modified => {x:2}})
    end

    it "should return a hash containing each entry in modified_hash that varies from original_hash" do
      hash_diff({x:1, y:'2'}, {x:1, y:'99', z:3}).must_equal({ :_modified => {y:'99', z:3}})
    end

    it "should not return values which have not changed" do
      hash_diff({x:1, y:'2'}, {x:1, y:'2', z:3}).must_equal({ :_modified => {z:3}})
    end

    it "should recurse into nested hashes" do
      original = { people: 1, tom: { age: 20 }}
      changed  = { people: 2, tom: { age: 21 }, sally: { age: 24 }}
      expected = { :_modified => { people: 2, tom: { :_modified => { age:21 }}, sally: { :_new => { age:24 }}}}
      hash_diff(original, changed).must_equal(expected)
    end

    it "should ignore original_hash entries that are absent in modified_hash" do
      hash_diff({x:1, y:2, z:3}, {y:99}).must_equal({ :_modified => {y:99}})
    end

    it "should return the entire array if an array of values has changed" do
      original = { values: [ 1, 2, 3, 4 ] }
      changed  = { values: [ 1, 3, 2, 4 ] }
      expected = { :_modified => { values: [ 1, 3, 2, 4 ] }}
      hash_diff(original, changed).must_equal(expected)
    end

    it "should always include required keys in results" do
      hash_diff({x:1, y:2, z:3}, {x:1, y:'2', z:3}, 'z').must_equal({ :_modified => {y:'2', z:3}})
    end

    it "should return only new and updated hashes if an array of hashes has changed" do
      original = { people: [{ id:1, name:'Tom' }, { id:2, name:'Silly' }, { id:3, name:'Roger' }] }
      changed  = { people: [{ id:2, name:'Sally' }, { id:3, name:'Roger' }, { id:4, name:'Jane' }] }
      expected = { :_modified => { people: [{ :_modified => { id:2, name:'Sally' }}, { :_new => { id:4, name:'Jane' }}] }}
      hash_diff(original, changed).must_equal(expected)
    end

    it "should treat a mixed array as an array of values" do
      original = { people: [1, 2, 3, { id:1, name:'Tom' }] }
      changed  = { people: [1, 2, 3, { id:1, name:'Tim' }] }
      expected = { :_modified => { people: [1, 2, 3, { id:1, name:'Tim' }] }}
      hash_diff(original, changed).must_equal(expected)
    end

    it "should treat an array of hashes that do not all contain 'id' keys as an array of values" do
      original = { people: [{ id:1, name:'Tom' }, { id:2, name:'Silly' }, { id:3, name:'Roger' }] }
      changed  = { people: [{ id:2, name:'Sally' }, { name:'Roger' }] }
      expected = { :_modified => { people: [{ id:2, name:'Sally' }, { name:'Roger' }] }}
      hash_diff(original, changed).must_equal(expected)
    end

  end
end
