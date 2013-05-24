ENV["ADAPTER_ENV"] = "test"

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
