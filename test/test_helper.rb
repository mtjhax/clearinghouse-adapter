ENV["RAILS_ENV"] = "test"

require 'rubygems'
gem 'minitest'

require 'minitest/autorun'
require 'minitest/spec'

#Dir[Rails.root.join("test/support/**/*.rb")].each {|f| require f}
