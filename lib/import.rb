require 'csv'
require 'logger'
require 'fileutils'
require 'active_support/core_ext/hash/indifferent_access'

# Import
#
# A generic class to simplify importing a file or folder of files that logs results
# and prevents accidental reimport of the same file.
#
# If Logger object passed to initialize, import will log activity there.
#
# from_file imports a specific file and takes no further action. When passed a block,
# calls block for each row with a hash of row values and optional Logger to use.
# If not passed a block, will return raw data (CSV::Table).
#
# from_folder imports every file in the specified directory. Requires a block to handle rows,
# returns array of hashes containing:
# {
#   file_name:  string
#   size:       fize size
#   modified:   file last modified time
#   error:      true if fatal error and entire file not imported
#   error_msg:  string
#   rows:       count of rows successfully imported
#   row_errors: count of non-fatal errors (rows imported but not successfully processed)
#  }
#
# Blocks should raise Import::RowError if a row cannot be processed but import should
# continue -- result will contain a count of bad rows.
#
# If Logger object passed to initialize, import will log activity there.
# - Creates a log in :completed_folder if provided
# - Creates a log in :inbox_folder
#
# If from_folder passed a valid output_dir, imported files will be moved to that folder,
# Otherwise they will be renamed '*.imported' on completion to prevent accidental reimport.
#
# If a file contains errors, from_folder will rename the file '*.error' to prevent repeated
# attempts to reimport.
#
# TODO would be good if you could pass in a hash validations (fields required, format regexps, etc.)
# TODO can it log which specific lines of a CSV file have invalid data to help in diagnosing problems?

class Import
  class RowError < RuntimeError; end

  def initialize(logger = nil, options = {})
    @logger = logger
    @options = options || {}
  end

  def from_file(file)
    log "Importing #{file}"
    csv = CSV.open(file, headers: true, return_headers: false)
    data = csv.read
    csv.close
    if block_given?
      log "Processing #{data.length} rows"
      row_count = 0
      error_count = 0
      data.each do |row|
        row_hash = HashWithIndifferentAccess[row.headers.zip(row.fields)]
        log "Row #{row_count + 1} data: #{row}"
        begin
          yield(row_hash, @logger)
        rescue RowError => e
          error "Row #{row_count + 1} error: #{e}"
          error_count += 1
        end
        row_count += 1
      end
      return row_count, error_count
    else
      data
    end
  end

  def from_folder(import_dir, output_dir, skip_files = [], &row_handler)
    if err = check_directory(import_dir)
      return [{ file_name: nil, error: true, error_msg: err }]
    end

    @import_dir = import_dir
    @output_dir = output_dir if output_dir && output_dir != import_dir && !Dir[output_dir].empty?
    skip_files ||= []

    @logger ||= Logger.new(log_file_name, 'weekly')

    log "Starting import from directory #{File.expand_path(import_dir)}"
    import_files = importable_files(import_dir)
    log "Found #{import_files.length} files to import"

    results = []
    import_files.each do |file|
      if skip_files.include?(file)
        log "File #{file} skipped"
      else
        size = File.size(file)
        modified = File.mtime(file)
        begin
          row_count, error_count = from_file(file){ |row, logger| row_handler.call(row, logger) }
          results << { file_name: file, size: size, modified: modified, error: false, rows: row_count, row_errors: error_count }
          log "Successfully imported #{row_count - error_count} rows, #{error_count} rows had errors and could not be processed"
          file_completed(file)
        rescue CSV::MalformedCSVError, SystemCallError => e
          # handles CSV parsing errors and file IO errors
          results << { file_name: file, size: size, modified: modified, error: true, error_msg: e.to_s }
          error "Error #{e.to_s}"
          file_error(file)
        end
      end
    end
    log "Directory import complete"
    results
  end

  def check_directory(directory)
    return "Import folder not configured, will not check for files to import" if directory.nil?
    return "Import folder #{directory} does not exist" if Dir[directory].empty?
    nil
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

  def log_file_name
    File.join(@output_dir || @import_dir, 'import.log')
  end

  def file_completed(file)
    # If from_folder passed a valid output_dir, imported files will be moved to that folder,
    # Otherwise they will be renamed '*.imported' on completion to prevent accidental reimport
    if @output_dir
      FileUtils.mv(file, @output_dir)
    else
      File.rename(file, file + '.imported')
    end
  rescue SystemCallError => e
    error "Error marking file as imported, please make sure Adapter has read-write access to #{file}" +
          "#{ @output_dir.nil? ? '' : ' and directory ' }#{ @output_dir }"
  end

  def file_error(file)
    # rename the file '*.error' to prevent repeated attempts to import a bad file
    File.rename(file, file + '.error')
  rescue SystemCallError => e
    error "Error marking file as imported with errors, please make sure Adapter has read-write access to #{file}"
  end

end
