# TODO create a gemfile and use bundler

require 'sqlite3'
require 'active_record'
require 'yaml'
require 'rbconfig'
require 'logger'

$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'api_client'

CONFIG_FILE = File.expand_path(File.join('..', 'config', 'database.yml'), File.dirname(__FILE__))
API_CONFIG_FILE = File.expand_path(File.join('..', 'config', 'api.yml'), File.dirname(__FILE__))
LOG_FILE = File.expand_path(File.join('..', 'log', 'adapter_sync.log'), File.dirname(__FILE__))
MIGRATIONS_DIR = File.expand_path(File.join('..', 'db', 'migrations'), File.dirname(__FILE__))

class ActiveRecordConnection
  attr_accessor :dbconfig

  def initialize(logger)
    @dbconfig = YAML::load(File.open(CONFIG_FILE))['development']
    ActiveRecord::Base.establish_connection @dbconfig
    ActiveRecord::Base.logger = logger

    # not used for SQLite?
    #ActiveRecord::Base.connection.create_database @dbconfig['database']

    # check to make sure SQLite database was created
    #ActiveRecord::Base.connection
    #unless File.exist?(@dbconfig['database'])
  end

  def migrate(version = nil)
    ActiveRecord::Migrator.migrate MIGRATIONS_DIR, version ? version.to_i : nil
  end
end

class AdapterTest < ActiveRecord::Base
end

begin
  logger = Logger.new(LOG_FILE, 'weekly')

  # open the database, creating it if necessary, and make sure up to date with latest migrations
  connection = ActiveRecordConnection.new(logger)
  connection.migrate

  logger.info "Creating 5 test database rows"
  5.times do |i|
    AdapterTest.create foo:"foo#{i}", bar:"bar#{i}"
  end

  rand_foo = rand(5)
  logger.info "Selecting row where column foo has value 'foo#{rand_foo}'"
  rows = AdapterTest.where(foo: "foo#{rand_foo}")
  logger.info "Selected #{rows.count} rows, first row: #{rows[0].attributes}"

  logger.info "Destroying all test database rows"
  AdapterTest.destroy_all

  # make some network connections to APIs
  logger.info "Requesting trip tickets via API"
  apiconfig = YAML::load(File.open(API_CONFIG_FILE))
  apiconfig[:raw] = false
  result = ApiClient.new(apiconfig).get(:trip_tickets)

  logger.info "Received #{result.length} trip tickets, requesting comments for each"
  result.each_with_index do |trip, i|
    comments = trip.get :trip_ticket_comments
    logger.info "Trip #{i}: ID #{trip['id']}, comments #{comments.length}"
  end

  # TODO REMOVE TEST CODE
  #test_crash_handling

rescue Exception => e
  logger.error e.message + "\n" + e.backtrace.join("\n")
  exit 1
end
