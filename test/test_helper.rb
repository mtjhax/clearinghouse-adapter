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

ENV["ADAPTER_ENV"] = "test"

require 'debugger'
require 'minitest/autorun'
require 'minitest/spec'
require 'minitest/mock'
require 'factory_girl'
require 'mocha/setup'
require 'database_cleaner'
require 'vcr'

FactoryGirl.find_definitions

class MiniTest::Unit::TestCase
  include FactoryGirl::Syntax::Methods
end

class MiniTest::Spec
  include FactoryGirl::Syntax::Methods
end

VCR.configure do |c|
  c.cassette_library_dir = 'test/vcr_cassettes'
  c.hook_into :webmock
  c.default_cassette_options = {
    :record => :new_episodes,
    :match_requests_on => [ :method, :host, :path ]
  }
end
