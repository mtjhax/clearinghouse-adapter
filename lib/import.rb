require 'csv'
require 'active_support/core_ext/hash/indifferent_access'

# initialize with options such as:
# :new_folder => 'tmp/import'
# :done_folder => 'tmp/import_done'
#
# if passed a block, will call each block with a hash of row values
# if not passed a block, will return CSV::Table

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
    # TODO capture exceptions, particularly CSV::MalformedCSVError
    csv = CSV.open(file, headers: true, return_headers: false)
    if block_given?
      csv.each do |row|
        row_hash = Hash[row.headers.zip(row.fields)]
        log "Row: #{row}"
        yield(row_hash)
      end
    else
      data = csv.read
      log "Returning #{data.length} imported rows to caller"
    end
  end

  def import_folder(import_dir, &row_handler)
    if import_dir.nil?
      log "Import folder not configured, will not check for files to import"
    elsif Dir[import_dir].empty?
      log "Import folder #{import_dir} does not exist, will not check for files to import"
    else
      log "Checking folder #{File.expand_path(import_dir)} for files to import"
      import_files = Dir[File.join(File.expand_path(import_dir), "*.{txt,csv}")]
      log "Found #{import_files.length} files to import"
      import_files.each do |file|
        import(file) do |row|
          row_handler.call(row)
        end
      end
    end
  end
end
