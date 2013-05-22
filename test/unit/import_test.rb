require 'test_helper'
require 'fileutils'
require 'import'
require 'support/import_helpers'

describe Import do
  include ImportHelpers

  before do
    @input_folder = 'tmp/_import_test'
    @output_folder = 'tmp/_import_test_out'
    FileUtils.mkpath @input_folder
    FileUtils.mkpath @output_folder
  end

  after do
    remove_test_folders(@input_folder, @output_folder)
  end

  describe "Import#from_file" do
    before do
      @headers = ['bread','milk','eggs']
      @data = [['wheat','skim','brown'],
              ['rye','whole','white']]
      @test_csv = create_csv(@input_folder, 'test.csv', @headers, @data)
    end

    it "imports the specified file and returns the raw data (CSV::Table)" do
      result = Import.new.from_file(@test_csv)
      result.must_be_kind_of(CSV::Table)
      result.length.must_equal 2
      result[0].headers.must_equal @headers
      result[0].fields.must_equal @data[0]
      result[1].fields.must_equal @data[1]
    end

    it "imports the specified file and invokes a block for each row" do
      block_calls = 0
      Import.new.from_file(@test_csv) do |row, logger|
        block_calls += 1
      end
      block_calls.must_equal 2
    end

    it "invokes block with a hash of row values and logger" do
      logger = Minitest::Mock.new
      logger.expect(:info, true, [String])
      Import.new.from_file(@test_csv) do |row, logger|
        row.must_be_kind_of(Hash)
        row.keys.must_equal @headers
        @data.must_include row.values
        logger.must_equal(logger)
      end
    end

    it "returns total row count and count of rows with errors" do
      row_num = 0
      count, error_count = Import.new.from_file(@test_csv) do |row, logger|
        row_num += 1
        raise Import::RowError, "Test Error" if row_num > 1
      end
      count.must_equal 2
      error_count.must_equal 1
    end

    it "only rescues Import::RowError" do
      Proc.new do
        Import.new.from_file(@test_csv) do |row, logger|
          raise RuntimeError, "Test Error"
        end
      end.must_raise(RuntimeError)
    end
  end

  describe "Import#from_folder" do
    before do
      @headers_1 = ['bread','milk','eggs']
      @data_1 = [['wheat','skim','brown'], ['rye','whole','white']]
      @test_csv_1 = create_csv(@input_folder, 'test_1.csv', @headers_1, @data_1)
      @headers_2 = ['creature','legs']
      @data_2 = [['spider',8], ['insect',6]]
      @test_csv_2 = create_csv(@input_folder, 'test_2.txt', @headers_2, @data_2)
    end

    it "requires a valid import directory" do
      response = Import.new.from_folder(File.join(@input_folder, '__no_dir'), nil) {}
      response.must_be_kind_of(Array)
      response.length.must_equal 1
      response[0].must_be_kind_of(Hash)
      response[0][:error].must_equal true
    end

    it "imports all files with .csv and .txt extensions" do
      response = Import.new.from_folder(@input_folder, nil) {}
      response.must_be_kind_of(Array)
      response.length.must_equal 2
      [@test_csv_1, @test_csv_2].must_include response[0][:file_name]
      [@test_csv_1, @test_csv_2].must_include response[1][:file_name]
    end

    it "includes expected result keys for each imported file" do
      response = Import.new.from_folder(@input_folder, nil) {}
      response.must_be_kind_of(Array)
      response.length.must_equal 2
      response[0][:size].must_be_kind_of(Integer)
      assert response[0][:size] > 0
      response[0][:modified].must_be_kind_of(Time)
      response[0][:error].must_equal false
      response[0][:rows].must_equal 2
      response[0][:row_errors].must_equal 0
    end

    it "ignores a specified list of files" do
      results = Import.new.from_folder(@input_folder, nil, [@test_csv_1]) {}
      results.must_be_kind_of(Array)
      results.length.must_equal 1
      results[0][:file_name].must_equal @test_csv_2
    end

    it "moves imported files to output directory if provided" do
      Import.new.from_folder(@input_folder, @output_folder, [@test_csv_1]) {}
      File.exist?(@test_csv_2).must_equal false
      File.exist?(File.join(@output_folder, 'test_2.txt')).must_equal true
    end

    it "renames imported files if no output directory provided" do
      Import.new.from_folder(@input_folder, nil, [@test_csv_1]) {}
      File.exist?(@test_csv_2).must_equal false
      File.exist?(File.join(@input_folder, 'test_2.txt.imported')).must_equal true
    end

    it "renames files with errors to prevent reimport" do
      Import.new.from_folder(@input_folder, nil, [@test_csv_1]) do
        raise CSV::MalformedCSVError
      end
      File.exist?(@test_csv_2).must_equal false
      File.exist?(File.join(@test_csv_2 + '.error')).must_equal true
    end

    it "rescues CSV parsing errors and indicates that the file contains errors" do
      bad_csv = create_illegal_csv(@input_folder, 'bad.csv')
      results = Import.new.from_folder(@input_folder, nil, [@test_csv_1, @test_csv_2]) {}
      results.must_be_kind_of(Array)
      results.length.must_equal 1
      results[0][:file_name].must_equal bad_csv
      results[0][:error].must_equal true
      results[0][:error_msg].must_be_kind_of(String)
    end

    it "logs to the output directory if provided" do
      Import.new.from_folder(@input_folder, @output_folder, [@test_csv_1]) {}
      File.exist?(File.join(@output_folder, 'import.log')).must_equal true
    end

    it "logs to the input directory if no output directory provided" do
      Import.new.from_folder(@input_folder, nil, [@test_csv_1]) {}
      File.exist?(File.join(@input_folder, 'import.log')).must_equal true
    end
  end

  describe "Import#check_directory" do
    it "returns an error if directory is nil" do
      Import.new.check_directory(nil).must_be_kind_of(String)
    end
    it "returns an error if directory does not exist" do
      Import.new.check_directory(File.join(@input_folder, '__no_dir')).must_be_kind_of(String)
    end
    it "returns nil if successful" do
      Import.new.check_directory(@input_folder).must_be_nil
    end
  end

  describe "Import#importable_files" do
    it "returns a list of all .csv and .txt files in the specified directory" do
      test_files = create_empty_files(@input_folder, 'test.txt', 'test.csv')
      importable_files = Import.new.importable_files(@input_folder)
      importable_files.length.must_equal 2
      importable_files.must_include test_files[0]
      importable_files.must_include test_files[1]
    end
  end
end
