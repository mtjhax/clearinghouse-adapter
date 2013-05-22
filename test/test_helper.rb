ENV["ADAPTER_ENV"] = "test"

require 'minitest/autorun'
require 'minitest/spec'
require 'minitest/mock'
require 'factory_girl'
require 'mocha/setup'
require 'database_cleaner'

FactoryGirl.find_definitions

class MiniTest::Unit::TestCase
  include FactoryGirl::Syntax::Methods
end

class MiniTest::Spec
  include FactoryGirl::Syntax::Methods
end

#Dir[Rails.root.join("test/support/**/*.rb")].each {|f| require f}
