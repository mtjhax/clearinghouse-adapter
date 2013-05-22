require 'minitest/autorun'
require 'fileutils'
require 'csv'

module ImportHelpers

  # helpers for testing Import class

  def create_csv(folder, file_name, headers = [], data = [])
    file_name = File.join(File.expand_path(folder), file_name)
    CSV.open(file_name, 'w' ) do |csv|
      csv << headers unless headers.empty?
      data.each do |row|
        csv << row unless row.empty?
      end
    end
    file_name
  end

  def create_illegal_csv(folder, file_name)
    file_name = File.join(File.expand_path(folder), file_name)
    File.open(file_name, 'w') {|f| f.write('"csv does not", "like spaces", "outside quotes"') }
    file_name
  end

  def create_empty_files(folder, *file_names)
    names = []
    file_names.each do |f|
      names << File.join(File.expand_path(folder), f)
      File.open(names.last, 'w') {}
    end
    names
  end

  def remove_test_files(*folders)
    folders.each do |f|
      FileUtils.rm_f Dir.glob(File.join(f, '*.*')) if File.exist?(f)
    end
  end

  def remove_test_folders(*folders)
    folders.each do |f|
      remove_test_files(*folders)
      FileUtils.rmdir f if File.exist?(f)
    end
  end

end
