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

require 'csv'
require 'logger'
require 'fileutils'
require 'active_support/core_ext/hash/indifferent_access'

class CsvImport
  def initialize(logger = nil)
    @logger = logger || Logger.new(STDOUT)
  end

  def from_file(file)
    log "Importing #{file}"
    csv = CSV.open(file, headers: true, return_headers: false)
    data = csv.read
    csv.close
    data.collect{|row| HashWithIndifferentAccess[row.headers.zip(row.fields)]}
  end

  def from_folder(import_dir, skip_files = [])
    log "Starting import from directory #{File.expand_path(import_dir)}"
    import_files = importable_files(import_dir)
    log "Found #{import_files.length} files to import"

    results, data = [[], []]
    import_files.each do |file|
      if skip_files.include?(file)
        log "File #{file} skipped"
      else
        size = File.size(file)
        modified = File.mtime(file)
        begin
          rows = from_file(file)
          results << { file_name: file, size: size, modified: modified, error: false, rows: rows.size }
          rows.each{|row| data << row}
          log "Successfully imported #{rows.size} rows"
        rescue CSV::MalformedCSVError, SystemCallError => e
          # handles CSV parsing errors and file IO errors
          results << { file_name: file, size: size, modified: modified, error: true, error_msg: e.to_s }
          error "Error #{e.to_s}"
          file_error(file)
        end
      end
    end
    
    log "Directory import complete"
    
    [results, data]
  end

  def importable_files(directory)
    Dir[File.join(File.expand_path(directory), "*.{txt,csv}")] || []
  end

  protected

  def log(msg)
    @logger.info msg if @logger
  end

  def error(msg)
    @logger.error msg if @logger
  end

  def file_error(file)
    # rename the file '*.error' to prevent repeated attempts to import a bad file
    File.rename(file, file + '.error')
  rescue SystemCallError => e
    error "Error marking file as imported with errors, please make sure Adapter has read-write access to #{file}"
  end
end
