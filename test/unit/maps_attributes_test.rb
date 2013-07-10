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
require 'active_record'
require 'maps_attributes'

class TestModel
  include MapsAttributes
  maps_attributes ['*', 'all_data'], ['foo', 'mapped_foo'], 'bar'

  attr_accessor :attributes

  def method_missing(method)
    attributes[method.to_s]
  end
end

describe MapsAttributes do
  before do
    @test_model = TestModel.new
  end

  it "should define a map_attributes method on the model" do
    @test_model.must_respond_to(:map_attributes)
  end

  it "should allow a model to cherrypick attributes from an input hash" do
    @test_model.map_attributes(x: 1, bar: 2, y: 3)
    @test_model.x.must_equal nil
    @test_model.bar.must_equal 2
    @test_model.y.must_equal nil
  end

  it "should allow a model to map input hash keys to attributes with different names" do
    @test_model.map_attributes(foo: 1)
    @test_model.foo.must_equal nil
    @test_model.mapped_foo.must_equal 1
  end

  it "should allow a model to serialize the input hash to an attribute" do
    @test_model.map_attributes(x: 1, y: 2, z: 3)
    @test_model.all_data.must_equal('{"x":1,"y":2,"z":3}')
  end

  it "should define a method to access serialized attributes as a hash" do
    @test_model.map_attributes(x: 1, y: 2, z: 3)
    @test_model.must_respond_to(:all_data_hash)
    @test_model.all_data_hash.must_equal({ 'x' => 1, 'y' => 2, 'z' => 3 })
  end

  it "should not save the model automatically" do
    @test_model.expects(:save).never
    @test_model.expects(:save!).never
    @test_model.map_attributes(x: 1, y: 2, z: 3)
  end

  it "should support method chaining by returning the model" do
    @test_model.map_attributes(x: 1, y: 2, z: 3).must_equal @test_model
  end
end
