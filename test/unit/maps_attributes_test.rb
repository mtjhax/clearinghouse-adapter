require 'test_helper'
require 'active_record'
require 'maps_attributes'

describe MapsAttributes do

  it "should allow a model to cherrypick attributes from an input hash"
  it "should allow a model to map input hash keys to attributes with different names"
  it "should allow a model to serialize the input hash to an attribute"
  it "should define a method to access serialized attributes as a hash"
  it "should not save the model automatically"
  it "should allow method chaining with update_attributes"

end
