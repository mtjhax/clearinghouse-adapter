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

class ActiveRecordConnection
  attr_accessor :options

  def initialize(logger, options = {})
    @options = options || {}
    ActiveRecord::Base.default_timezone = :utc
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
