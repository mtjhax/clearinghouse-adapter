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

describe MapsAttributes do

  it "should allow a model to cherrypick attributes from an input hash"
  it "should allow a model to map input hash keys to attributes with different names"
  it "should allow a model to serialize the input hash to an attribute"
  it "should define a method to access serialized attributes as a hash"
  it "should not save the model automatically"
  it "should allow method chaining with update_attributes"

end
