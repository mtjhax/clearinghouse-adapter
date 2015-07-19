source 'https://rubygems.org'

# gems needed by adapter_sync
gem 'sqlite3', '~>1.3'
gem 'activerecord', '~>4.2'

# gems needed by adapter_sync + api_client
gem 'rest-client'
gem 'activesupport'

# gems needed by adapter_monitor
gem 'mail', '~>2.6'
gem 'win32-service', '~>0.8', platforms: [:mswin, :mingw]

# gems needed by adapter_monitor_notification
gem 'slop'

group :test, :development do
  gem 'rake'
  gem 'minitest'
  gem 'factory_girl'
  gem 'database_cleaner'
  gem 'vcr'
  gem 'webmock'
  gem 'mocha', :require => false
end
