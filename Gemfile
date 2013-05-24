source 'https://rubygems.org'

# gems needed by sync
gem 'sqlite3', '~>1.3'
gem 'activerecord', '~>3.2'

# gems needed by sync + api wrapper
gem 'rest-client'
gem 'activesupport'

# gems needed by monitor
gem 'mail', '~>2.5'
gem 'win32-service', '~>0.7', platforms: [:mswin, :mingw]

group :test, :development do
  gem 'rake'
  gem 'minitest'
  gem 'factory_girl'
  gem 'database_cleaner'
  gem 'vcr'
  gem 'webmock'
  gem 'mocha', :require => false
end
