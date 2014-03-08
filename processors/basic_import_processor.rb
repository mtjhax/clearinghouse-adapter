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
require_relative 'basic_import_processor/csv_import'
require_relative 'basic_import_processor/imported_file'
require 'import_processor'
require 'sqlite3'

# TODO
require 'debugger'

# This is working example of an extended ImportProcessor class. To use
# this as the ImportProcessor in your adapter installation, simply 
# update the config/adapter_sync.yml file by specifying the path to this
# file as the import[:processor] value.

# All ImportProcessor instances must impliment two public methods: 
# #process and #finalize

# The #public method accepts no arguments. It should return an array of 
# hashes, each one representing all of the attributes for a trip ticket
# that the CH API would expect, and in the proper format. This does 
# require some knowledge of the structure of a trip ticket and it's 
# associated objects, so be sure you're comfortable with that before you
# make any changes. Where the data originates from and what sort of
# transformations you perofm on it is dependent on the local system and
# can be customized as neecessary. Some examples of what a custom
# ImportProcessor might do would be to massage data from the local
# transportation system into a format that is better suited for the
# clearinghouse API, or to pick up data directly from a database as
# opposed to reading from a file.

# In this example, the #process method will pick up CSV files from a
# directory, parse the contents, and finally format it to better 
# represent trip ticket data.

# The #finalize method accepts three arguments: imported_rows, 
# skipped_rows, and unposted_rows. Each of these is an array containing
# zero or more trip hashes. (The same hashes that were reterned by
# the #process method) The method should not return any value. While it
# is required that you define this method in your ImportProcessor
# class, it is not required that it actually do any thing. It is 
# provided as an optional end point for performing cleanup, reporting, 
# maintenance, etc. 

# In this example, we will use the #finalize method to move processed 
# files to a different directory, and to record the names of the files
# we processed so that we don't accidentally process them again later.

# The Processor::Import::Base class that your ImportProcessor will 
# inherit from includes an initializer which should not be overwritten.
# This initializer is already configured to accept any options that
# your custom processor may need. For instance, in this processor we
# need to specify the folders where our CSV files will be processed 
# from. Any options you'd like to make available to an instance of the  
# ExportProcessor can be specified in the config/adapter_sync.yml file
# under the import[:options] area. You can specify as many options
# as you need for your specific implementation.

# The initializer also instantiates the @logger and @errors instance
# variables. The @logger variable will be a standard logger object that
# you can write log messages to for debugging or informational
# purposes. The @errors variable is an array (initially empty), which
# you can assign any error messages that you would like to be sent to
# system admins after #process is called as part of the AdapterSync
# process.

Time.zone = "UTC"

