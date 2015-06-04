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

require 'active_record'
require 'active_record_connection'
require 'active_support/core_ext/object'
require 'active_support/core_ext/hash'
require 'active_support/time_with_zone'
require 'import_processor'
require 'processors/processor_helpers'
require 'sqlite3'
require 'csv_import'
require_relative 'imported_file'

Time.zone = "UTC"

class ImportProcessor < Processor::Import::Base
  include Processors::ProcessorHelper

  def initialize(logger = nil, options = {})
    super
    setup_import_database
  end
  
  def process
    import_dir = options[:import_folder]
    raise RuntimeError, "Import folder not configured, will not check for files to import" if import_dir.blank?
    raise RuntimeError, "Import folder #{import_dir} does not exist" if Dir[import_dir].empty?

    logger.info "Starting import from directory #{import_dir}"

    importer = CsvImport.new(logger)
  
    # check each file the import thinks it can work with to see if we 
    # imported it previously
    skips = []
    importer.importable_files(import_dir).each do |file|
      size = File.size(file)
      modified = File.mtime(file)
      if ImportedFile.where(file_name: file, size: size, modified: modified).count > 0
        logger.warn "Skipping file #{file} which was previously imported"
        skips << file
      end
    end
  
    # import folder and process each imported row
    @import_results, trip_data = importer.from_folder(import_dir, skips)
    logger.info "Imported #{@import_results.size} files"
    
    @import_results.each do |r|
      @errors << "An error was encountered while importing #{r[:rows]} rows from file #{r[:file_name]} at #{r[:created_at]}:\n\t#{r[:error_msg]}\nThe file has been renamed and none of its rows were imported." if r[:error]
    end    
    
    trip_data.collect do |row|
      handle_nested_objects!(row)
      handle_array_and_hstore_attributes!(row)
      handle_date_conversions!(row)
      row
    end
  end
  
  # imported_rows, skipped_rows, and unposted_rows may contain data that
  # is useful in some circumstances, but we are ignoring it.
  def finalize(imported_rows = [], skipped_rows = [], unposted_rows =[])
    output_dir = options[:completed_folder]
    raise RuntimeError, "Import folder not configured, will not check for files to import" if output_dir.blank?
    raise RuntimeError, "Import folder #{directory} does not exist" if Dir[output_dir].empty?

    @import_results.each do |r|
      unless r[:error]
        # as an extra layer of safety, record files that were imported 
        # so we can avoid reimporting them
        ImportedFile.create(r)
        
        # Move the processed files to the output folder
        begin
          FileUtils.mv(r[:file_name], output_dir)
        rescue SystemCallError => e
          logger.error "Error marking file as imported, please make sure Adapter has read-write access to #{r[:file_name]} and directory #{output_dir}"
        end
      end
    end    
  end
  
  private

  def setup_import_database
    ImportedFile.logger = logger
    
    old_spec = nil
    if ActiveRecord::Base.connected?
      old_spec = ActiveRecord::Base.connection.instance_variable_get(:@config)
    end
    
    ActiveRecord::Base.establish_connection ImportedFile::CONNECTION_SPEC
    ActiveRecord::Migrator.migrate(File.join(File.expand_path(File.dirname(__FILE__)), 'basic_import_processor', 'migrations'))
    
    if old_spec.present?
      ActiveRecord::Base.establish_connection old_spec
    end
  end
end