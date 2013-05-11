class ActiveRecordConnection
  attr_accessor :options

  def initialize(logger, options = {})
    @options = options || {}
    ActiveRecord::Base.logger = logger
    ActiveRecord::Base.establish_connection @options

    # not needed for SQLite
    #ActiveRecord::Base.connection.create_database @options['database']

    # check to make sure SQLite database was created
    #ActiveRecord::Base.connection
    #unless File.exist?(@options['database'])
  end

  def migrate(migrations_dir, version = nil)
    ActiveRecord::Migrator.migrate migrations_dir, version ? version.to_i : nil
  end
end