class ImportProcessor < Processor::Import::Base
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
  
  def handle_nested_objects!(row)
    # support nested values for :customer_address, :pick_up_location, 
    # :drop_off_location, :trip_result
    # These can be included in the CSV file with the object name 
    # prepended, e.g. 'trip_result_outcome' upon import they are 
    # removed from the row, then added back as nested objects,
    # e.g.: row['trip_result_attributes'] = { 'outcome' => ... })
  
    customer_address_hash = nested_object_to_hash(row, 'customer_address_')
    pick_up_location_hash = nested_object_to_hash(row, 'pick_up_location_')
    drop_off_location_hash = nested_object_to_hash(row, 'drop_off_location_')
    trip_result_hash = nested_object_to_hash(row, 'trip_result_')
  
    normalize_location_coordinates!(customer_address_hash)
    normalize_location_coordinates!(pick_up_location_hash)
    normalize_location_coordinates!(drop_off_location_hash)
  
    row['customer_address_attributes'] = customer_address_hash if customer_address_hash.present?
    row['pick_up_location_attributes'] = pick_up_location_hash if pick_up_location_hash.present?
    row['drop_off_location_attributes'] = drop_off_location_hash if drop_off_location_hash.present?
    row['trip_result_attributes'] = trip_result_hash if trip_result_hash.present?
  end
  
  def nested_object_to_hash(row, prefix)
    new_hash = {}
    row.select do |k, v|
      if k.to_s.start_with?(prefix)
        new_key = k.to_s.gsub(Regexp.new("^#{prefix}"), '')
        new_hash[new_key] = row.delete(k)
      end
    end
    new_hash
  end
  
  # normalize accepted location coordinate formats to WKT
  # accepted:
  #   location_hash['lat'] and location_hash['lon']
  #   location_hash['position'] = "lon lat" (punctuation ignored except 
  #     dash, e.g. lon:lat, lon,lat, etc.)
  #   location_hash['position'] = "POINT(lon lat)"
  def normalize_location_coordinates!(location_hash)
    lat = location_hash.delete('lat')
    lon = location_hash.delete('lon')
    position = location_hash.delete('position')
    new_position = position
    if lon.present? && lat.present?
      new_position = "POINT(#{lon} #{lat})"
    elsif position.present?
      match = position.match(/^\s*([\d\.\-]+)[^\d-]+([\d\.\-]+)\s*$/)
      new_position = "POINT(#{match[1]} #{match[2]})" if match
    end
    location_hash['position'] = new_position if new_position
  end
  
  def handle_array_and_hstore_attributes!(row)
    # In this example scenaio, we know our transportation system outputs
    # certain array and hstore fields in a flattened format in the CSV 
    # files, and we know that Rails expects these to be in array and
    # hash formats. We also know that these fields are given sequential
    # identifiers for each value/column.

    # array fields
    [
      :customer_eligibility_factors,
      :customer_mobility_factors,
      :customer_service_animals,
      :trip_funders,
    ].each do |f|
      row[f] = []
      i = 1
      loop do 
        key = "#{f}_#{i}"
        break unless row.keys.include?(key) && row[key].present?
        row[f] << row.delete(key)
      end
      row[f].compact!
    end
    
    # hstore fields
    [:customer_identifiers].each do |f|
      row[f] = {}
      i = 0
      loop do 
        i += 1
        key_key = "#{f}_#{i}_key"
        value_key = "#{f}_#{i}_value"
        break unless row.keys.include?(key_key) && row.keys.include?(value_key) && row[key_key].present?
        row[f].merge!({row.delete(key_key) => row.delete(value_key)})
      end
    end
  end

  def handle_date_conversions!(row)
    # assume any date entered as ##/##/#### is mm/dd/yyyy, convert to 
    # dd/mm/yyyy the way Ruby prefers
    changed = false
    row.each do |k,v|
      parts = k.rpartition('_')
      if parts[1] == '_' && ['date', 'time', 'at', 'on', 'dob'].include?(parts[2])
        if v =~ /^(\d{1,2})\/(\d{1,2})\/(\d{4})(.*)$/
          new_val = "#{ "%02d" % $2 }/#{ "%02d" % $1 }/#{ $3 }#{ $4 }"
          row[k] = new_val
          changed = true
        end
      end
    end
    changed
  end
    
  def setup_import_database
    database_options = {
      adapter: "sqlite3",
      database: "db/basic_import_processor_#{ENV["ADAPTER_ENV"] || development}.sqlite3",
      pool: 5,
      timeout: 5000
    }
    
    ImportedFile.establish_connection database_options
    ImportedFile.logger = logger
        
    # setup the default ActiveRecord::Base.connection if one doesn't 
    # exist already. For instance, if this class is included from
    # AdapterSync, there will already be a default database connection.
    # If we are running it on it's own then no default will exist yet.
    # This is necessary for the migrations to work properly
    ActiveRecordConnection.new(logger, database_options) unless ActiveRecord::Base.connected?
    
    ActiveRecord::Migrator.migrate(File.join(File.expand_path(File.dirname(__FILE__)), 'basic_import_processor', 'migrations'))
  end
end