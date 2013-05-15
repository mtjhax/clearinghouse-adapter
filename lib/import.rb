require 'csv'
require 'active_support/core_ext/hash/indifferent_access'

# initialize with options such as:
# :new_folder => 'tmp/import'
# :done_folder => 'tmp/import_done'
#
# if import passed a block, will call each block with a hash of row values
# if not passed a block, will return CSV::Table
#
# import_folder requires a block to handle rows, returns array of hashes containing:
# file_name: string, rows: integer, error: true/false, error_msg: string

class Import
  def initialize(logger, options = {})
    @logger = logger
    @options = options || {}
  end

  def log(msg)
    @logger.info msg if @logger
  end

  def import(file)
    log "Importing #{file}"
    csv = CSV.open(file, headers: true, return_headers: false)
    data = csv.read
    if block_given?
      log "Importing #{data.length} rows"
      row_count = 0
      data.each do |row|
        row_hash = Hash[row.headers.zip(row.fields)]
        log "Row: #{row}"
        yield(row_hash)
        row_count += 1
      end
      row_count
    else
      data
    end
  end

  def import_folder(import_dir, &row_handler)
    results = []
    if import_dir.nil?
      log "Import folder not configured, will not check for files to import"
    elsif Dir[import_dir].empty?
      log "Import folder #{import_dir} does not exist, will not check for files to import"
    else
      # TODO create import log in the import folder, as well as log overall import result to main log
      # TODO log errors, return files, error counts to main code to be logged and for notification
      # TODO if import fails, stash name and timestamp to avoid reimporting that file
      # TODO if there is an output folder, move file there when finished

      log "Checking folder #{File.expand_path(import_dir)} for files to import"
      import_files = Dir[File.join(File.expand_path(import_dir), "*.{txt,csv}")]
      log "Found #{import_files.length} files to import"

      import_files.each do |file|
        begin
          row_count = import(file){ |row| row_handler.call(row) }
          results << { file_name: file, rows: row_count, error: false }
        rescue CSV::MalformedCSVError, SystemCallError => e
          # handles CSV parsing errors and file IO errors
          log "Error: #{e.to_s}"
          results << { file_name: file, error: true, error_msg: e.to_s }
        end
      end
    end
    results
  end
end
